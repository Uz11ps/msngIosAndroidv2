const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const sqlite3 = require('sqlite3');
const { open } = require('sqlite');
const https = require('https');
const querystring = require('querystring');
const bcrypt = require('bcrypt');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const JWT_SECRET = 'super_secret_key_123';
const PORT = 3000;

// Убедимся, что папка для загрузок существует
const uploadDir = 'uploads/';
if (!fs.existsSync(uploadDir)){
    fs.mkdirSync(uploadDir);
}

// API токен от Telegram Gateway
const TELEGRAM_GATEWAY_TOKEN = 'AAEqMQAAxLHukRbH3x_aYspgyiVgIhQhQZBU4_86f_RvOg';

app.use(cors());
// Increase JSON body limit so we can accept base64 uploads as a fallback when
// multipart uploads hang/timeout on some iOS network paths.
app.use(express.json({ limit: '25mb' }));
app.use('/uploads', express.static('uploads'));

// Some networks/proxies block or hang on direct static `/uploads/*` requests.
// Provide an API-shaped media endpoint so clients can fetch media through `/api/*`,
// which tends to be treated differently by DPI/carrier proxies.
app.get('/api/media/:filename', (req, res) => {
  try {
    const filename = path.basename(String(req.params.filename || ''));
    if (!filename) return res.status(400).json({ error: 'filename required' });
    const filePath = path.join(uploadDir, filename);
    if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'not found' });
    return res.sendFile(path.resolve(filePath));
  } catch (e) {
    console.error('api media error', e);
    return res.status(500).json({ error: 'media error' });
  }
});

// JSON chunked media download: avoids binary responses that some networks/proxies block/hang on.
// Public (same as /uploads). Client calls with { filename, offset, length }.
// NOTE: Cloudflare sometimes returns 520 for POST requests to certain API paths.
// Provide a GET variant on a different path to avoid POST body handling issues at the edge.
function _handleMediaChunk(filenameRaw, offsetRaw, lengthRaw, res) {
  const filename = path.basename(String(filenameRaw || ''));
  const offset = Number(offsetRaw || 0);
  const length = Number(lengthRaw || 24000);
  if (!filename) return res.status(400).json({ error: 'filename required' });
  if (!Number.isFinite(offset) || offset < 0) return res.status(400).json({ error: 'bad offset' });
  if (!Number.isFinite(length) || length <= 0 || length > 65536) return res.status(400).json({ error: 'bad length' });

  const filePath = path.join(uploadDir, filename);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'not found' });

  const stat = fs.statSync(filePath);
  const size = stat.size || 0;
  if (offset >= size) {
    return res.json({ eof: true, offset, size, dataBase64: '' });
  }

  const fd = fs.openSync(filePath, 'r');
  try {
    const toRead = Math.min(length, size - offset);
    const buf = Buffer.alloc(toRead);
    const read = fs.readSync(fd, buf, 0, toRead, offset);
    const slice = read === toRead ? buf : buf.subarray(0, read);
    return res.json({
      eof: offset + read >= size,
      offset,
      nextOffset: offset + read,
      size,
      dataBase64: slice.toString('base64'),
    });
  } finally {
    try { fs.closeSync(fd); } catch (_) {}
  }
}

app.get('/api/media_chunk', (req, res) => {
  try {
    return _handleMediaChunk(req.query && req.query.filename, req.query && req.query.offset, req.query && req.query.length, res);
  } catch (e) {
    console.error('api media chunk error', e);
    return res.status(500).json({ error: 'media chunk error' });
  }
});

// Backwards compatible aliases (older clients used this path).
app.get('/api/media/chunk', (req, res) => {
  try {
    return _handleMediaChunk(req.query && req.query.filename, req.query && req.query.offset, req.query && req.query.length, res);
  } catch (e) {
    console.error('api media chunk alias(get) error', e);
    return res.status(500).json({ error: 'media chunk error' });
  }
});

app.post('/api/media/chunk', (req, res) => {
  try {
    return _handleMediaChunk(req.body && req.body.filename, req.body && req.body.offset, req.body && req.body.length, res);
  } catch (e) {
    console.error('api media chunk alias(post) error', e);
    return res.status(500).json({ error: 'media chunk error' });
  }
});

const storage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => {
    cb(null, Date.now() + path.extname(file.originalname));
  }
});
const upload = multer({ storage });

