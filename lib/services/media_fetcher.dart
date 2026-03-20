import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes, kDebugMode, kIsWeb;
import '../config/api_config.dart';
import 'json_uploader.dart';

class MediaFetcher {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true; // PNG
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x39 || bytes[4] == 0x37) &&
        bytes[5] == 0x61) {
      return true; // GIF
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true; // WEBP
    }
    return false;
  }

  static Future<Uint8List?> fetchBytes(
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    final existing = _inflight[url];
    if (existing != null) {
      return existing;
    }

    final f = _fetchBytesInner(url, timeout: timeout);
    _inflight[url] = f;
    try {
      return await f;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<Uint8List?> _fetchBytesInner(
    String url, {
    required Duration timeout,
  }) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final isApiHost = host == Uri.parse(ApiConfig.baseUrl).host;

    Future<Uint8List?> _fetchWithClient(String label, HttpClient client) async {
      try {
        client.findProxy = (_) => 'DIRECT';
        client.connectionTimeout = const Duration(seconds: 12);
        client.idleTimeout = const Duration(seconds: 12);
        final req = await client.getUrl(uri).timeout(timeout);
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
        req.headers.set(HttpHeaders.userAgentHeader, 'MessengerApp/1.0.0 (iOS)');
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final res = await req.close().timeout(timeout);
        if (res.statusCode != 200) {
          if (kDebugMode) {
            print('🖼️ Media fetch ($label) failed: ${res.statusCode}');
          }
          return null;
        }
        final bytes = await consolidateHttpClientResponseBytes(res).timeout(timeout);
        if (bytes.isEmpty) return null;
        final out = Uint8List.fromList(bytes);
        if (!_looksLikeImage(out)) {
          if (kDebugMode) {
            print('🖼️ Media fetch ($label) rejected non-image payload (${out.length} bytes)');
          }
          return null;
        }
        return out;
      } catch (e) {
        if (kDebugMode) {
          print('🖼️ Media fetch ($label) exception: $e');
        }
        return null;
      } finally {
        try {
          client.close(force: true);
        } catch (_) {}
      }
    }

    Uint8List? out;
    // Fast path first: default HttpClient with global overrides/DoH.
    out = await _fetchWithClient('overrides', HttpClient());

    // Fallback: pinned edges for api.milviar.ru when default path is flaky.
    if (out == null && isApiHost) {
      final pinnedIps = <InternetAddress>[
        InternetAddress('172.67.154.188'),
        InternetAddress('104.21.5.195'),
      ];
      for (final ip in pinnedIps) {
        final hc = JsonUploader.pinnedTlsClient(host: host, ip: ip);
        out = await _fetchWithClient('pinned_${ip.address}', hc);
        if (out != null) break;
      }
    }

    // Final fallback: JSON chunked media download (works when binary hangs).
    out ??= await _fetchViaApiChunks(uri, timeout: timeout);

    if (out != null) {
      _cache[url] = out;
    }
    return out;
  }

  static String _extractFilename(Uri uri) {
    if (uri.pathSegments.isEmpty) return '';
    return uri.pathSegments.last;
  }

  static Future<Uint8List?> _fetchViaApiChunks(
    Uri mediaUri, {
    required Duration timeout,
  }) async {
    try {
      final base = Uri.parse(ApiConfig.baseUrl);
      // Some responses still contain `/uploads/<file>` or absolute urls pointing to `/uploads/*`.
      // We only need the final file name.
      final filename = _extractFilename(mediaUri);
      if (filename.isEmpty) return null;

      // IMPORTANT: Use GET `/api/media_chunk` instead of POST `/api/media/chunk`.
      // On some networks (and sometimes at Cloudflare edge), POST to certain paths may
      // return 520 HTML or hang, while GET + query string works reliably.
      final directBase = Uri.parse(ApiConfig.fallbackIpHttpBaseUrl);
      final endpointBase = base.replace(path: '/api/media_chunk');
      final endpointDirect = directBase.replace(path: '/api/media_chunk');
      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'MessengerApp/1.0.0 (iOS)',
      };

      // Avoid waiting 25s per chunk; better to fail fast and retry on a different path/client.
      final perReqTimeout = timeout.inSeconds <= 12 ? timeout : const Duration(seconds: 12);

      Future<IoHttpResponse?> _getWithClient(HttpClient client, String label, Uri uri) async {
        try {
          client.findProxy = (_) => 'DIRECT';
          client.connectionTimeout = const Duration(seconds: 10);
          client.idleTimeout = const Duration(seconds: 10);
          final req = await client.getUrl(uri).timeout(perReqTimeout);
          headers.forEach((k, v) => req.headers.set(k, v));
          req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          req.headers.removeAll(HttpHeaders.expectHeader);
          req.persistentConnection = false;
          req.headers.set(HttpHeaders.connectionHeader, 'close');
          final res = await req.close().timeout(perReqTimeout);
          final body = await utf8.decoder.bind(res).join().timeout(perReqTimeout);
          final out = IoHttpResponse(statusCode: res.statusCode, body: body);
          final code = out.statusCode;
          if (code != 200) {
            if (kDebugMode) {
              print('🖼️ Media chunk ($label) failed: $code body="${out.body}"');
            }
            return null;
          }
          return out;
        } catch (e) {
          if (kDebugMode) {
            print('🖼️ Media chunk ($label) exception: $e');
          }
          return null;
        } finally {
          try {
            client.close(force: true);
          } catch (_) {}
        }
      }

      final buf = BytesBuilder(copy: false);
      int offset = 0;
      // Smaller chunks tend to survive DPI/proxy buffering quirks better.
      const int chunkLen = 4096;
      int? size;

      // Pinned edges are flaky for this carrier path: they sometimes hang or return 520 HTML.
      // Use them only as a fallback if the normal (overrides/DoH) client cannot make progress.
      final pinnedIps = <InternetAddress>[
        InternetAddress('172.67.154.188'),
        InternetAddress('104.21.5.195'),
      ];

      int maxChunks = 2000;
      for (int i = 0; i < maxChunks; i++) {
        final query = <String, String>{
          'filename': filename,
          'offset': '$offset',
          'length': '$chunkLen',
        };
        final chunkUri = endpointBase.replace(queryParameters: query);
        final chunkUriDirect = endpointDirect.replace(queryParameters: query);

        IoHttpResponse? res;
        // 1) Normal HttpClient first (global overrides/DoH).
        res = await _getWithClient(HttpClient(), 'overrides', chunkUri);

        // 2) If that fails, try pinned edges.
        if (res == null) {
          for (final ip in pinnedIps) {
            final hc = JsonUploader.pinnedTlsClient(host: base.host, ip: ip);
            res = await _getWithClient(hc, 'pinned_${ip.address}', chunkUri);
            if (res != null) break;
          }
        }
        // 3) iOS final fallback: direct origin HTTP.
        if (res == null && !kIsWeb && Platform.isIOS) {
          res = await _getWithClient(HttpClient(), 'direct_origin', chunkUriDirect);
        }
        if (res == null) return null;

        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['error'] != null) return null;
        if (kDebugMode && i == 0) {
          print('🖼️ Media chunk ok: filename=$filename size=${j['size']} chunkLen=$chunkLen');
        }
        size ??= (j['size'] is int) ? j['size'] as int : int.tryParse('${j['size']}');
        if (size != null) {
          // Tighten loop bound once we know total size.
          maxChunks = ((size! + chunkLen - 1) ~/ chunkLen) + 2;
          // Safety: refuse absurd sizes to avoid memory blowups.
          if (size! > 25 * 1024 * 1024) return null;
        }
        final dataB64 = (j['dataBase64'] as String?) ?? '';
        if (dataB64.isNotEmpty) {
          buf.add(base64Decode(dataB64));
        }
        final nextOffset = (j['nextOffset'] is int)
            ? j['nextOffset'] as int
            : int.tryParse('${j['nextOffset']}') ?? (offset + chunkLen);
        final eof = j['eof'] == true;
        offset = nextOffset;
        if (eof) break;
        if (size != null && offset >= size) break;
      }

      final out = buf.takeBytes();
      if (out.isEmpty) return null;
      if (!_looksLikeImage(Uint8List.fromList(out))) {
        if (kDebugMode) {
          print('🖼️ Media chunk rejected non-image payload (${out.length} bytes)');
        }
        return null;
      }
      if (kDebugMode) {
        print('🖼️ Media chunk complete: filename=$filename bytes=${out.length}');
      }
      return Uint8List.fromList(out);
    } catch (e) {
      if (kDebugMode) {
        print('🖼️ Media chunk (final) exception: $e');
      }
      return null;
    }
  }
}

