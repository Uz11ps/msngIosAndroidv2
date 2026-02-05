import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/agora_config.dart';

class AgoraService {
  RtcEngine? _engine;
  bool _isCallActive = false;
  String? _currentChannelName;
  String? _callType; // 'audio' or 'video'
  int? _localUid;
  int? _remoteUid;
  RtcConnection? _connection;
  
  // Callbacks
  Function(int uid, int elapsed)? onUserJoined;
  Function(int uid, UserOfflineReasonType reason)? onUserOffline;
  Function(RtcConnection connection, int remoteUid, int elapsed)? onRemoteVideoStateChanged;
  Function(RtcConnection connection, int remoteUid, int elapsed)? onRemoteAudioStateChanged;

  bool get isCallActive => _isCallActive;
  String? get callType => _callType;
  int? get localUid => _localUid;
  int? get remoteUid => _remoteUid;
  RtcEngine? get engine => _engine;
  RtcConnection? get connection => _connection;

  bool _isInitialized = false;
  
  Future<void> initialize() async {
    // Agora не поддерживается на веб-платформе
    if (kIsWeb) {
      print('⚠️ Agora RTC Engine is not supported on web platform');
      throw Exception('Agora RTC Engine is not supported on web. Please use mobile app for calls.');
    }
    
    if (_isInitialized && _engine != null) {
      print('✅ Agora already initialized');
      return;
    }
    
    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: AgoraConfig.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      
      _isInitialized = true;
      print('✅ Agora engine initialized successfully');

      // Включаем аудио
      await _engine!.enableAudio();
      
      // Регистрируем обработчики событий
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            print('✅ Joined channel: ${connection.channelId}, uid: ${connection.localUid}');
            _localUid = connection.localUid;
            _connection = connection;
            _isCallActive = true;
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            print('📞 Left channel: ${connection.channelId}');
            _isCallActive = false;
            _localUid = null;
            _remoteUid = null;
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            print('👤 User joined: $remoteUid');
            _remoteUid = remoteUid;
            onUserJoined?.call(remoteUid, elapsed);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            print('👤 User offline: $remoteUid, reason: $reason');
            _remoteUid = null;
            onUserOffline?.call(remoteUid, reason);
          },
          onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
            if (state == RemoteVideoState.remoteVideoStateStarting || 
                state == RemoteVideoState.remoteVideoStateDecoding) {
              onRemoteVideoStateChanged?.call(connection, remoteUid, elapsed);
            }
          },
          onRemoteAudioStateChanged: (RtcConnection connection, int remoteUid, RemoteAudioState state, RemoteAudioStateReason reason, int elapsed) {
            if (state == RemoteAudioState.remoteAudioStateStarting || 
                state == RemoteAudioState.remoteAudioStateDecoding) {
              onRemoteAudioStateChanged?.call(connection, remoteUid, elapsed);
            }
          },
          onError: (ErrorCodeType err, String msg) {
            print('💥 Agora error: $err - $msg');
          },
        ),
      );

    } catch (e) {
      print('💥 Error initializing Agora: $e');
      _engine = null;
      _isInitialized = false;
      // При hot restart нативные библиотеки могут быть недоступны
      final errorStr = e.toString();
      if (errorStr.contains('Failed to load dynamic library') || 
          errorStr.contains('.dll') ||
          errorStr.contains('.so') ||
          errorStr.contains('The specified module could not be found')) {
        print('⚠️ Agora native libraries not available. Full app restart required.');
        throw Exception('Agora requires full app restart. Please stop and restart the app.');
      }
      rethrow;
    }
  }

  Future<void> startCall(String channelName, bool isVideo, int uid) async {
    if (kIsWeb) {
      throw Exception('Agora RTC Engine is not supported on web. Please use mobile app for calls.');
    }
    
    try {
      _currentChannelName = channelName;
      _callType = isVideo ? 'video' : 'audio';
      
      // Инициализируем только при необходимости
      if (!_isInitialized || _engine == null) {
        await initialize();
        if (_engine == null) {
          throw Exception('Agora engine not initialized. Please restart the app (full rebuild required).');
        }
      }

      // Включаем видео если нужно
      if (isVideo) {
        print('📹 Enabling video...');
        try {
          await _engine!.enableVideo();
          print('✅ Video enabled');
          await _engine!.startPreview();
          print('✅ Preview started');
        } catch (e) {
          print('💥 Error enabling video: $e');
          // Пробуем продолжить без видео
          await _engine!.disableVideo();
          throw Exception('Не удалось включить камеру. Проверьте разрешения и попробуйте снова.');
        }
      } else {
        await _engine!.disableVideo();
      }

      // Присоединяемся к каналу
      final token = AgoraConfig.getToken(channelName, uid);
      await _engine!.joinChannel(
        token: token ?? '',
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      print('📞 Starting call: $channelName, type: $_callType, uid: $uid');
    } catch (e) {
      print('💥 Error starting call: $e');
      await endCall();
      rethrow;
    }
  }

  Future<void> joinCall(String channelName, bool isVideo, int uid) async {
    if (kIsWeb) {
      throw Exception('Agora RTC Engine is not supported on web. Please use mobile app for calls.');
    }
    await startCall(channelName, isVideo, uid);
  }

  Future<void> endCall() async {
    try {
      if (_engine != null && _isCallActive) {
        await _engine!.leaveChannel();
        await _engine!.stopPreview();
      }
      
      _isCallActive = false;
      _currentChannelName = null;
      _callType = null;
      _localUid = null;
      _remoteUid = null;

      print('📞 Call ended');
    } catch (e) {
      print('💥 Error ending call: $e');
    }
  }

  Future<void> toggleMute(bool mute) async {
    try {
      if (_engine != null) {
        await _engine!.muteLocalAudioStream(mute);
        print('🎤 Audio ${mute ? "muted" : "unmuted"}');
      }
    } catch (e) {
      print('💥 Error toggling mute: $e');
    }
  }

  Future<void> toggleVideo(bool enable) async {
    try {
      if (_engine != null) {
        await _engine!.muteLocalVideoStream(!enable);
        await _engine!.enableLocalVideo(enable);
        print('📹 Video ${enable ? "enabled" : "disabled"}');
      }
    } catch (e) {
      print('💥 Error toggling video: $e');
    }
  }

  Future<void> switchCamera() async {
    try {
      if (_engine != null) {
        await _engine!.switchCamera();
        print('📷 Camera switched');
      }
    } catch (e) {
      print('💥 Error switching camera: $e');
    }
  }

  Future<void> dispose() async {
    await endCall();
    try {
      await _engine?.release();
    } catch (e) {
      print('⚠️ Error releasing Agora engine: $e');
    }
    _engine = null;
    _isInitialized = false;
  }
}