let db;
(async () => {
  db = await open({
    filename: './database.sqlite',
    driver: sqlite3.Database
  });

  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      phoneNumber TEXT UNIQUE,
      email TEXT UNIQUE,
      password TEXT,
      displayName TEXT,
      photoUrl TEXT,
      status TEXT,
      lastSeen INTEGER,
      fcmToken TEXT
    );
    CREATE TABLE IF NOT EXISTS chats (
      id TEXT PRIMARY KEY,
      participants TEXT,
      lastMessage TEXT,
      lastMessageTimestamp INTEGER,
      isGroup INTEGER DEFAULT 0,
      groupName TEXT,
      groupAdminId TEXT
    );
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      chatId TEXT,
      senderId TEXT,
      text TEXT,
      type TEXT,
      mediaUrl TEXT,
      timestamp INTEGER,
      isRead INTEGER DEFAULT 0,
      replyToMessageId TEXT
    );
    CREATE TABLE IF NOT EXISTS blocked_users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      blocker_id TEXT NOT NULL,
      blocked_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      UNIQUE(blocker_id, blocked_id)
    );
    CREATE TABLE IF NOT EXISTS user_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reporter_id TEXT NOT NULL,
      reported_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      details TEXT,
      created_at INTEGER NOT NULL,
      status TEXT DEFAULT 'pending'
    );
    CREATE TABLE IF NOT EXISTS message_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reporter_id TEXT NOT NULL,
      message_id TEXT NOT NULL,
      chat_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      details TEXT,
      created_at INTEGER NOT NULL,
      status TEXT DEFAULT 'pending'
    );
  `);

  // Миграция: добавляем колонки email и password если их нет
  try {
    await db.exec("ALTER TABLE users ADD COLUMN email TEXT UNIQUE");
  } catch (e) {}
  try {
    await db.exec("ALTER TABLE users ADD COLUMN password TEXT");
  } catch (e) {}
  // Миграция: добавляем колонку replyToMessageId в messages если её нет
  try {
    await db.exec("ALTER TABLE messages ADD COLUMN replyToMessageId TEXT");
  } catch (e) {}
})();

// API: Вход по почте и паролю
app.post('/api/auth/email-login', async (req, res) => {
  const { email, password } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email и пароль обязательны' });
  }
  
  // Нормализуем email: убираем пробелы и приводим к нижнему регистру
  const normalizedEmail = email.trim().toLowerCase();
  
  // Простая валидация формата email
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({ success: false, message: 'Некорректный формат email. Проверьте правильность ввода.' });
  }
  
  try {
    // Ищем пользователя по email (без учета регистра)
    let user = await db.get('SELECT * FROM users WHERE LOWER(TRIM(email)) = ?', [normalizedEmail]);
    
    // Если не нашли по email, проверяем все пользователи с email
    if (!user) {
      const allUsers = await db.all('SELECT * FROM users WHERE email IS NOT NULL');
      user = allUsers.find(u => u.email && u.email.trim().toLowerCase() === normalizedEmail);
    }
    
    if (!user) {
      return res.status(400).json({ 
        success: false, 
        message: 'Пользователь с таким email не найден. Возможно, вы регистрировались по номеру телефона. Попробуйте войти через номер телефона или зарегистрируйтесь заново.' 
      });
    }
    
    if (!user.password) {
      return res.status(400).json({ 
        success: false, 
        message: 'Для этого аккаунта не установлен пароль. Вы регистрировались по номеру телефона. Войдите через номер телефона или привяжите пароль в профиле.' 
      });
    }

    // Backward compatibility: older builds could store plain-text password.
    // If legacy format is detected, allow login and transparently migrate to bcrypt.
    const hashPrefix = String(user.password).slice(0, 4);
    const looksHashed = hashPrefix === '$2a$' || hashPrefix === '$2b$' || hashPrefix === '$2y$';
    let isMatch = false;
    let shouldUpgradePasswordHash = false;
    if (looksHashed) {
      isMatch = await bcrypt.compare(password, user.password);
    } else {
      isMatch = String(password) === String(user.password);
      shouldUpgradePasswordHash = isMatch;
    }

    if (!isMatch) {
      return res.status(400).json({ success: false, message: 'Неверный пароль. Проверьте правильность ввода.' });
    }

    if (shouldUpgradePasswordHash) {
      try {
        const hashedPassword = await bcrypt.hash(password, 10);
        await db.run('UPDATE users SET password = ? WHERE id = ?', [hashedPassword, user.id]);
        user.password = hashedPassword;
      } catch (upgradeError) {
        console.error('[WARN] Failed to upgrade legacy password hash:', upgradeError.message);
      }
    }

    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    const safeUser = {
      id: user.id,
      phoneNumber: user.phoneNumber,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      status: user.status,
      lastSeen: user.lastSeen,
      fcmToken: user.fcmToken,
    };
    res.json({ success: true, token, user: safeUser });
  } catch (e) {
    console.error(`[ERROR] Login error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка сервера. Попробуйте позже.' });
  }
});

// API: Регистрация по почте
app.post('/api/auth/email-register', async (req, res) => {
  const { email, password, displayName } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email и пароль обязательны' });
  }
  
  // Нормализуем email: убираем пробелы и приводим к нижнему регистру
  const normalizedEmail = email.trim().toLowerCase();
  
  // Простая валидация email
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({ success: false, message: 'Некорректный формат email. Проверьте правильность ввода.' });
  }
  
  // Валидация пароля (минимум 6 символов)
  if (password.length < 6) {
    return res.status(400).json({ success: false, message: 'Пароль должен содержать минимум 6 символов' });
  }
  
  try {
    // Проверяем существование пользователя (без учета регистра)
    // Сначала проверяем прямой поиск по нормализованному email
    let existingUser = await db.get('SELECT * FROM users WHERE email = ?', [normalizedEmail]);
    
    // Если не нашли, проверяем все пользователи с email и сравниваем в коде
    if (!existingUser) {
      const allUsers = await db.all('SELECT * FROM users WHERE email IS NOT NULL');
      existingUser = allUsers.find(u => u.email && u.email.trim().toLowerCase() === normalizedEmail);
    }
    
    if (existingUser) {
      return res.status(400).json({ 
        success: false, 
        message: 'Пользователь с таким email уже зарегистрирован. Попробуйте войти или используйте другой email.' 
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const id = Date.now().toString();
    const finalDisplayName = (displayName || normalizedEmail.split('@')[0]).trim();
    
    try {
      await db.run(
        'INSERT INTO users (id, email, password, displayName) VALUES (?, ?, ?, ?)',
        [id, normalizedEmail, hashedPassword, finalDisplayName]
      );
    } catch (dbError) {
      // Если ошибка связана с уникальностью email (может быть race condition)
      if (dbError.message && (dbError.message.includes('UNIQUE constraint') || dbError.message.includes('UNIQUE'))) {
        // Проверяем еще раз, может быть пользователь был создан между проверками
        const checkUser = await db.get('SELECT * FROM users WHERE email = ?', [normalizedEmail]);
        if (checkUser) {
          return res.status(400).json({ 
            success: false, 
            message: 'Пользователь с таким email уже зарегистрирован. Попробуйте войти.' 
          });
        }
        return res.status(400).json({ 
          success: false, 
          message: 'Ошибка при создании аккаунта. Попробуйте еще раз.' 
        });
      }
      throw dbError; // Пробрасываем другие ошибки дальше
    }

    // Получаем созданного пользователя для возврата
    const newUser = await db.get('SELECT id, email, displayName FROM users WHERE id = ?', [id]);
    if (!newUser) {
      return res.status(500).json({ 
        success: false, 
        message: 'Ошибка при создании пользователя. Попробуйте еще раз.' 
      });
    }

    const user = { 
      id: newUser.id, 
      email: newUser.email, 
      displayName: newUser.displayName 
    };
    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    
    res.json({ success: true, token, user });
  } catch (e) {
    console.error(`[ERROR] Registration error for ${normalizedEmail}: ${e.message}`);
    console.error(`[ERROR] Stack: ${e.stack}`);
    res.status(500).json({ 
      success: false, 
      message: 'Ошибка сервера при регистрации. Попробуйте позже или обратитесь в поддержку.'
    });
  }
});

// Middleware для установки Content-Type для всех ответов
app.use((req, res, next) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  next();
});

// Добавим middleware для HTTP запросов (определяем ДО использования)
const authMiddleware = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return res.status(401).json({ success: false, error: 'No token' });
  }
  const token = authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ success: false, error: 'No token' });
  }
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }
    req.userId = decoded.id;
    next();
  });
};

