/// Uygulama genelinde tip guvenli hata modeli.
///
/// UI asla ham exception gormez; her hata bir [Failure]a donusturulur.
/// Loading / error / empty / offline state yonetimi bu sinif uzerinden yapilir.
///
/// Not: Dart'ta bir fonksiyonda ayni anda opsiyonel positional ve named
/// parametre kullanilamaz; bu yuzden tum alanlar konumsal tanimlanir.
sealed class Failure {
  const Failure([this.message = 'Beklenmeyen bir hata oluştu.', this.cause]);

  /// Kullaniciya gosterilecek (Turkce) aciklama.
  final String message;

  /// Teknik detay; yalnizca log icin. UI'da gosterilmez.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Internet baglantisi yok veya istek basarisiz.
class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'İnternet bağlantısı kurulamadı.',
    super.cause,
  ]);
}

/// Sunucu 5xx ya da beklenmeyen bir HTTP durum kodu.
class ServerFailure extends Failure {
  const ServerFailure([
    super.message = 'Sunucudan yanıt alınamadı.',
    super.cause,
  ]);
}

/// Sunucu 4xx - istek hatali (yanlis sembol, yetkisiz vb.).
class BadRequestFailure extends Failure {
  const BadRequestFailure([
    super.message = 'İstek geçersiz.',
    super.cause,
  ]);
}

/// Zaman asimi.
class TimeoutFailure extends Failure {
  const TimeoutFailure([
    super.message = 'Sunucu zaman aşımına uğradı. Tekrar deneyin.',
    super.cause,
  ]);
}

/// Veri formati beklendigi gibi degil (bozuk JSON/XML).
class ParseFailure extends Failure {
  const ParseFailure([
    super.message = 'Veri okunamadı.',
    super.cause,
  ]);
}

/// Kaynakta hic veri yok (gercek bos durum).
class EmptyFailure extends Failure {
  const EmptyFailure([
    super.message = 'Gösterilecek veri bulunamadı.',
    super.cause,
  ]);
}

/// Baglanti yok ama onbellekte son gecerli veri var.
class OfflineFailure extends Failure {
  const OfflineFailure([
    super.message = 'Çevrimdışısınız. Gösterilen veri son güncellemedir.',
    super.cause,
  ]);
}

/// Bilinmeyen/ beklenmeyen hata.
class UnknownFailure extends Failure {
  const UnknownFailure([
    super.message = 'Beklenmeyen bir hata oluştu.',
    super.cause,
  ]);
}

/// Sonucu ya veri ya da hata olarak tasuyan sarmalayici.
///
/// Veri asla null gecirilmez: ya [data] doludur ya da [failure].
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Err<T>;

  /// Basari durumunda veriyi, hata durumunda null dondurur.
  T? get dataOrNull => switch (this) {
        Success<T>(:final data) => data,
        Err<T>() => null,
      };

  /// Hata durumunda [Failure], basari durumunda null dondurur.
  Failure? get failureOrNull => switch (this) {
        Err<T>(:final failure) => failure,
        Success<T>() => null,
      };

  R when<R>({
    required R Function(T data) onSuccess,
    required R Function(Failure failure) onFailure,
  }) =>
      switch (this) {
        Success<T>(:final data) => onSuccess(data),
        Err<T>(:final failure) => onFailure(failure),
      };

  Result<R> mapData<R>(R Function(T data) transform) => switch (this) {
        Success<T>(:final data) => Success(transform(data)),
        Err<T>(:final failure) => Err(failure),
      };
}

final class Success<T> extends Result<T> {
  const Success(this.data);

  final T data;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
