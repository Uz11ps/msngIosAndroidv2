import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../services/media_fetcher.dart';
import '../utils/image_utils.dart';

class AdaptiveAvatar extends StatefulWidget {
  const AdaptiveAvatar({
    super.key,
    required this.photoUrl,
    required this.radius,
    required this.backgroundColor,
    required this.fallbackChild,
  });

  final String? photoUrl;
  final double radius;
  final Color backgroundColor;
  final Widget fallbackChild;

  @override
  State<AdaptiveAvatar> createState() => _AdaptiveAvatarState();
}

class _AdaptiveAvatarState extends State<AdaptiveAvatar> {
  Future<Uint8List?>? _bytesFuture;
  String _resolvedUrl = '';
  bool _useFetcher = false;

  bool get _useIosMediaFetcher =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AdaptiveAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _prepare();
    }
  }

  void _prepare() {
    _resolvedUrl = ImageUtils.getFullImageUrl(widget.photoUrl);
    if (_resolvedUrl.isEmpty || !_useIosMediaFetcher) {
      _useFetcher = false;
      _bytesFuture = null;
      return;
    }
    // On Wi-Fi, regular NetworkImage is usually faster and lighter for chat list avatars.
    // Keep robust MediaFetcher only on mobile/other networks where proxies are less stable.
    Connectivity()
        .checkConnectivity()
        .then((results) {
          final isCellular = results.contains(ConnectivityResult.mobile) ||
              results.contains(ConnectivityResult.other);
          if (!mounted) return;
          setState(() {
            _useFetcher = isCellular;
            _bytesFuture = _useFetcher
                ? MediaFetcher.fetchBytes(_resolvedUrl, timeout: const Duration(seconds: 12))
                : null;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _useFetcher = false;
            _bytesFuture = null;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedUrl.isEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.backgroundColor,
        child: widget.fallbackChild,
      );
    }

    if (!_useIosMediaFetcher || !_useFetcher) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.backgroundColor,
        backgroundImage: NetworkImage(_resolvedUrl),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Container(
            width: widget.radius * 2,
            height: widget.radius * 2,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: widget.fallbackChild),
            ),
          );
        }
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: widget.backgroundColor,
          child: widget.fallbackChild,
        );
      },
    );
  }
}
