import 'dart:io';

import 'doh_http_overrides.dart';
import 'doh_resolver.dart';

Future<void> setupNetworkOverrides() async {
  // Some carrier networks break DNS resolution for specific domains.
  // DoH-based overrides let HTTPS keep working without relying on the carrier DNS.
  HttpOverrides.global = DohHttpOverrides(
    resolver: DohResolver(),
    targetHosts: <String>{'api.milviar.ru'},
    edgeFallbackIps: <InternetAddress>[
      // Resolved via 1.1.1.1; used only when carrier DNS + DoH are blocked.
      InternetAddress('172.67.154.188'),
      InternetAddress('104.21.5.195'),
      InternetAddress('2606:4700:3033::ac43:9abc'),
      InternetAddress('2606:4700:3033::6815:5c3'),
    ],
  );
  print('🌐 Network overrides enabled: DoH + Cloudflare edge fallback for api.milviar.ru');
}

