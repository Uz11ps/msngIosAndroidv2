import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _isChecking = false;
  final List<DiagnosticResult> _results = [];

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isChecking = true;
      _results.clear();
    });

    // Проверка 1: Доступность базового URL
    await _checkServerAvailability();

    // Проверка 2: Проверка эндпоинта регистрации
    await _checkRegistrationEndpoint();

    // Проверка 3: Проверка эндпоинта входа
    await _checkLoginEndpoint();

    setState(() {
      _isChecking = false;
    });
  }

  Future<void> _checkServerAvailability() async {
    final result = DiagnosticResult(
      name: 'Доступность сервера',
      status: DiagnosticStatus.checking,
    );
    setState(() {
      _results.add(result);
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/email-register');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 400 || response.statusCode == 200) {
        result.status = DiagnosticStatus.success;
        result.message = 'Сервер доступен (код: ${response.statusCode})';
      } else {
        result.status = DiagnosticStatus.warning;
        result.message = 'Сервер отвечает, но с неожиданным кодом: ${response.statusCode}';
      }
    } catch (e) {
      result.status = DiagnosticStatus.error;
      result.message = 'Ошибка: $e';
    }

    setState(() {});
  }

  Future<void> _checkRegistrationEndpoint() async {
    final result = DiagnosticResult(
      name: 'Эндпоинт регистрации',
      status: DiagnosticStatus.checking,
    );
    setState(() {
      _results.add(result);
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailRegister}');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));

      final contentType = response.headers['content-type'] ?? '';
      final body = response.body.trim();

      if (contentType.contains('application/json') && body.startsWith('{')) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data.containsKey('success') || data.containsKey('message')) {
          result.status = DiagnosticStatus.success;
          result.message = 'Эндпоинт работает корректно';
        } else {
          result.status = DiagnosticStatus.warning;
          result.message = 'Эндпоинт отвечает, но формат неожиданный';
        }
      } else {
        result.status = DiagnosticStatus.error;
        result.message = 'Сервер вернул не JSON (Content-Type: $contentType)';
      }
    } catch (e) {
      result.status = DiagnosticStatus.error;
      result.message = 'Ошибка: $e';
    }

    setState(() {});
  }

  Future<void> _checkLoginEndpoint() async {
    final result = DiagnosticResult(
      name: 'Эндпоинт входа',
      status: DiagnosticStatus.checking,
    );
    setState(() {
      _results.add(result);
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailLogin}');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));

      final contentType = response.headers['content-type'] ?? '';
      final body = response.body.trim();

      if (contentType.contains('application/json') && body.startsWith('{')) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data.containsKey('success') || data.containsKey('message')) {
          result.status = DiagnosticStatus.success;
          result.message = 'Эндпоинт работает корректно';
        } else {
          result.status = DiagnosticStatus.warning;
          result.message = 'Эндпоинт отвечает, но формат неожиданный';
        }
      } else {
        result.status = DiagnosticStatus.error;
        result.message = 'Сервер вернул не JSON (Content-Type: $contentType)';
      }
    } catch (e) {
      result.status = DiagnosticStatus.error;
      result.message = 'Ошибка: $e';
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика подключения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking ? null : _runDiagnostics,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Информация о сервере',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('URL: ${ApiConfig.baseUrl}'),
                  const SizedBox(height: 4),
                  Text('Регистрация: ${ApiConfig.emailRegister}'),
                  const SizedBox(height: 4),
                  Text('Вход: ${ApiConfig.emailLogin}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isChecking)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else
            ..._results.map((result) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _getStatusIcon(result.status),
                    title: Text(result.name),
                    subtitle: result.message != null
                        ? Text(
                            result.message!,
                            style: TextStyle(
                              color: _getStatusColor(result.status),
                            ),
                          )
                        : null,
                  ),
                )),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Что делать, если есть ошибки:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('1. Проверьте интернет-соединение'),
                  const Text('2. Убедитесь, что сервер запущен'),
                  const Text('3. Проверьте, что URL сервера правильный'),
                  const Text('4. Если ошибка "не JSON", возможно проблема с сервером'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getStatusIcon(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.checking:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DiagnosticStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DiagnosticStatus.warning:
        return const Icon(Icons.warning, color: Colors.orange);
      case DiagnosticStatus.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  Color _getStatusColor(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.checking:
        return Colors.grey;
      case DiagnosticStatus.success:
        return Colors.green;
      case DiagnosticStatus.warning:
        return Colors.orange;
      case DiagnosticStatus.error:
        return Colors.red;
    }
  }
}

enum DiagnosticStatus {
  checking,
  success,
  warning,
  error,
}

class DiagnosticResult {
  final String name;
  DiagnosticStatus status;
  String? message;

  DiagnosticResult({
    required this.name,
    required this.status,
    this.message,
  });
}
