import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/socket_service.dart';
import '../config/api_config.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  SocketService? _socketService;
  bool _isCallActive = false;
  String? _currentCallId;
  String? _callType; // 'audio' or 'video'
  RTCSessionDescription? _pendingOffer;
  String? _callerUserId;

  bool get isCallActive => _isCallActive;
  String? get callType => _callType;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  RTCVideoRenderer? get localRenderer => _localRenderer;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;

  void setSocketService(SocketService socketService) {
    _socketService = socketService;
  }

  Future<void> initialize() async {
    try {
      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      await _remoteRenderer!.initialize();
    } catch (e) {
      print('⚠️ WebRTC initialization failed: $e');
      // Очищаем renderers при ошибке
      _localRenderer = null;
      _remoteRenderer = null;
      rethrow;
    }
  }

  Future<void> startCall(String toUserId, String channelName, bool isVideo) async {
    try {
      _callType = isVideo ? 'video' : 'audio';
      _currentCallId = channelName;
      
      // Создаем peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      // Получаем локальный поток (видео/аудио)
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo,
      });

      if (_localRenderer != null && _localStream != null) {
        _localRenderer!.srcObject = _localStream;
      }

      // Добавляем треки в peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Обработка ICE кандидатов
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _socketService?.socket?.emit('ice-candidate', {
          'to': toUserId,
          'candidate': candidate.toMap(),
          'channelName': channelName,
        });
      };

      // Обработка удаленного потока
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          if (_remoteRenderer != null) {
            _remoteRenderer!.srcObject = _remoteStream;
          }
        }
      };

      // Создаем offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Отправляем событие звонка через Socket (бекенд ожидает call_user)
      _socketService?.callUser(
        to: toUserId,
        channelName: channelName,
        type: _callType!,
      );

      // Отправляем offer через socket (будет обработан после принятия звонка)
      // Сохраняем offer для отправки после call_accepted
      _pendingOffer = offer;

      _isCallActive = true;
      print('📞 Call started: $channelName, type: $_callType');
    } catch (e) {
      print('💥 Error starting call: $e');
      await endCall();
    }
  }

  Future<void> acceptCall(Map<String, dynamic> callData) async {
    try {
      final channelName = callData['channelName'] as String;
      final callType = callData['type'] as String;
      _callerUserId = callData['from'] as String;
      
      _callType = callType;
      _currentCallId = channelName;
      _isCallActive = true;

      // Создаем peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      // Получаем локальный поток
      final isVideo = callType == 'video';
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo,
      });

      if (_localRenderer != null && _localStream != null) {
        _localRenderer!.srcObject = _localStream;
      }

      // Добавляем треки
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Обработка ICE кандидатов
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _socketService?.socket?.emit('ice-candidate', {
          'to': _callerUserId,
          'candidate': candidate.toMap(),
          'channelName': channelName,
        });
      };

      // Обработка удаленного потока
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          if (_remoteRenderer != null) {
            _remoteRenderer!.srcObject = _remoteStream;
          }
        }
      };

      // Ждем offer от инициатора (будет получен через onCallOffer)
      print('✅ Call accepted, waiting for offer: $channelName');
    } catch (e) {
      print('💥 Error accepting call: $e');
      await endCall();
    }
  }

  Future<void> handleOffer(Map<String, dynamic> offerData) async {
    try {
      if (_peerConnection == null) return;
      
      final offer = RTCSessionDescription(
        offerData['offer']['sdp'] as String,
        offerData['offer']['type'] as String,
      );
      
      await _peerConnection!.setRemoteDescription(offer);
      
      // Создаем answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      
      // Отправляем answer обратно инициатору
      _socketService?.socket?.emit('call-answer', {
        'to': offerData['from'] as String? ?? _callerUserId,
        'answer': answer.toMap(),
        'channelName': offerData['channelName'] as String,
      });
      
      print('✅ Offer received and answer sent');
    } catch (e) {
      print('💥 Error handling offer: $e');
    }
  }

  Future<void> handleIceCandidate(Map<String, dynamic> candidateData) async {
    try {
      if (_peerConnection == null) return;
      
      final candidateMap = candidateData['candidate'] as Map<String, dynamic>;
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
      print('✅ ICE candidate added');
    } catch (e) {
      print('💥 Error handling ICE candidate: $e');
    }
  }

  Future<void> handleAnswer(Map<String, dynamic> answerData) async {
    try {
      if (_peerConnection == null) return;
      
      final answer = RTCSessionDescription(
        answerData['answer']['sdp'] as String,
        answerData['answer']['type'] as String,
      );
      await _peerConnection!.setRemoteDescription(answer);
      print('✅ Answer received and set');
    } catch (e) {
      print('💥 Error handling answer: $e');
    }
  }

  Future<void> sendPendingOffer(String toUserId) async {
    if (_pendingOffer != null && _socketService != null) {
      _socketService!.socket?.emit('call-offer', {
        'to': toUserId,
        'offer': _pendingOffer!.toMap(),
        'channelName': _currentCallId,
        'type': _callType,
      });
      _pendingOffer = null;
      print('📤 Sent pending offer to $toUserId');
    }
  }

  Future<void> endCall() async {
    try {
      _isCallActive = false;
      _currentCallId = null;
      _callType = null;
      _callerUserId = null;
      _pendingOffer = null;

      // Останавливаем все треки
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _remoteStream?.getTracks().forEach((track) {
        track.stop();
      });

      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _peerConnection?.close();
      
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;

      if (_localRenderer != null) {
        try {
          _localRenderer!.srcObject = null;
        } catch (e) {
          // Игнорируем ошибки при очистке renderer
        }
      }
      if (_remoteRenderer != null) {
        try {
          _remoteRenderer!.srcObject = null;
        } catch (e) {
          // Игнорируем ошибки при очистке renderer
        }
      }

      print('📞 Call ended');
    } catch (e) {
      print('💥 Error ending call: $e');
      // Игнорируем ошибки MissingPluginException
      if (!e.toString().contains('MissingPluginException') && 
          !e.toString().contains('initialize')) {
        rethrow;
      }
    }
  }

  Future<void> dispose() async {
    await endCall();
    await _localRenderer?.dispose();
    await _remoteRenderer?.dispose();
  }
}
