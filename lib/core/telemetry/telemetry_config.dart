/// Anonim telemetri yapilandirmasi (Supabase).
///
/// Degerler yalnizca build sirasinda `--dart-define` ile verilir (projenin
/// mevcut gizli anahtar konvansiyonu ile ayni; bkz.
/// `lib/domain/providers/stream_market_data_provider.dart`):
///
///     flutter build apk \
///       --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///       --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
///
/// * `SUPABASE_URL`  : Supabase proje URL'si.
/// * `SUPABASE_ANON_KEY` : **anon (publishable)** anahtari. Bu anahtar
///   APK'nin icinde bulunabilir; RLS tarafinda okuma kapali oldugu icin
///   veri cekilemez.
///
/// **service-role key hicbir yere yazilmaz** (ne Flutter'a ne web'e; yalnizca
/// Supabase server-side ortaminda calisir).
///
/// Iki degerden biri bile bosken telemetri **tamamen pasif**tir: ag cagrisi
/// yapilmaz, kimlik uretilmez, uygulama normal calisir.
class TelemetryConfig {
  const TelemetryConfig._();

  /// Supabase proje URL'si (`--dart-define=SUPABASE_URL=...`).
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon anahtari (`--dart-define=SUPABASE_ANON_KEY=...`).
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Telemetri yalnizca iki tanim da verildiginde aciktir.
  static bool get enabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
