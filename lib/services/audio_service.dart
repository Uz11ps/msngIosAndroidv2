import 'dart:io' if (dart.library.html) 'dart:html';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AudioService {
  final AudioRecorder? _recorder = kIsWeb ? null : AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _token;
  String? _currentRecordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  Future<String?> startRecording() async {
    if (kIsWeb) {
      print('⚠️ Audio recording is not supported on web platform');
      return null;
    }
    
    if (_recorder == null) {
      print('⚠️ AudioRecorder is not available');
      return null;
    }
    
    try {
      // Проверяем доступность плагина
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        print('❌ No recording permission');
        return null;
      }
      
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/audio_$timestamp.m4a';
      
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );
      
      _isRecording = true;
      print('🎤 Started recording: $_currentRecordingPath');
      return _currentRecordingPath;
    } catch (e) {
      print('💥 Error starting recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      
      // Проверяем, является ли это ошибкой MissingPluginException
      if (e.toString().contains('MissingPluginException')) {
        throw Exception('PLUGIN_NOT_AVAILABLE');
      }
      
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (kIsWeb || _recorder == null) {
      return null;
    }
    
    try {
      if (_isRecording && _currentRecordingPath != null) {
        final path = await _recorder!.stop();
        _isRecording = false;
        print('🛑 Stopped recording: $path');
        return path;
      }
      return null;
    } catch (e) {
      print('💥 Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (kIsWeb || _recorder == null) {
      return;
    }
    
    try {
      if (_isRecording) {
        await _recorder!.stop();
        _isRecording = false;
        if (_currentRecordingPath != null && !kIsWeb) {
          try {
            final file = File(_currentRecordingPath!);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            print('⚠️ Error deleting file: $e');
          }
        }
        _currentRecordingPath = null;
        print('❌ Recording cancelled');
      }
    } catch (e) {
      print('💥 Error cancelling recording: $e');
    }
  }

  void setToken(String? token) {
    _token = token;
  }

  Future<String?> uploadAudio(String filePath) async {
    try {
      if (_token == null) {
        print('❌ No token for upload');
        return null;
      }
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFile}'),
      );
      request.headers.addAll(ApiConfig.getHeaders(_token));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['url'] as String?;
        print('📤 Audio uploaded: $url');
        
        // Удаляем временный файл после загрузки
        if (!kIsWeb) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            print('⚠️ Error deleting file: $e');
          }
        }
        
        return url;
      }
      return null;
    } catch (e) {
      print('💥 Error uploading audio: $e');
      return null;
    }
  }

  Future<void> playAudio(String url) async {
    try {
      if (_isPlaying) {
        await _player.stop();
      }
      _isPlaying = true;
      await _player.play(UrlSource(url));
      
      _player.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.completed) {
          _isPlaying = false;
        }
      });
      
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
      });
    } catch (e) {
      print('💥 Error playing audio: $e');
      _isPlaying = false;
      // Игнорируем ошибки MissingPluginException при hot restart
      if (e.toString().contains('MissingPluginException')) {
        print('⚠️ Audio player plugin not available (may need full rebuild)');
      }
    }
  }

  Future<void> stopPlaying() async {
    try {
      await _player.stop();
      _isPlaying = false;
    } catch (e) {
      print('💥 Error stopping playback: $e');
    }
  }

  void dispose() {
    if (!kIsWeb && _recorder != null) {
      try {
        _recorder!.dispose();
      } catch (e) {
        // Игнорируем ошибки при dispose (может быть MissingPluginException)
      }
    }
    try {
      _player.dispose();
    } catch (e) {
      // Игнорируем ошибки при dispose (может быть MissingPluginException)
    }
  }
}
