import 'dart:io';

import 'doh_resolver.dart';

class DohHttpOverrides extends HttpOverrides {
  DohHttpOverrides({
    required this.resolver,
    required this.targetHosts,
    required this.edgeFallbackIps,
  });

  final DohResolver resolver;
  final Set<String> targetHosts;
  final List<InternetAddress> edgeFallbackIps;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Override DNS resolution for specific hosts by using DoH to obtain an IP,
    // then connecting to that IP while keeping the original host for TLS/SNI.
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final host = uri.host;
      final scheme = uri.scheme;
      final isTls = scheme == 'https' || scheme == 'wss';
      final defaultPort = isTls ? 443 : 80;
      final port = (uri.hasPort && uri.port != 0) ? uri.port : defaultPort;

      if (targetHosts.contains(host)) {
        // 1) Preferred: DoH-based A lookup (avoids carrier DNS poisoning/NXDOMAIN).
        try {
          final ip = await resolver.resolveA(host);
          print('🌐 DoH: resolved $host -> ${ip.address}');
          if (isTls) {
            final tcp = Socket.connect(ip, port).timeout(const Duration(seconds: 15));
            final tls = tcp.then((s) => SecureSocket.secure(s, host: host));
            return ConnectionTask.fromSocket(tls, () {});
          }
          return Socket.startConnect(ip.address, port).timeout(const Duration(seconds: 15));
        } catch (e) {
          print('⚠️ DoH resolve failed for $host: $e');
        }

        // 2) If DoH is blocked, try connecting to known Cloudflare edge IPs for this host.
        for (final ip in edgeFallbackIps) {
          try {
            print('🌐 Edge fallback: connecting $host via ${ip.address}:$port');
            if (isTls) {
              final tcp = Socket.connect(ip, port).timeout(const Duration(seconds: 10));
              final tls = tcp.then((s) => SecureSocket.secure(s, host: host));
              return ConnectionTask.fromSocket(tls, () {});
            }
            return Socket.startConnect(ip.address, port).timeout(const Duration(seconds: 10));
          } catch (e) {
            print('⚠️ Edge fallback failed via ${ip.address}: $e');
          }
        }

        // 3) Last resort: system DNS (may fail on Megafon, but keep behavior normal elsewhere).
        if (isTls) {
          final tcp = Socket.connect(host, port).timeout(const Duration(seconds: 15));
          final tls = tcp.then((s) => SecureSocket.secure(s, host: host));
          return ConnectionTask.fromSocket(tls, () {});
        }
        return Socket.startConnect(host, port).timeout(const Duration(seconds: 15));
      }

      if (isTls) {
        final tcp = Socket.connect(host, port).timeout(const Duration(seconds: 15));
        final tls = tcp.then((s) => SecureSocket.secure(s, host: host));
        return ConnectionTask.fromSocket(tls, () {});
      }
      return Socket.startConnect(host, port).timeout(const Duration(seconds: 15));
    };

    return client;
  }
}

