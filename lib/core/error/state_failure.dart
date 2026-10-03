import 'failures.dart';

/// [AsyncNotifier] / [FutureProvider] icinde firlatilan, uzerinde
/// [Failure] tasuyan sarmalayici hata.
///
/// Bu sayede Riverpod'un `AsyncError(error: ...)` degeri uzerinden
/// gercek hata modeline ulasilabilir ve UI Turkce mesaj gosterir.
class StateFailure implements Exception {
  const StateFailure(this.failure);

  final Failure failure;

  /// Kolay olusturma.
  static StateFailure of(Failure failure) => StateFailure(failure);

  /// Bilinmeyen bir istisnayi [Failure]a donusturur.
  static Failure from(Object error) {
    if (error is StateFailure) return error.failure;
    if (error is Failure) return error;
    return UnknownFailure('Beklenmeyen bir hata oluştu.', error);
  }

  @override
  String toString() => 'StateFailure: ${failure.message}';
}
