import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class IoHttpResponse {
  IoHttpResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

class JsonUploader {
  static Future<IoHttpResponse> postJson({
    required HttpClient httpClient,
    required Uri uri,
    required Map<String, String> headers,
    required Object bodyJson,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final bodyStr = jsonEncode(bodyJson);
    final bodyBytes = utf8.encode(bodyStr);

    final req = await httpClient.postUrl(uri).timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.removeAll(HttpHeaders.expectHeader);
    req.persistentConnection = false;
    req.headers.set(HttpHeaders.connectionHeader, 'close');
    req.contentLength = bodyBytes.length;
    req.add(bodyBytes);

    final res = await req.close().timeout(timeout);
    final body = await utf8.decoder.bind(res).join().timeout(timeout);
    return IoHttpResponse(statusCode: res.statusCode, body: body);
  }

  static HttpClient pinnedTlsClient({
    required String host,
    required InternetAddress ip,
    Duration connectTimeout = const Duration(seconds: 6),
  }) {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.maxConnectionsPerHost = 1;
    client.connectionTimeout = connectTimeout;
    client.idleTimeout = const Duration(seconds: 10);

    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final isTls = uri.scheme == 'https' || uri.scheme == 'wss';
      final port = (uri.hasPort && uri.port != 0) ? uri.port : (isTls ? 443 : 80);
      if (!isTls) {
        return Socket.startConnect(ip.address, port).timeout(connectTimeout);
      }
      final tcp = Socket.connect(ip, port).timeout(connectTimeout);
      final tls = tcp.then((s) => SecureSocket.secure(s, host: host));
      return ConnectionTask.fromSocket(tls, () {});
    };
    return client;
  }

  static Future<String?> uploadFileBase64Chunked({
    required Uri baseUri,
    required String token,
    required String filePath,
    Duration timeoutPerReq = const Duration(seconds: 20),
    int chunkBytes = 4096,
  }) async {
    final file = File(filePath);
    final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file.bin';
    final initUri = baseUri.replace(path: '/api/upload-chunks/init');
    final partUri = baseUri.replace(path: '/api/upload-chunks/part');
    final completeUri = baseUri.replace(path: '/api/upload-chunks/complete');

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'User-Agent': 'MessengerApp/1.0.0 (iOS)',
      'Accept': 'application/json',
    };

    final pinnedIps = <InternetAddress>[
      InternetAddress('172.67.154.188'),
      InternetAddress('104.21.5.195'),
    ];

    Future<IoHttpResponse> _postReliable(Uri uri, Object body) async {
      Object? lastErr;
      // 1) Prefer normal client first (uses global HttpOverrides/DoH), which is
      // often more stable than hard-pinned edges on mobile carrier paths.
      final normal = HttpClient();
      try {
        return await postJson(
          httpClient: normal,
          uri: uri,
          headers: headers,
          bodyJson: body,
          timeout: timeoutPerReq,
        );
      } catch (e) {
        lastErr = e;
      } finally {
        try {
          normal.close(force: true);
        } catch (_) {}
      }

      // 2) Fallback to pinned edges only if normal path failed.
      for (final ip in pinnedIps) {
        final hc = pinnedTlsClient(host: uri.host, ip: ip);
        try {
          return await postJson(
            httpClient: hc,
            uri: uri,
            headers: headers,
            bodyJson: body,
            timeout: timeoutPerReq,
          );
        } catch (e) {
          lastErr = e;
        } finally {
          try {
            hc.close(force: true);
          } catch (_) {}
        }
      }
      if (lastErr != null) {
        throw lastErr!;
      }
      throw Exception('upload chunk failed');
    }

    // 1) init
    final initRes = await _postReliable(initUri, <String, dynamic>{'filename': filename});
    if (initRes.statusCode != 200) {
      return null;
    }
    final initJson = jsonDecode(initRes.body) as Map<String, dynamic>;
    final uploadId = initJson['uploadId'] as String?;
    if (uploadId == null || uploadId.isEmpty) return null;

    // 2) parts
    int index = 0;
    await for (final chunk in file.openRead().transform(_ChunkTransformer(chunkBytes))) {
      final partRes = await _postReliable(
        partUri,
        <String, dynamic>{
          'uploadId': uploadId,
          'index': index,
          'dataBase64': base64Encode(chunk),
        },
      );
      if (partRes.statusCode != 200) {
        return null;
      }
      index++;
    }

    // 3) complete
    final doneRes = await _postReliable(completeUri, <String, dynamic>{'uploadId': uploadId});
    if (doneRes.statusCode != 200) return null;
    final doneJson = jsonDecode(doneRes.body) as Map<String, dynamic>;
    return doneJson['url'] as String?;
  }
}

class _ChunkTransformer extends StreamTransformerBase<List<int>, List<int>> {
  _ChunkTransformer(this.chunkSize);
  final int chunkSize;

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) async* {
    final buffer = BytesBuilder(copy: false);
    await for (final data in stream) {
      buffer.add(data);
      while (buffer.length >= chunkSize) {
        final bytes = buffer.takeBytes();
        // takeBytes empties; we may have more than chunkSize. Put remainder back.
        if (bytes.length == chunkSize) {
          yield bytes;
        } else {
          yield bytes.sublist(0, chunkSize);
          buffer.add(bytes.sublist(chunkSize));
        }
      }
    }
    if (buffer.length > 0) {
      yield buffer.takeBytes();
    }
  }
}

