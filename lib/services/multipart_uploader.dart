import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MultipartUploadResponse {
  MultipartUploadResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class MultipartUploader {
  // Manual multipart upload using dart:io HttpClient.
  //
  // Why not package:http MultipartRequest?
  // - On some iOS networks/paths, chunked multipart uploads can hang/timeout.
  // - Here we always set Content-Length explicitly.
  static Future<MultipartUploadResponse> uploadFile({
    required HttpClient httpClient,
    required Uri uri,
    required String filePath,
    required Map<String, String> headers,
    String fieldName = 'file',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final started = DateTime.now();
    final file = File(filePath);
    final fileLen = await file.length();
    final filename = _basename(filePath);
    final boundary = '----msng_${DateTime.now().microsecondsSinceEpoch}';

    final preamble = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n')
      ..write('Content-Type: application/octet-stream\r\n')
      ..write('\r\n');
    final epilogue = '\r\n--$boundary--\r\n';

    final preBytes = utf8.encode(preamble.toString());
    final epiBytes = utf8.encode(epilogue);
    final contentLength = preBytes.length + fileLen + epiBytes.length;

    print('📤 Upload(start): uri=$uri fileLen=$fileLen contentLen=$contentLength');
    final req = await httpClient.postUrl(uri).timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    // Avoid "Expect: 100-continue" edge cases.
    req.headers.removeAll(HttpHeaders.expectHeader);
    req.contentLength = contentLength;
    req.persistentConnection = false;
    req.headers.set(HttpHeaders.connectionHeader, 'close');

    req.add(preBytes);
    print('📤 Upload: wrote preamble (${preBytes.length} bytes), streaming file...');
    await req.addStream(file.openRead()).timeout(timeout);
    print('📤 Upload: file stream complete, writing epilogue (${epiBytes.length} bytes)...');
    req.add(epiBytes);

    print('📤 Upload: closing request...');
    final res = await req.close().timeout(timeout);
    print('📤 Upload: response status=${res.statusCode} reading body...');
    final body = await utf8.decoder.bind(res).join().timeout(timeout);
    final ms = DateTime.now().difference(started).inMilliseconds;
    print('📤 Upload(done): status=${res.statusCode} elapsedMs=$ms');
    return MultipartUploadResponse(statusCode: res.statusCode, body: body);
  }

  static String _basename(String path) {
    final idx = path.lastIndexOf(Platform.pathSeparator);
    if (idx < 0) return path;
    return path.substring(idx + 1);
  }
}

