import 'dart:convert';
import 'dart:io';

class DohResolver {
  final Map<String, InternetAddress> _cache = <String, InternetAddress>{};
  final Map<String, int> _cacheTsMs = <String, int>{};

  static final List<Uri> _providers = <Uri>[
    // Cloudflare DoH via IP (sometimes hostnames are filtered, but IP is reachable)
    Uri(scheme: 'https', host: '1.1.1.1', path: '/dns-query'),
    // Cloudflare DoH (dns-json)
    Uri(scheme: 'https', host: 'cloudflare-dns.com', path: '/dns-query'),
    // Google DoH JSON
    Uri(scheme: 'https', host: 'dns.google', path: '/resolve'),
    // Quad9 DoH (dns-json)
    Uri(scheme: 'https', host: 'dns.quad9.net', path: '/dns-query'),
    // Cloudflare DoH alias
    Uri(scheme: 'https', host: 'mozilla.cloudflare-dns.com', path: '/dns-query'),
  ];

  Future<InternetAddress> resolveA(String host) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cache[host];
    final ts = _cacheTsMs[host];
    if (cached != null && ts != null && now - ts < 5 * 60 * 1000) {
      return cached;
    }

    Exception? lastErr;
    for (final base in _providers) {
      final uri = base.replace(queryParameters: <String, String>{
        'name': host,
        'type': 'A',
      });

      final client = HttpClient();
      client.userAgent = 'MessengerApp/DoH';
      client.connectionTimeout = const Duration(seconds: 10);
      // Avoid carrier proxies that can sometimes interfere.
      client.findProxy = (_) => 'DIRECT';

      try {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
        // Both endpoints understand JSON; Cloudflare/Quad9 require dns-json accept.
        req.headers.set('accept', 'application/dns-json, application/json');
        final res = await req.close().timeout(const Duration(seconds: 10));
        final body = await utf8.decodeStream(res);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('DoH ${base.host} HTTP ${res.statusCode}: $body');
        }
        final json = jsonDecode(body);
        if (json is! Map<String, dynamic>) {
          throw Exception('DoH ${base.host}: bad JSON');
        }
        final answer = json['Answer'];
        if (answer is List) {
          for (final row in answer) {
            if (row is Map<String, dynamic>) {
              final data = row['data'];
              if (data is String && RegExp(r'^[0-9.]+$').hasMatch(data)) {
                final ip = InternetAddress(data);
                _cache[host] = ip;
                _cacheTsMs[host] = now;
                return ip;
              }
            }
          }
        }
        lastErr = Exception('DoH ${base.host}: no A record for $host');
      } catch (e) {
        lastErr = e is Exception ? e : Exception(e.toString());
      } finally {
        client.close(force: true);
      }
    }

    // As a last resort, try system DNS (may still fail on Megafon, but avoids
    // getting stuck on blocked DoH providers).
    try {
      final addrs = await InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(seconds: 5));
      if (addrs.isNotEmpty) {
        _cache[host] = addrs.first;
        _cacheTsMs[host] = now;
        return addrs.first;
      }
    } catch (e) {
      lastErr = e is Exception ? e : Exception(e.toString());
    }

    throw lastErr ?? Exception('DoH resolve failed for $host');
  }
}

