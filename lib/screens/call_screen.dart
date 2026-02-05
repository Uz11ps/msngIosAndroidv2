import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../services/agora_service.dart';

class CallScreen extends StatefulWidget {
  final AgoraService agoraService;
  final bool isVideo;
  final VoidCallback onEndCall;

  const CallScreen({
    super.key,
    required this.agoraService,
    required this.isVideo,
    required this.onEndCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  int? _remoteUid;

  @override
  void initState() {
    super.initState();
    // Настраиваем обработчики событий Agora
    widget.agoraService.onUserJoined = (uid, elapsed) {
      setState(() {
        _remoteUid = uid;
      });
    };
    widget.agoraService.onUserOffline = (uid, reason) {
      setState(() {
        _remoteUid = null;
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Удаленное видео (если видео звонок)
          if (widget.isVideo && _remoteUid != null && widget.agoraService.engine != null)
            Positioned.fill(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: widget.agoraService.engine!,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: widget.agoraService.connection ?? RtcConnection(channelId: ''),
                ),
              ),
            ),
          
          // Локальное видео (если видео звонок)
          if (widget.isVideo)
            Positioned(
              top: 40,
              right: 20,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: widget.agoraService.engine!,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                ),
              ),
            ),
          
          // Аудио звонок - показываем информацию
          if (!widget.isVideo)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Аудио звонок',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ],
              ),
            ),
          
          // Кнопки управления
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Кнопка микрофона
                IconButton(
                  icon: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                    // Отключаем/включаем микрофон через Agora
                    widget.agoraService.toggleMute(_isMuted);
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(width: 20),
                
                // Кнопка завершения звонка
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.white),
                  onPressed: widget.onEndCall,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(width: 20),
                
                // Кнопка видео (только для видео звонков)
                if (widget.isVideo)
                  IconButton(
                    icon: Icon(
                      _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isVideoEnabled = !_isVideoEnabled;
                      });
                      // Отключаем/включаем камеру через Agora
                      widget.agoraService.toggleVideo(_isVideoEnabled);
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      padding: const EdgeInsets.all(16),
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