// API: Обновление токена FCM
app.post('/api/users/fcm-token', async (req, res) => {
  const { id, fcmToken } = req.body;
  await db.run('UPDATE users SET fcmToken = ? WHERE id = ?', [fcmToken, id]);
  res.json({ success: true });
});

// API: Создание группового чата
app.post('/api/chats/group', authMiddleware, async (req, res) => {
  const { participants, groupName, adminId } = req.body;
  const chatId = 'group_' + Date.now();
  try {
    await db.run(
      'INSERT INTO chats (id, participants, lastMessageTimestamp, isGroup, groupName, groupAdminId) VALUES (?, ?, ?, ?, ?, ?)',
      [chatId, JSON.stringify(participants), Date.now(), 1, groupName, adminId]
    );
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    chat.participants = JSON.parse(chat.participants);
    
    // Уведомляем всех участников о создании группы
    participants.forEach(userId => {
      io.to(String(userId)).emit('chat_created', chat);
    });
    
    res.json(chat);
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Добавление участника в группу
app.post('/api/chats/:chatId/add-participant', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { userId } = req.body;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может добавлять участников' });
    }
    
    let participants = JSON.parse(chat.participants);
    if (!participants.includes(userId)) {
      participants.push(userId);
      await db.run(
        'UPDATE chats SET participants = ? WHERE id = ?',
        [JSON.stringify(participants), chatId]
      );
      
      // Уведомляем нового участника
      io.to(String(userId)).emit('chat_created', { ...chat, participants });
      
      res.json({ success: true, participants });
    } else {
      res.status(400).json({ success: false, error: 'Пользователь уже в группе' });
    }
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление участника из группы
app.post('/api/chats/:chatId/remove-participant', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { userId } = req.body;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может удалять участников' });
    }
    
    let participants = JSON.parse(chat.participants);
    participants = participants.filter(id => id !== userId);
    
    await db.run(
      'UPDATE chats SET participants = ? WHERE id = ?',
      [JSON.stringify(participants), chatId]
    );
    
    // Уведомляем удаленного участника
    io.to(String(userId)).emit('group_left', { chatId });
    
    res.json({ success: true, participants });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление группы
app.delete('/api/chats/:chatId', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может удалить группу' });
    }
    
    // Удаляем все сообщения группы
    await db.run('DELETE FROM messages WHERE chatId = ?', [chatId]);
    
    // Удаляем группу
    await db.run('DELETE FROM chats WHERE id = ?', [chatId]);
    
    // Уведомляем всех участников
    const participants = JSON.parse(chat.participants);
    participants.forEach(userId => {
      io.to(String(userId)).emit('group_deleted', { chatId });
    });
    
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление сообщения
app.delete('/api/chats/:chatId/messages/:messageId', authMiddleware, async (req, res) => {
  const { chatId, messageId } = req.params;
  try {
    const message = await db.get('SELECT * FROM messages WHERE id = ? AND chatId = ?', [messageId, chatId]);
    if (!message) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    // Проверяем, что пользователь является отправителем сообщения
    if (message.senderId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Можно удалять только свои сообщения' });
    }
    
    await db.run('DELETE FROM messages WHERE id = ?', [messageId]);
    
    // Уведомляем всех участников чата
    io.to(chatId).emit('message_deleted', { messageId, chatId });
    
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Обновление профиля
app.post('/api/users/update', authMiddleware, async (req, res) => {
  const { id, displayName, status, photoUrl } = req.body;
  
  // Проверяем, что пользователь обновляет свой профиль
  if (id !== req.userId) {
    return res.status(403).json({ success: false, error: 'Недостаточно прав для обновления этого профиля' });
  }
  
  await db.run(
    'UPDATE users SET displayName = ?, status = ?, photoUrl = ? WHERE id = ?',
    [displayName, status, photoUrl, id]
  );
  const user = await db.get('SELECT * FROM users WHERE id = ?', [id]);
  res.json({ success: true, user });
});

// API: Привязка почты к аккаунту (для пользователей, зарегистрированных по телефону)
app.post('/api/users/link-email', authMiddleware, async (req, res) => {
  const { email, password } = req.body;
  const userId = req.userId;
  
  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email и пароль обязательны' });
  }
  
  // Нормализуем email
  const normalizedEmail = email.trim().toLowerCase();
  
  // Валидация формата email
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({ success: false, message: 'Некорректный формат email' });
  }
  
  // Валидация пароля
  if (password.length < 6) {
    return res.status(400).json({ success: false, message: 'Пароль должен содержать минимум 6 символов' });
  }
  
  try {
    // Проверяем, что пользователь существует
    const user = await db.get('SELECT * FROM users WHERE id = ?', [userId]);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Пользователь не найден' });
    }
    
    // Проверяем, что email не занят другим пользователем
    const existingUser = await db.get('SELECT * FROM users WHERE email = ? AND id != ?', [normalizedEmail, userId]);
    if (existingUser) {
      return res.status(400).json({ success: false, message: 'Этот email уже используется другим аккаунтом' });
    }
    
    // Хешируем пароль
    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Обновляем пользователя: добавляем email и пароль
    await db.run(
      'UPDATE users SET email = ?, password = ? WHERE id = ?',
      [normalizedEmail, hashedPassword, userId]
    );
    
    // Получаем обновленного пользователя
    const updatedUser = await db.get('SELECT * FROM users WHERE id = ?', [userId]);
    res.json({ success: true, message: 'Почта успешно привязана', user: updatedUser });
  } catch (e) {
    console.error(`[ERROR] Link email error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка сервера. Попробуйте позже.' });
  }
});

// API: Привязка телефона к аккаунту (для пользователей, зарегистрированных по почте)
app.post('/api/users/link-phone', authMiddleware, async (req, res) => {
  const { phoneNumber, code } = req.body;
  const userId = req.userId;
  
  if (!phoneNumber || !code) {
    return res.status(400).json({ success: false, message: 'Номер телефона и код обязательны' });
  }
  
  // Нормализуем номер телефона
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  
  // Проверяем формат номера
  if (!normalizedPhone.startsWith('+7') || normalizedPhone.length !== 12) {
    return res.status(400).json({ success: false, message: 'Неверный формат номера телефона' });
  }
  
  // Проверяем код OTP
  const storedCode = otpStore.get(phoneNumber) || otpStore.get(normalizedPhone);
  if (!storedCode || storedCode !== code) {
    return res.status(400).json({ success: false, message: 'Неверный код подтверждения' });
  }
  
  try {
    // Проверяем, что пользователь существует
    const user = await db.get('SELECT * FROM users WHERE id = ?', [userId]);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Пользователь не найден' });
    }
    
    // Проверяем, что телефон не занят другим пользователем
    const existingUser = await db.get('SELECT * FROM users WHERE phoneNumber = ? AND id != ?', [normalizedPhone, userId]);
    if (existingUser) {
      return res.status(400).json({ success: false, message: 'Этот номер телефона уже используется другим аккаунтом' });
    }
    
    // Обновляем пользователя: добавляем телефон
    await db.run(
      'UPDATE users SET phoneNumber = ? WHERE id = ?',
      [normalizedPhone, userId]
    );
    
    // Удаляем использованный код
    otpStore.delete(phoneNumber);
    otpStore.delete(normalizedPhone);
    
    // Получаем обновленного пользователя
    const updatedUser = await db.get('SELECT * FROM users WHERE id = ?', [userId]);
    res.json({ success: true, message: 'Телефон успешно привязан', user: updatedUser });
  } catch (e) {
    console.error(`[ERROR] Link phone error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка сервера. Попробуйте позже.' });
  }
});

// Хранилище временных кодов OTP (в памяти для быстроты)
const otpStore = new Map();

// Функция для нормализации номера телефона в формат E.164 для Telegram Gateway
function normalizePhoneNumber(phone) {
  // Убираем все нецифровые символы
  let normalized = phone.replace(/\D/g, '');
  
  // Если номер начинается с 8, заменяем на 7
  if (normalized.startsWith('8')) {
    normalized = '7' + normalized.substring(1);
  }
  
  // Если номер не начинается с 7, добавляем 7 (для российских номеров)
  if (!normalized.startsWith('7') && normalized.length === 10) {
    normalized = '7' + normalized;
  }
  
  // Возвращаем в формате E.164 (+7XXXXXXXXXX)
  if (normalized.startsWith('7')) {
    return '+' + normalized;
  }
  
  return '+' + normalized;
}

// API: Отправка OTP через Telegram Gateway
app.post('/api/auth/send-otp', async (req, res) => {
  let responseSent = false;
  
  const sendResponse = (statusCode, data) => {
    if (!responseSent) {
      responseSent = true;
      res.status(statusCode).json(data);
    }
  };
  
  try {
    const { phoneNumber } = req.body;

    if (!phoneNumber || phoneNumber.trim() === '') {
      return sendResponse(400, { success: false, message: 'Номер телефона не указан' });
    }

    // Вход для гостя
    if (phoneNumber === '1111111111') {
      return sendResponse(200, { success: true, message: 'Guest login enabled. Use code 0000' });
    }

    // Нормализуем номер телефона в формат E.164 для Telegram Gateway
    const normalizedPhone = normalizePhoneNumber(phoneNumber);
    console.log(`[DEBUG] Original phone: ${phoneNumber}, Normalized: ${normalizedPhone}`);

    // Проверяем формат номера (должен быть в формате E.164, например +79991234567)
    if (!normalizedPhone.startsWith('+7') || normalizedPhone.length !== 12) {
      console.error(`[ERROR] Invalid phone format: ${normalizedPhone}`);
      return sendResponse(400, { 
        success: false, 
        message: 'Неверный формат номера телефона. Используйте формат: +7XXXXXXXXXX' 
      });
    }

    const code = Math.floor(1000 + Math.random() * 9000).toString();
    
    // Сохраняем код для обоих форматов номера (оригинального и нормализованного)
    otpStore.set(phoneNumber, code);
    otpStore.set(normalizedPhone, code);
    console.log(`[DEBUG] Generated OTP for ${phoneNumber} (${normalizedPhone}): ${code}`);
    
    // Отправляем SMS через Telegram Gateway API
    console.log(`[DEBUG] Attempting to send SMS to ${normalizedPhone} via Telegram Gateway API`);
    
    const requestData = {
      phone_number: normalizedPhone,
      code: code
    };
    
    const postData = JSON.stringify(requestData);
    
    const options = {
      hostname: 'gatewayapi.telegram.org',
      port: 443,
      path: '/sendVerificationMessage',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TELEGRAM_GATEWAY_TOKEN}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };
    
    // Создаем запрос к Telegram Gateway
    const telegramReq = https.request(options, (smsRes) => {
      let responseData = '';
      
      smsRes.on('data', (chunk) => {
        responseData += chunk;
      });
      
      smsRes.on('end', () => {
        try {
          if (!responseData) {
            throw new Error('Empty response from Telegram Gateway');
          }
          
          const result = JSON.parse(responseData);
          console.log(`[DEBUG] Telegram Gateway API response:`, JSON.stringify(result, null, 2));
          
          if (result.ok === true) {
            console.log(`[DEBUG] SMS sent successfully to ${normalizedPhone}`);
            sendResponse(200, { success: true, message: 'SMS код отправлен' });
          } else {
            const errorCode = result.error?.error_code || 'unknown';
            const errorDescription = result.error?.description || 'Ошибка отправки SMS';
            console.error(`[ERROR] SMS send error for ${normalizedPhone}: Code ${errorCode}, Description: ${errorDescription}`);
            
            // Более детальные сообщения об ошибках на основе кодов Telegram Gateway
            let userMessage = 'Не удалось отправить SMS. Проверьте номер телефона и попробуйте еще раз.';
            if (errorCode === 400 || errorDescription.includes('PHONE_NUMBER_INVALID')) {
              userMessage = 'Номер телефона указан неверно. Используйте формат: +7XXXXXXXXXX';
            } else if (errorCode === 401 || errorDescription.includes('ACCESS_TOKEN_INVALID')) {
              userMessage = 'Ошибка авторизации в Telegram Gateway. Обратитесь к администратору.';
            } else if (errorDescription.includes('insufficient')) {
              userMessage = 'Недостаточно средств на счете Telegram Gateway. Обратитесь к администратору.';
            }
            
            sendResponse(500, { 
              success: false, 
              message: userMessage,
              errorCode: errorCode,
              errorDetails: errorDescription
            });
          }
        } catch (parseError) {
          console.error(`[ERROR] Failed to parse Telegram Gateway response:`, parseError);
          console.error(`[ERROR] Response data:`, responseData);
          sendResponse(500, { 
            success: false, 
            message: 'Ошибка обработки ответа от Telegram Gateway. Попробуйте позже.',
            errorDetails: parseError.message
          });
        }
      });
    });
    
    // Устанавливаем таймаут на сокет (не на опции)
    telegramReq.setTimeout(10000, () => {
      console.error(`[ERROR] Telegram Gateway API request timeout`);
      telegramReq.destroy();
      sendResponse(500, { 
        success: false, 
        message: 'Таймаут при отправке SMS. Попробуйте позже.'
      });
    });
    
    telegramReq.on('error', (error) => {
      console.error(`[ERROR] Telegram Gateway API request error:`, error);
      sendResponse(500, { 
        success: false, 
        message: 'Ошибка подключения к Telegram Gateway. Попробуйте позже.',
        errorDetails: error.message
      });
    });
    
    // Отправляем данные и завершаем запрос
    telegramReq.write(postData);
    telegramReq.end();
  } catch (error) {
    console.error(`[ERROR] Unexpected error in send-otp:`, error);
    sendResponse(500, { 
      success: false, 
      message: 'Внутренняя ошибка сервера. Попробуйте позже.',
      errorDetails: error.message
    });
  }
});

app.post('/api/auth/verify-otp', async (req, res) => {
  const { phoneNumber, code, displayName } = req.body;
  
  if (!phoneNumber || !code) {
    return res.status(400).json({ success: false, message: 'Номер телефона и код обязательны' });
  }
  
  const isGuest = phoneNumber === '1111111111' && code === '0000';
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  
  // Проверяем код для обоих форматов номера
  const storedCode = otpStore.get(phoneNumber) || otpStore.get(normalizedPhone);
  const isValidCode = isGuest || storedCode === code || code === '1234'; // 1234 для теста

  if (isValidCode) {
    // Сохраняем оригинальный формат номера в БД
    let user = await db.get('SELECT * FROM users WHERE phoneNumber = ?', [phoneNumber]);
    if (!user) {
      // Также проверяем нормализованный формат
      user = await db.get('SELECT * FROM users WHERE phoneNumber = ?', [normalizedPhone]);
    }
    
    if (!user) {
      const id = Date.now().toString();
      const name = isGuest ? 'Гость' : (displayName || phoneNumber);
      await db.run('INSERT INTO users (id, phoneNumber, displayName) VALUES (?, ?, ?)', 
        [id, normalizedPhone, name]);
      user = await db.get('SELECT * FROM users WHERE id = ?', [id]);
      console.log(`[DEBUG] New user created: ${phoneNumber}`);
    }
    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    // Удаляем использованный код из хранилища для обоих форматов
    otpStore.delete(phoneNumber);
    otpStore.delete(normalizedPhone);
    console.log(`[DEBUG] OTP verified successfully for ${phoneNumber}`);
    res.json({ success: true, token, user });
  } else {
    console.log(`[DEBUG] Invalid OTP code for ${phoneNumber}. Expected: ${storedCode}, Got: ${code}`);
    res.status(400).json({ success: false, message: 'Неверный код подтверждения. Проверьте SMS и попробуйте еще раз.' });
  }
});

// Поиск пользователей
app.get('/api/users/search', async (req, res) => {
  const { query } = req.query;
  const searchQuery = query || '';
  const users = await db.all(
    'SELECT id, phoneNumber, email, displayName, photoUrl FROM users WHERE phoneNumber LIKE ? OR displayName LIKE ? OR email LIKE ? LIMIT 50',
    [`%${searchQuery}%`, `%${searchQuery}%`, `%${searchQuery}%`]
  );
  res.json(users);
});

// Получение пользователя по ID
// Block user endpoint
app.post('/api/users/block', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const blockerId = req.user.id;

    if (!userId || userId === blockerId) {
      return res.status(400).json({ success: false, message: 'Неверный запрос' });
    }

    // Check if already blocked
    const existing = await db.get(
      'SELECT * FROM blocked_users WHERE blocker_id = ? AND blocked_id = ?',
      [blockerId, userId]
    );

    if (existing) {
      return res.json({ success: true, message: 'Пользователь уже заблокирован' });
    }

    // Insert block record
    await db.run(
      'INSERT INTO blocked_users (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)',
      [blockerId, userId, Date.now()]
    );

    // Notify admin about the block (for moderation purposes)
    console.log(`[MODERATION] User ${blockerId} blocked user ${userId}`);

    res.json({ success: true, message: 'Пользователь заблокирован' });
  } catch (e) {
    console.error(`[ERROR] Block user error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка блокировки пользователя' });
  }
});

// Report user endpoint
app.post('/api/users/report', authMiddleware, async (req, res) => {
  try {
    const { userId, reason, details } = req.body;
    const reporterId = req.user.id;

    if (!userId || !reason) {
      return res.status(400).json({ success: false, message: 'Неверный запрос' });
    }

    // Insert report record
    await db.run(
      'INSERT INTO user_reports (reporter_id, reported_id, reason, details, created_at, status) VALUES (?, ?, ?, ?, ?, ?)',
      [reporterId, userId, reason, details || null, Date.now(), 'pending']
    );

    console.log(`[MODERATION] User ${reporterId} reported user ${userId} for: ${reason}`);

    // Admin should review reports within 24 hours (as per Apple requirements)
    // In production, you might want to send an email/notification to admins here

    res.json({ success: true, message: 'Жалоба отправлена. Администрация рассмотрит её в течение 24 часов.' });
  } catch (e) {
    console.error(`[ERROR] Report user error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка отправки жалобы' });
  }
});

// Report message endpoint
app.post('/api/messages/report', authMiddleware, async (req, res) => {
  try {
    const { messageId, chatId, reason, details } = req.body;
    const reporterId = req.user.id;

    if (!messageId || !chatId || !reason) {
      return res.status(400).json({ success: false, message: 'Неверный запрос' });
    }

    // Get message to find sender
    const message = await db.get('SELECT * FROM messages WHERE id = ?', [messageId]);
    if (!message) {
      return res.status(404).json({ success: false, message: 'Сообщение не найдено' });
    }

    // Insert report record
    await db.run(
      'INSERT INTO message_reports (reporter_id, message_id, chat_id, sender_id, reason, details, created_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [reporterId, messageId, chatId, message.sender_id, reason, details || null, Date.now(), 'pending']
    );

    console.log(`[MODERATION] User ${reporterId} reported message ${messageId} from user ${message.sender_id} for: ${reason}`);

    // Admin should review and remove objectionable content within 24 hours
    // In production, you might want to send an email/notification to admins here

    res.json({ success: true, message: 'Жалоба отправлена. Администрация рассмотрит её в течение 24 часов.' });
  } catch (e) {
    console.error(`[ERROR] Report message error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка отправки жалобы' });
  }
});

app.get('/api/users/:userId', authMiddleware, async (req, res) => {
  try {
    const user = await db.get('SELECT id, phoneNumber, email, displayName, photoUrl, status FROM users WHERE id = ?', [req.params.userId]);
    if (user) {
      res.json(user);
    } else {
      res.status(404).json({ success: false, error: 'User not found' });
    }
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// Создание чата
app.post('/api/chats/create', async (req, res) => {
  const { participants } = req.body;
  participants.sort();
  const chatId = participants.join('_');
  
  try {
    let chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat) {
      const timestamp = Date.now();
      await db.run(
        'INSERT INTO chats (id, participants, lastMessageTimestamp, lastMessage) VALUES (?, ?, ?, ?)',
        [chatId, JSON.stringify(participants), timestamp, 'Чат создан']
      );
      chat = { id: chatId, participants, lastMessage: 'Чат создан', lastMessageTimestamp: timestamp };
      
      console.log(`[DEBUG] New chat created: ${chatId}`);
      
      participants.forEach(userId => {
        io.to(String(userId)).emit('chat_created', chat);
      });
    } else {
      // Даже если чат существует, возвращаем его с распарсенными участниками
      chat.participants = JSON.parse(chat.participants);
    }
    res.json(chat);
  } catch (e) {
    console.error(`[ERROR] Create chat error: ${e.message}`);
    res.status(500).json({ success: false, error: e.message });
  }
});

app.post('/api/upload', upload.single('file'), (req, res) => {
  // Prefer API media endpoint for better compatibility on carrier networks.
  res.json({ url: `/api/media/${req.file.filename}` });
});

// Fallback upload endpoint: JSON + base64 payload.
// This helps on paths where multipart/form-data POSTs hang/timeout.
app.post('/api/upload-base64', authMiddleware, (req, res) => {
  try {
    const { filename, dataBase64 } = req.body || {};
    if (!dataBase64 || typeof dataBase64 !== 'string') {
      return res.status(400).json({ error: 'dataBase64 is required' });
    }

    // Allow both raw base64 and data URLs.
    const base64 = dataBase64.includes('base64,')
      ? dataBase64.split('base64,').pop()
      : dataBase64;

    const buf = Buffer.from(base64, 'base64');
    if (!buf || !buf.length) {
      return res.status(400).json({ error: 'invalid base64' });
    }

    const safeExt = filename ? path.extname(filename).slice(0, 10) : '';
    const outName = `${Date.now()}${safeExt}`;
    const outPath = path.join(uploadDir, outName);
    fs.writeFileSync(outPath, buf);
    return res.json({ url: `/api/media/${outName}` });
  } catch (e) {
    console.error('upload-base64 error', e);
    return res.status(500).json({ error: 'upload failed' });
  }
});

// Chunked base64 upload fallback: send small JSON requests to avoid carrier/edge issues with large POST bodies.
// Flow:
//   1) POST /api/upload-chunks/init { filename }
//   2) POST /api/upload-chunks/part { uploadId, index, dataBase64 }
//   3) POST /api/upload-chunks/complete { uploadId }
const activeUploads = new Map(); // uploadId -> { tmpPath, createdAt, filename }

app.post('/api/upload-chunks/init', authMiddleware, (req, res) => {
  try {
    const { filename } = req.body || {};
    const safeExt = filename ? path.extname(String(filename)).slice(0, 10) : '';
    const uploadId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const tmpName = `${uploadId}${safeExt}.part`;
    const tmpPath = path.join(uploadDir, tmpName);
    fs.writeFileSync(tmpPath, Buffer.alloc(0));
    activeUploads.set(uploadId, { tmpPath, createdAt: Date.now(), filename: filename || '' });
    return res.json({ uploadId });
  } catch (e) {
    console.error('upload-chunks init error', e);
    return res.status(500).json({ error: 'init failed' });
  }
});

app.post('/api/upload-chunks/part', authMiddleware, (req, res) => {
  try {
    const { uploadId, index, dataBase64 } = req.body || {};
    if (!uploadId || typeof uploadId !== 'string') {
      return res.status(400).json({ error: 'uploadId is required' });
    }
    if (dataBase64 == null || typeof dataBase64 !== 'string') {
      return res.status(400).json({ error: 'dataBase64 is required' });
    }
    const meta = activeUploads.get(uploadId);
    if (!meta) {
      return res.status(404).json({ error: 'unknown uploadId' });
    }
    const base64 = dataBase64.includes('base64,')
      ? dataBase64.split('base64,').pop()
      : dataBase64;
    const buf = Buffer.from(base64, 'base64');
    if (!buf || !buf.length) {
      return res.status(400).json({ error: 'invalid base64 chunk' });
    }
    // Append chunk. Index is accepted for diagnostics only.
    fs.appendFileSync(meta.tmpPath, buf);
    return res.json({ ok: true, index: index ?? null, bytesAppended: buf.length });
  } catch (e) {
    console.error('upload-chunks part error', e);
    return res.status(500).json({ error: 'part failed' });
  }
});

app.post('/api/upload-chunks/complete', authMiddleware, (req, res) => {
  try {
    const { uploadId } = req.body || {};
    if (!uploadId || typeof uploadId !== 'string') {
      return res.status(400).json({ error: 'uploadId is required' });
    }
    const meta = activeUploads.get(uploadId);
    if (!meta) {
      return res.status(404).json({ error: 'unknown uploadId' });
    }
    activeUploads.delete(uploadId);
    const safeExt = meta.filename ? path.extname(String(meta.filename)).slice(0, 10) : '';
    const outName = `${Date.now()}${safeExt}`;
    const outPath = path.join(uploadDir, outName);
    fs.renameSync(meta.tmpPath, outPath);
    return res.json({ url: `/api/media/${outName}` });
  } catch (e) {
    console.error('upload-chunks complete error', e);
    return res.status(500).json({ error: 'complete failed' });
  }
});

// Получение списка чатов пользователя
app.get('/api/chats', authMiddleware, async (req, res) => {
  try {
    const userId = String(req.userId);
    console.log(`[DEBUG] Fetching chats for user ID: ${userId}`);
    
    const chats = await db.all('SELECT * FROM chats ORDER BY lastMessageTimestamp DESC');
    
    const userChats = chats.filter(chat => {
      try {
        const participants = typeof chat.participants === 'string' 
          ? JSON.parse(chat.participants) 
          : chat.participants;
        return Array.isArray(participants) && participants.map(String).includes(userId);
      } catch (e) {
        return false;
      }
    }).map(chat => {
      return { ...chat, participants: JSON.parse(chat.participants) };
    });

    console.log(`[DEBUG] Found ${userChats.length} matches for user ${userId}`);
    res.json(userChats);
  } catch (e) {
    console.error(`[ERROR] Fetch chats error: ${e.message}`);
    res.status(500).json({ success: false, error: e.message });
  }
});

// Helper function to check if user is blocked
async function isUserBlocked(viewerId, otherUserId) {
  const block = await db.get(
    'SELECT * FROM blocked_users WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)',
    [viewerId, otherUserId, otherUserId, viewerId]
  );
  return !!block;
}

app.get('/api/chats/:chatId/messages', authMiddleware, async (req, res) => {
  try {
    const viewerId = req.user.id;
    const messages = await db.all(
      'SELECT * FROM messages WHERE chatId = ? ORDER BY timestamp DESC LIMIT 100',
      [req.params.chatId]
    );
    
    // Filter out messages from blocked users
    const filteredMessages = [];
    for (const message of messages) {
      const blocked = await isUserBlocked(viewerId, message.senderId);
      if (!blocked) {
        filteredMessages.push(message);
      }
    }
    
    res.json(filteredMessages);
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

const userSockets = new Map();

io.use((socket, next) => {
  // Пробуем получить токен из разных источников:
  // 1. socket.handshake.auth.token (для Android/Flutter с setAuth)
  // 2. socket.handshake.query.token (для iOS Swift с connectParams)
  // 3. Authorization header (для iOS Swift с extraHeaders)
  let token = socket.handshake.auth?.token;
  
  if (!token) {
    // Пробуем из query параметров (connectParams в Swift)
    token = socket.handshake.query?.token;
    if (typeof token === 'object' && token.length > 0) {
      token = token[0];
    }
  }
  
  if (!token) {
    // Пробуем из заголовка Authorization
    const authHeader = socket.handshake.headers?.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7);
    }
  }
  
  console.log(`[DEBUG] Socket Auth attempt - auth.token: ${socket.handshake.auth?.token}, query.token: ${socket.handshake.query?.token}, authHeader: ${socket.handshake.headers?.authorization}`);
  console.log(`[DEBUG] Socket Auth attempt with token: ${token ? token.substring(0, 20) + '...' : 'none'}`);
  
  if (token) {
    jwt.verify(token, JWT_SECRET, (err, decoded) => {
      if (err) {
        console.error(`[ERROR] Socket JWT verify error: ${err.message}`);
        return next(new Error('Auth error'));
      }
      socket.userId = decoded.id;
      console.log(`[DEBUG] Socket Auth success for user: ${socket.userId}`);
      next();
    });
  } else {
    console.error(`[ERROR] Socket Auth error: No token provided in auth, query, or headers`);
    next(new Error('Auth error'));
  }
});

io.on('connection', (socket) => {
  console.log(`[DEBUG] User connected: userId=${socket.userId}, socketId=${socket.id}`);
  userSockets.set(String(socket.userId), socket.id);
  socket.join(String(socket.userId));
  console.log(`[DEBUG] Updated userSockets map, total entries: ${userSockets.size}`);

  // Логируем все входящие события для отладки
  socket.onAny((eventName, ...args) => {
    if (eventName !== 'ping' && eventName !== 'pong') {
      console.log(`[DEBUG] 📨 Received event: ${eventName}, args:`, JSON.stringify(args));
    }
  });

  socket.on('join_chat', (chatId) => {
    socket.join(chatId);
  });

  socket.on('send_message', async (data) => {
    const { chatId, text, type, mediaUrl, replyToMessageId } = data;
    const timestamp = Date.now();
    const message = {
      id: timestamp.toString(),
      chatId,
      senderId: socket.userId,
      text,
      type,
      mediaUrl,
      timestamp,
      replyToMessageId: replyToMessageId || null
    };

    try {
      // Get chat participants to check for blocks
      const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
      if (chat) {
        const participants = JSON.parse(chat.participants);
        
        // Check if sender is blocked by any participant
        for (const participantId of participants) {
          if (participantId !== socket.userId) {
            const blocked = await isUserBlocked(participantId, socket.userId);
            if (blocked) {
              console.log(`[MODERATION] Message blocked: user ${socket.userId} is blocked by ${participantId}`);
              socket.emit('message_blocked', { reason: 'Вы заблокированы этим пользователем' });
              return;
            }
          }
        }
      }

      await db.run(
        'INSERT INTO messages (id, chatId, senderId, text, type, mediaUrl, timestamp, replyToMessageId) VALUES (?,?,?,?,?,?,?,?)',
        [message.id, message.chatId, message.senderId, message.text, message.type, message.mediaUrl, message.timestamp, message.replyToMessageId]
      );

      await db.run(
        'UPDATE chats SET lastMessage = ?, lastMessageTimestamp = ? WHERE id = ?',
        [text || type, timestamp, chatId]
      );

      console.log(`[DEBUG] Message saved and chat updated: ${chatId}`);
      
      // Only emit to participants who haven't blocked the sender
      const chatUpdated = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
      if (chatUpdated) {
        const participants = JSON.parse(chatUpdated.participants);
        for (const participantId of participants) {
          if (participantId !== socket.userId) {
            const blocked = await isUserBlocked(participantId, socket.userId);
            if (!blocked) {
              const targetSocketId = userSockets.get(String(participantId));
              if (targetSocketId) {
                io.to(targetSocketId).emit('new_message', message);
              }
            }
          }
        }
        // Also emit to sender
        socket.emit('new_message', message);
      } else {
        io.to(chatId).emit('new_message', message);
      }
    } catch (e) {
      console.error(`[ERROR] Send message error: ${e.message}`);
    }
  });

  socket.on('call_user', async (data) => {
    const { to, channelName, type } = data;
    console.log(`[DEBUG] call_user event: from=${socket.userId}, to=${to}, channelName=${channelName}, type=${type}`);
    const targetSocketId = userSockets.get(String(to));
    console.log(`[DEBUG] Target socketId for user ${to}: ${targetSocketId}`);
    console.log(`[DEBUG] Current userSockets keys: ${Array.from(userSockets.keys()).join(', ')}`);
    if (targetSocketId) {
      // Получаем информацию о чате для отправки participants
      try {
        const chat = await db.get('SELECT * FROM chats WHERE id = ?', [channelName]);
        let participants = [];
        if (chat) {
          participants = JSON.parse(chat.participants);
        }
        const callData = {
          from: socket.userId,
          channelName,
          type,
          participants: participants
        };
        console.log(`[DEBUG] Sending incoming_call with data:`, JSON.stringify(callData));
        io.to(targetSocketId).emit('incoming_call', callData);
        console.log(`[DEBUG] ✅ Sent incoming_call to user ${to} (socketId=${targetSocketId})`);
      } catch (e) {
        console.error(`[ERROR] Error getting chat info: ${e.message}`);
        // Fallback: отправляем без participants
        io.to(targetSocketId).emit('incoming_call', {
          from: socket.userId,
          channelName,
          type
        });
      }
    } else {
      console.log(`[DEBUG] ⚠️ User ${to} not connected, cannot send incoming_call`);
    }
  });

  socket.on('call_accepted', (data) => {
    const { chatId, from } = data;
    console.log(`[DEBUG] ========== CALL ACCEPTED EVENT ==========`);
    console.log(`[DEBUG] Call accepted: chatId=${chatId}, from=${from}, acceptor socketId=${socket.id}, acceptor userId=${socket.userId}`);
    console.log(`[DEBUG] Current userSockets map:`, Array.from(userSockets.entries()).map(([k, v]) => `${k}:${v}`).join(', '));
    
    // Уведомляем инициатора звонка о том, что звонок принят
    // Находим всех участников чата и отправляем событие
    db.get('SELECT * FROM chats WHERE id = ?', [chatId]).then(chat => {
      if (chat) {
        const participants = JSON.parse(chat.participants);
        console.log(`[DEBUG] Chat participants: ${participants.join(', ')}`);
        console.log(`[DEBUG] User who accepted (from): ${from}`);
        console.log(`[DEBUG] Acceptor userId (socket.userId): ${socket.userId}`);
        
        let sentCount = 0;
        const acceptorUserIdStr = String(socket.userId); // Тот, кто отправил событие call_accepted
        
        participants.forEach(userId => {
          const userIdStr = String(userId);
          const fromStr = String(from);
          console.log(`[DEBUG] Checking participant: ${userIdStr}, from: ${fromStr}, acceptor: ${acceptorUserIdStr}`);
          
          // Отправляем всем участникам, кроме того, кто отправил событие call_accepted
          // Это позволяет инициатору звонка получить уведомление о принятии
          if (userIdStr !== acceptorUserIdStr) {
            const targetSocketId = userSockets.get(userIdStr);
            console.log(`[DEBUG] Sending call_accepted to userId=${userIdStr}, socketId=${targetSocketId}`);
            if (targetSocketId) {
              const eventData = { chatId, from };
              console.log(`[DEBUG] Emitting call_accepted event:`, JSON.stringify(eventData));
              console.log(`[DEBUG] Sending to socketId=${targetSocketId} via io.to()`);
              
              // Отправляем событие напрямую на сокет
              const targetSocket = io.sockets.sockets.get(targetSocketId);
              if (targetSocket) {
                console.log(`[DEBUG] Found target socket, emitting call_accepted with data:`, JSON.stringify(eventData));
                targetSocket.emit('call_accepted', eventData);
                console.log(`[DEBUG] ✅ Sent call_accepted event directly to userId=${userIdStr} (socketId=${targetSocketId})`);
                // Также пробуем через io.to() для надежности
                io.to(targetSocketId).emit('call_accepted', eventData);
                console.log(`[DEBUG] ✅ Also sent call_accepted via io.to() to userId=${userIdStr} (socketId=${targetSocketId})`);
              } else {
                console.log(`[DEBUG] Target socket not found, using io.to() only`);
                // Fallback: используем io.to()
                io.to(targetSocketId).emit('call_accepted', eventData);
                console.log(`[DEBUG] ✅ Sent call_accepted event via io.to() to userId=${userIdStr} (socketId=${targetSocketId})`);
              }
              sentCount++;
            } else {
              console.log(`[DEBUG] ⚠️ User ${userIdStr} not connected (no socketId in userSockets map)`);
              console.log(`[DEBUG] Available socketIds: ${Array.from(userSockets.values()).join(', ')}`);
            }
          } else {
            console.log(`[DEBUG] Skipping ${userIdStr} (this is the user who sent call_accepted event)`);
          }
        });
        console.log(`[DEBUG] Total call_accepted events sent: ${sentCount}`);
        console.log(`[DEBUG] ==========================================`);
      } else {
        console.error(`[ERROR] Chat ${chatId} not found`);
      }
    }).catch(e => {
      console.error(`[ERROR] Error handling call_accepted: ${e.message}`);
      console.error(`[ERROR] Stack:`, e.stack);
    });
  });

  socket.on('group_call', (data) => {
    const { participants, channelName, type } = data;
    // Отправляем уведомление всем участникам группы
    participants.forEach(participantId => {
      const targetSocketId = userSockets.get(participantId);
      if (targetSocketId && participantId !== socket.userId) {
        io.to(targetSocketId).emit('incoming_group_call', {
          from: socket.userId,
          channelName,
          type,
          participants
        });
      }
    });
  });

  socket.on('disconnect', () => {
    console.log(`[DEBUG] User disconnected: userId=${socket.userId}, socketId=${socket.id}`);
    if (socket.userId) {
      userSockets.delete(String(socket.userId));
      console.log(`[DEBUG] Removed user from userSockets map, remaining entries: ${userSockets.size}`);
    }
    userSockets.delete(socket.userId);
  });
});

// Webhook endpoint для Telegram Gateway (для получения отчетов о доставке)
app.post('/api/sms/webhook', (req, res) => {
  console.log('[DEBUG] Telegram Gateway webhook received:', JSON.stringify(req.body, null, 2));
  // Telegram Gateway требует ответ 200 для подтверждения получения отчета
  res.status(200).json({ ok: true });
});

// Обработчик для несуществующих маршрутов (404)
app.use((req, res) => {
  res.status(404).json({ 
    success: false, 
    error: 'Маршрут не найден',
    path: req.path 
  });
});

// Общий обработчик ошибок
app.use((err, req, res, next) => {
  console.error(`[ERROR] Unhandled error:`, err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Внутренняя ошибка сервера',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
