/// Update configuration provider.
///
/// Fetches the remote app update configuration from Supabase.
/// Uses anon key (read-only) via PostgREST.
/// Caches successful responses for offline resilience.
library update_config_provider;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'update_config.dart';
import '../telemetry/telemetry_config.dart';
import '../providers/app_providers.dart';

/// Cache key for update config in SharedPreferences.
const String _updateConfigCacheKey = 'update_config_cache';

/// Cache TTL (24 hours).
const Duration _updateConfigCacheTtl = Duration(hours: 24);

/// Remote update configuration provider.
///
/// Fetches config from Supabase `app_config` table via PostgREST.
/// Returns cached config on network failure.
final updateConfigProvider = FutureProvider.autoDispose<UpdateConfig>((ref) async {
  // `const` ile derleyiciye bunlarin compile-time sabit oldugunu acikca belirtir:
  // degerler SADECE build sirasinda --dart-define ile verilebilir.
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || anonKey.isEmpty) {
    // Bu tam olarak "forced update hic cikmiyor" root cause'idir: degerler
    // compile-time tanimsiz kalirsa hicbir HTTP cagrisi yapilmaz.
    debugPrint(
      '[UpdateConfig] SUPABASE_URL/SUPABASE_ANON_KEY compile-time BOS. '
      'Bu degerler String.fromEnvironment ile SADECE build sirasinda verilir; '
      'duz "flutter build apk --release" ile derlenince bos kalirlar ve '
      'update sistemi sessizce devre disi kalir. '
      'Duzeltme: scripts\\build_release.ps1 ile build et (dot-env dosyasindan '
      '--dart-define olarak otomatik gecer) veya elle '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... ver. '
      'urlDolu=${url.isNotEmpty} anonKeyDolu=${anonKey.isNotEmpty}',
    );
    throw const UpdateConfigException('Supabase config not provided');
  }

  final prefs = ref.read(sharedPreferencesProvider);
  final client = http.Client();
  
  try {
    final response = await client
        .get(
          Uri.parse('$url/rest/v1/app_config?select=key,value'),
          headers: {
            'apikey': anonKey,
            'Authorization': 'Bearer $anonKey',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateConfigException('HTTP ${response.statusCode}: ${response.body}');
    }

    final List<dynamic> rows = jsonDecode(response.body);
    final map = <String, String>{};
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key != null && value != null) {
        map[key] = value;
      }
    }

    final config = UpdateConfig(
      latestVersion: map['latest_version'] ?? '1.0.0',
      minimumVersion: map['minimum_version'] ?? '1.0.0',
      downloadUrl: map['download_url'] ?? 'https://kyronapp.pages.dev/',
    );

    // Cache successful response
    await _cacheConfig(prefs, config);

    return config;
  } catch (e) {
    // On network failure, try to return cached config
    final cached = _getCachedConfig(prefs);
    if (cached != null) {
      return cached;
    }
    rethrow;
  } finally {
    client.close();
  }
});

/// Caches the update config with timestamp.
Future<void> _cacheConfig(SharedPreferences prefs, UpdateConfig config) async {
  final cacheData = {
    'config': config.toJson(),
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  await prefs.setString(_updateConfigCacheKey, jsonEncode(cacheData));
}

/// Retrieves cached config if not expired.
UpdateConfig? _getCachedConfig(SharedPreferences prefs) {
  final jsonStr = prefs.getString(_updateConfigCacheKey);
  if (jsonStr == null) return null;

  try {
    final cacheData = jsonDecode(jsonStr) as Map<String, dynamic>;
    final timestamp = cacheData['timestamp'] as int?;
    if (timestamp == null) return null;

    final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedTime) > _updateConfigCacheTtl) {
      // Cache expired
      return null;
    }

    final configJson = cacheData['config'] as Map<String, dynamic>?;
    if (configJson == null) return null;

    return UpdateConfig.fromJson(configJson);
  } catch (_) {
    return null;
  }
}

/// Exception thrown when update config fetch fails.
class UpdateConfigException implements Exception {
  const UpdateConfigException(this.message);

  final String message;

  @override
  String toString() => 'UpdateConfigException: $message';
}