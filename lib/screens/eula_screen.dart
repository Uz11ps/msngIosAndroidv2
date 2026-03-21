import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kCurrentTermsVersion = '20 марта 2026';

class EulaScreen extends StatefulWidget {
  final VoidCallback onAccept;
  final String termsVersion;
  final bool requireAcceptance;
  final bool canDismiss;

  const EulaScreen({
    super.key,
    required this.onAccept,
    required this.termsVersion,
    this.requireAcceptance = true,
    this.canDismiss = false,
  });

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  bool _hasScrolledToBottom = false;
  bool _accepted = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScrollPosition);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkScrollPosition);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScrollPosition() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (currentScroll >= maxScroll - 50 && !_hasScrolledToBottom) {
        setState(() {
          _hasScrolledToBottom = true;
        });
      }
    }
  }

  Future<void> _acceptEula() async {
    if (widget.requireAcceptance && !_accepted) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eula_accepted', true);
    await prefs.setString('eula_accepted_date', DateTime.now().toIso8601String());
    await prefs.setString('eula_accepted_version', widget.termsVersion);
    
    widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Условия использования'),
        automaticallyImplyLeading: widget.canDismiss,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Условия использования приложения Messenger App',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Последнее обновление:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(
                    widget.termsVersion,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '1. Принятие условий',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Используя приложение Messenger App, вы соглашаетесь с настоящими условиями использования. Если вы не согласны с этими условиями, пожалуйста, не используйте приложение.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '2. Недопустимый контент и поведение',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Мы не терпим неприемлемый контент или оскорбительное поведение пользователей. К неприемлемому контенту относится:',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Контент, содержащий ненависть, дискриминацию или оскорбления', style: TextStyle(fontSize: 16)),
                        Text('• Порнографический или сексуально откровенный контент', style: TextStyle(fontSize: 16)),
                        Text('• Контент, пропагандирующий насилие или незаконную деятельность', style: TextStyle(fontSize: 16)),
                        Text('• Спам, мошенничество или вводящая в заблуждение информация', style: TextStyle(fontSize: 16)),
                        Text('• Контент, нарушающий права интеллектуальной собственности', style: TextStyle(fontSize: 16)),
                        Text('• Личная информация других пользователей без их согласия', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '3. Модерация контента',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Мы применяем автоматическую фильтрацию для выявления неприемлемого контента. Пользователи могут сообщать о неприемлемом контент или поведении через функцию "Пожаловаться".',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '4. Блокировка пользователей',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вы можете заблокировать любого пользователя, который ведет себя неприемлемо. Заблокированные пользователи не смогут отправлять вам сообщения или видеть ваш профиль. При блокировке пользователя администрация автоматически уведомляется о неприемлемом поведении.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '5. Обработка жалоб',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Все жалобы на неприемлемый контент или поведение обрабатываются администрацией в течение 24 часов. Неприемлемый контент будет удален, а пользователи, нарушившие правила, будут заблокированы или удалены из приложения.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '6. Ваши права',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вы имеете право:',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Блокировать пользователей, которые ведут себя неприемлемо', style: TextStyle(fontSize: 16)),
                        Text('• Пожаловаться на неприемлемый контент или поведение', style: TextStyle(fontSize: 16)),
                        Text('• Удалять свои сообщения и контент', style: TextStyle(fontSize: 16)),
                        Text('• Удалить свой аккаунт в любое время', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '7. Ответственность',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вы несете полную ответственность за весь контент, который вы публикуете или отправляете через приложение. Мы не несем ответственности за действия других пользователей.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '8. Изменения условий',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Мы оставляем за собой право изменять настоящие условия использования в любое время. О существенных изменениях мы уведомим пользователей через приложение.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '9. Контакты',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'По вопросам, связанным с условиями использования или жалобами, обращайтесь:',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email: support@milviar.ru', style: TextStyle(fontSize: 16)),
                        Text('Через форму обратной связи в приложении', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              children: [
                if (widget.requireAcceptance)
                  CheckboxListTile(
                    title: const Text(
                      'Я прочитал и согласен с условиями использования',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    value: _accepted,
                    onChanged: (value) {
                      setState(() {
                        _accepted = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (widget.requireAcceptance) const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.requireAcceptance
                        ? ((_accepted && _hasScrolledToBottom) ? _acceptEula : null)
                        : () => Navigator.of(context).maybePop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      widget.requireAcceptance ? 'Принять и продолжить' : 'Закрыть',
                    ),
                  ),
                ),
                if (widget.requireAcceptance && !_hasScrolledToBottom)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Пожалуйста, прокрутите до конца, чтобы принять условия',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
