import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../features/alerts/alerts_screen.dart';
import '../../features/asset_detail/asset_detail_screen.dart';

/// Varlik detay sayfasina gecis.
///
/// Ayri bir routa ihtiyac duymadan, mevcut navigasyon yiginini kullanir.
void openAssetDetail(BuildContext context, String assetId) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => AssetDetailScreen(assetId: assetId),
    ),
  );
}

/// Alarmlar sayfasina gecis.
void openAlerts(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
  );
}

/// Haberin orijinal kaynaginda acilmasi (telif: ozet gosterilir, metin kopyalanmaz).
Future<void> launchNewsUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return;
  }
  try {
    await launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    );
  } catch (_) {
    // Uygulama disinda tarayici acilamadi; sessizce yutulur.
  }
}
