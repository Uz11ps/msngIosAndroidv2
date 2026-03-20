import 'dart:io' if (dart.library.html) 'dart:html';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, consolidateHttpClientResponseBytes;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import 'package:http/http.dart' as http;
import 'multipart_uploader.dart';
import 'json_uploader.dart';
import 'media_fetcher.dart';

class _PlainHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 20);
    return client;
  }
}

class AudioService {
  static const String _directUploadBaseUrl = ApiConfig.fallbackIpHttpBaseUrl;
  final AudioRecorder? _recorder = kIsWeb ? null : AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<void>? _playerCompleteSub;
  bool _playerListenersReady = false;
  String? _token;
  String? _currentRecordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  AudioService() {
    _ensurePlayerListeners();
    // Best-effort; don't block construction.
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  void _ensurePlayerListeners() {
    if (_playerListenersReady) return;
    _playerListenersReady = true;

    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      try {
        if (kDebugMode) {
          print('🎵 Player state changed: $state');
        }
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          _isPlaying = false;
        }
      } catch (_) {}
    });

    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      try {
        if (kDebugMode) {
          print('✅ Playback completed (onPlayerComplete)');
        }
        _isPlaying = false;
      } catch (_) {}
    });
  }

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

  HttpClient _newUploadHttpClient() {
    final hc = HttpClient();
    hc.findProxy = (_) => 'DIRECT';
    hc.maxConnectionsPerHost = 1;
    hc.connectionTimeout = const Duration(seconds: 20);
    hc.idleTimeout = const Duration(seconds: 20);
    return hc;
  }

  Future<String?> uploadAudio(String filePath) async {
    try {
      if (_token == null) {
        print('❌ Audio upload: no token');
        return null;
      }

      print('🎧 Uploading audio file: $filePath');

      // On some iOS paths multipart uploads hang at request close; base64 JSON is more reliable.
      if (!kIsWeb) {
        try {
          if (Platform.isIOS) {
            final url = await _uploadAudioBase64(filePath);
            if (url != null) return url;
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Audio upload(base64) preflight failed, will try multipart: $e');
          }
        }
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFile}');
      final headers = ApiConfig.getMultipartHeaders(_token);

      Future<MultipartUploadResponse?> sendWithClient(String label, HttpClient client) async {
        try {
          final res = await MultipartUploader.uploadFile(
            httpClient: client,
            uri: uri,
            filePath: filePath,
            headers: headers,
            timeout: const Duration(seconds: 25),
          );
          return res;
        } on TimeoutException catch (e) {
          print('⏱️ Audio upload timeout ($label): $e');
          return null;
        } catch (e) {
          print('💥 Audio upload exception ($label): $e');
          return null;
        } finally {
          try {
            client.close(force: true);
          } catch (_) {}
        }
      }

      // Attempt 1: normal (with global overrides)
      final resp1 = await sendWithClient('overrides', _newUploadHttpClient());
      MultipartUploadResponse? resp = resp1;

      // Attempt 2: bypass overrides (system DNS)
      resp ??= await HttpOverrides.runZoned(() async {
        return await sendWithClient('system_dns', _newUploadHttpClient());
      }, createHttpClient: _PlainHttpOverrides().createHttpClient);

      if (resp == null) {
        // Attempt 3: JSON base64 fallback.
        return await _uploadAudioBase64(filePath);
      }
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
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
      final prefix = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
      print('❌ Audio upload failed: ${resp.statusCode} body="$prefix"');
      // Attempt 3: JSON base64 fallback.
      return await _uploadAudioBase64(filePath);
    } catch (e) {
      print('💥 Error uploading audio: $e');
      return null;
    }
  }

  Future<String?> _uploadAudioBase64(String filePath) async {
    try {
      if (_token == null || _token!.isEmpty) {
        print('❌ Audio upload(base64): missing token');
        return null;
      }
      final file = File(filePath);
      final fileLen = await file.length();
      if (fileLen > 8 * 1024 * 1024) {
        print('❌ Audio upload(base64): file too large ($fileLen bytes)');
        return null;
      }
      final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'audio.m4a';
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFileBase64}');
      print('📤 Audio upload(base64): POST $uri bytes=$fileLen');

      final headers = ApiConfig.getHeaders(_token);
      
      // iOS/carrier paths often hang on "large" single-shot POST. Prefer chunked JSON immediately to avoid waiting for timeouts.
      if (!kIsWeb && Platform.isIOS && fileLen > 32 * 1024) {
        try {
          print('📤 Audio upload(base64 chunks): start fileLen=$fileLen chunkBytes=8192');
          final chunkUrl = await JsonUploader.uploadFileBase64Chunked(
            baseUri: Uri.parse(ApiConfig.baseUrl),
            token: _token!,
            filePath: filePath,
            chunkBytes: 8192,
            timeoutPerReq: const Duration(seconds: 20),
          );
          if (chunkUrl != null) {
            print('📤 Audio uploaded (base64 chunks): $chunkUrl');
            return chunkUrl;
          }
        } catch (e) {
          print('💥 Audio upload(base64 chunks) exception: $e');
        }
      }

      final bytes = await file.readAsBytes();
      final payload = <String, dynamic>{
        'filename': filename,
        'dataBase64': base64Encode(bytes),
      };

      // Try a few pinned Cloudflare edges first (some anycast routes hang on POST responses).
      final pinnedIps = <InternetAddress>[
        InternetAddress('172.67.154.188'),
        InternetAddress('104.21.5.195'),
      ];
      for (final ip in pinnedIps) {
        final hc = JsonUploader.pinnedTlsClient(host: uri.host, ip: ip);
        try {
          print('📤 Audio upload(base64): trying pinned edge ${ip.address}');
          final res = await JsonUploader.postJson(
            httpClient: hc,
            uri: uri,
            headers: headers,
            bodyJson: payload,
            timeout: const Duration(seconds: 12),
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final url = data['url'] as String?;
            print('📤 Audio uploaded (base64): $url');
            return url;
          }
          final prefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
          print('❌ Audio upload(base64) failed pinned ${ip.address}: ${res.statusCode} body="$prefix"');
        } catch (e) {
          print('💥 Audio upload(base64) exception pinned ${ip.address}: $e');
        } finally {
          try {
            hc.close(force: true);
          } catch (_) {}
        }
      }

      // Last resort: default client (still uses global HttpOverrides).
      try {
        final res = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final url = data['url'] as String?;
          print('📤 Audio uploaded (base64): $url');
          return url;
        }
        final prefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
        print('❌ Audio upload(base64) failed: ${res.statusCode} body="$prefix"');
      } catch (e) {
        print('💥 Audio upload(base64) exception: $e');
      }
      // Attempt: chunked base64 upload (many small JSON requests).
      try {
        print('📤 Audio upload(base64 chunks): start fileLen=$fileLen chunkBytes=8192');
        final chunkUrl = await JsonUploader.uploadFileBase64Chunked(
          baseUri: Uri.parse(ApiConfig.baseUrl),
          token: _token!,
          filePath: filePath,
          chunkBytes: 8192,
          timeoutPerReq: const Duration(seconds: 20),
        );
        if (chunkUrl != null) {
          print('📤 Audio uploaded (base64 chunks): $chunkUrl');
          return chunkUrl;
        }
      } catch (e) {
        print('💥 Audio upload(base64 chunks) exception: $e');
      }

      // Final fallback for iOS: bypass Cloudflare path entirely and hit backend origin over HTTP.
      // ATS exception for 83.166.246.225 is already present in Info.plist.
      if (!kIsWeb && Platform.isIOS) {
        try {
          print('📤 Audio upload(direct chunks): start fileLen=$fileLen base=$_directUploadBaseUrl');
          final directChunkUrl = await JsonUploader.uploadFileBase64Chunked(
            baseUri: Uri.parse(_directUploadBaseUrl),
            token: _token!,
            filePath: filePath,
            chunkBytes: 8192,
            timeoutPerReq: const Duration(seconds: 20),
          );
          if (directChunkUrl != null) {
            print('📤 Audio uploaded (direct chunks): $directChunkUrl');
            return directChunkUrl;
          }
        } catch (e) {
          print('💥 Audio upload(direct chunks) exception: $e');
        }

        try {
          final directUri = Uri.parse('$_directUploadBaseUrl${ApiConfig.uploadFileBase64}');
          print('📤 Audio upload(direct base64): POST $directUri bytes=$fileLen');
          final res = await http
              .post(
                directUri,
                headers: headers,
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 20));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final url = data['url'] as String?;
            print('📤 Audio uploaded (direct base64): $url');
            return url;
          }
          final prefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
          print('❌ Audio upload(direct base64) failed: ${res.statusCode} body="$prefix"');
        } catch (e) {
          print('💥 Audio upload(direct base64) exception: $e');
        }
      }
      return null;
    } catch (e) {
      print('💥 Audio upload(base64) exception: $e');
      return null;
    }
  }

  Future<void> playAudio(String url) async {
    try {
      _ensurePlayerListeners();
      print('🔊 Attempting to play audio from URL: $url');
      
      if (_isPlaying) {
        print('⏹️ Stopping current playback');
        await _player.stop();
      }
      
      _isPlaying = true;
      print('▶️ Starting playback...');

      // iOS AVPlayer uses system DNS/network (doesn't respect our DoH HttpOverrides),
      // and can fail/hang on some carrier/Cloudflare routes. Workaround: download
      // via Dart HttpClient (with overrides) and play from a local temp file.
      if (!kIsWeb && Platform.isIOS && (url.startsWith('http://') || url.startsWith('https://'))) {
        final localPath = await _downloadToTempFile(url);
        if (localPath != null) {
          await _player.play(DeviceFileSource(localPath));
          print('✅ Playback started successfully (local file)');
          return;
        }
      }

      await _player.play(UrlSource(url));
      print('✅ Playback started successfully');
    } catch (e, stackTrace) {
      print('💥 Error playing audio: $e');
      print('💥 Stack trace: $stackTrace');
      _isPlaying = false;
      // Игнорируем ошибки MissingPluginException при hot restart
      if (e.toString().contains('MissingPluginException')) {
        print('⚠️ Audio player plugin not available (may need full rebuild)');
      }
    }
  }

  Future<String?> _downloadToTempFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final tmpDir = await getTemporaryDirectory();
      final ext = uri.pathSegments.isNotEmpty && uri.pathSegments.last.contains('.')
          ? '.${uri.pathSegments.last.split('.').last}'
          : '.m4a';
      final safeName = uri.path.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final outPath = '${tmpDir.path}/aud_${safeName.hashCode}$ext';
      final outFile = File(outPath);
      if (await outFile.exists()) {
        final len = await outFile.length();
        if (len > 0) return outPath;
      }

      final bytes = await MediaFetcher.fetchBytes(url, timeout: const Duration(seconds: 25));
      if (bytes == null || bytes.isEmpty) return null;
      await outFile.writeAsBytes(bytes, flush: true);
      return outPath;
    } catch (e) {
      if (kDebugMode) {
        print('🔊 Download audio failed: $e');
      }
      return null;
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
      _playerStateSub?.cancel();
      _playerCompleteSub?.cancel();
      _player.dispose();
    } catch (e) {
      // Игнорируем ошибки при dispose (может быть MissingPluginException)
    }
  }
}
