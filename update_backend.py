#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import io
import time

# Проверка зависимостей
try:
    import paramiko
    from scp import SCPClient
except ImportError as e:
    print("❌ ERROR: Необходимые библиотеки не установлены!")
    print("Установите их командой:")
    print("  pip install paramiko scp")
    sys.exit(1)

# Устанавливаем UTF-8 для вывода
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

def deploy():
    server = "83.166.246.225"
    port = 22
    user = "root"
    password = "kcokmkzgHQ5dJOBF"
    
    # Путь к локальной папке бекенда
    backend_dir = "./бекенд"
    
    # Проверяем наличие файлов
    index_js = os.path.join(backend_dir, "index.js")
    package_json = os.path.join(backend_dir, "package.json")
    
    if not os.path.exists(index_js):
        print(f"❌ ERROR: {index_js} not found")
        return False
    
    if not os.path.exists(package_json):
        print(f"❌ ERROR: {package_json} not found")
        return False
    
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    print(f"🔌 Подключение к {server}...")
    try:
        ssh.connect(server, port, user, password, timeout=30)
        print("✅ Подключено успешно")
    except Exception as e:
        print(f"❌ ERROR: Не удалось подключиться: {e}")
        return False
    
    try:
        # Создаем папку если её нет
        print("📁 Создание директории на сервере...")
        stdin, stdout, stderr = ssh.exec_command("mkdir -p /root/messenger/backend")
        stdout.channel.recv_exit_status()
        
        # Загружаем файлы
        print("📤 Загрузка файлов на сервер...")
        with SCPClient(ssh.get_transport()) as scp:
            scp.put(index_js, "/root/messenger/backend/index.js")
            scp.put(package_json, "/root/messenger/backend/package.json")
        print("✅ Файлы загружены успешно")
        
        # Установка зависимостей
        print("📦 Установка зависимостей...")
        install_cmd = "cd /root/messenger/backend && npm install --production"
        stdin, stdout, stderr = ssh.exec_command(install_cmd)
        
        # Выводим прогресс установки
        while not stdout.channel.exit_status_ready():
            if stdout.channel.recv_ready():
                output = stdout.channel.recv(1024).decode('utf-8', errors='ignore')
                if output.strip():
                    print(output.strip())
            time.sleep(0.1)
        
        exit_status = stdout.channel.recv_exit_status()
        if exit_status != 0:
            error_output = stderr.read().decode('utf-8', errors='ignore')
            print(f"⚠️  Предупреждение при установке зависимостей: {error_output}")
        else:
            print("✅ Зависимости установлены")
        
        # Проверяем, запущен ли процесс
        print("🔍 Проверка статуса PM2...")
        stdin, stdout, stderr = ssh.exec_command("pm2 list | grep messenger-backend || echo 'not_running'")
        pm2_status = stdout.read().decode('utf-8', errors='ignore').strip()
        
        # Перезапуск или запуск сервера
        if 'not_running' in pm2_status or 'stopped' in pm2_status.lower():
            print("🚀 Запуск сервера...")
            restart_cmd = "cd /root/messenger/backend && pm2 start index.js --name messenger-backend --update-env"
        else:
            print("🔄 Перезапуск сервера...")
            restart_cmd = "cd /root/messenger/backend && pm2 restart messenger-backend --update-env"
        
        stdin, stdout, stderr = ssh.exec_command(restart_cmd)
        exit_status = stdout.channel.recv_exit_status()
        
        if exit_status != 0:
            error_output = stderr.read().decode('utf-8', errors='ignore')
            print(f"❌ Ошибка при перезапуске: {error_output}")
            # Пробуем запустить заново
            print("🔄 Попытка запуска заново...")
            stdin, stdout, stderr = ssh.exec_command("cd /root/messenger/backend && pm2 delete messenger-backend 2>/dev/null; pm2 start index.js --name messenger-backend")
            exit_status = stdout.channel.recv_exit_status()
        
        # Сохраняем конфигурацию PM2
        print("💾 Сохранение конфигурации PM2...")
        ssh.exec_command("pm2 save")
        
        # Ждем немного для запуска
        print("⏳ Ожидание запуска сервера (3 секунды)...")
        time.sleep(3)
        
        # Проверяем статус
        print("📊 Статус PM2:")
        stdin, stdout, stderr = ssh.exec_command("pm2 status")
        status_output = stdout.read().decode('utf-8', errors='ignore')
        print(status_output)
        
        # Проверяем логи
        print("\n📋 Последние логи сервера:")
        stdin, stdout, stderr = ssh.exec_command("pm2 logs messenger-backend --lines 15 --nostream")
        logs_output = stdout.read().decode('utf-8', errors='ignore')
        if logs_output.strip():
            print(logs_output)
        else:
            print("(Логи пусты или сервер только что запустился)")
        
        # Проверяем доступность эндпоинта
        print("\n🔍 Проверка доступности API...")
        stdin, stdout, stderr = ssh.exec_command(
            "curl -s -X POST http://localhost:3000/api/auth/email-register "
            "-H 'Content-Type: application/json' "
            "-d '{}' | head -c 200"
        )
        api_response = stdout.read().decode('utf-8', errors='ignore').strip()
        
        if api_response and ('Email и пароль обязательны' in api_response or 'success' in api_response.lower()):
            print("✅ API доступен и отвечает корректно!")
            print(f"   Ответ: {api_response[:100]}...")
        else:
            print("⚠️  API может быть недоступен или отвечает неверно")
            print(f"   Ответ: {api_response}")
        
        print("\n✅ Деплой завершен успешно!")
        print(f"🌐 Сервер доступен по адресу: http://{server}:3000")
        return True
        
    except Exception as e:
        print(f"❌ Ошибка при деплое: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        ssh.close()

if __name__ == "__main__":
    success = deploy()
    sys.exit(0 if success else 1)
