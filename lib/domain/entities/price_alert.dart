/// Alarm turu.
enum AlertType {
  /// Fiyat, hedef seviyenin uzerine cikarsa.
  priceAbove('Fiyat üzerine çıkar'),

  /// Fiyat, hedef seviyenin altina inerse.
  priceBelow('Fiyat altına iner'),

  /// Guncel degisim, verilen orani gecerse (yon belirtilebilir).
  percentChange('% değişim'),

  /// Fiyat gunun en yuksegine ulasirsa (dogrudan kaynak degeri).
  dayHigh('Gün en yükseği'),

  /// Fiyat gunun en dusugune ulasirsa (dogrudan kaynak degeri).
  dayLow('Gün en düşüğü'),

  /// Secili kategoride yeni onemli haber geldiginde.
  importantNews('Önemli haber');

  const AlertType(this.label);

  final String label;
}

/// Yon (yuzde alarmlari icin). Fiyat alarmlarinda anlami yoktur.
enum AlertDirection {
  above('üzerinde'),
  below('altında');

  const AlertDirection(this.label);

  final String label;
}

/// Kullanici tanimli alarm.
///
/// **Kural:** Bu sinif yalnizca **kosul** tasir; hicbir zaman "gerceklesen
/// fiyat" veya "sonuc" uretmez. Degerler kaynak'tan gelir ve `null` birakilabilir.
class PriceAlert {
  PriceAlert({
    String? id,
    required this.type,
    this.assetId,
    this.threshold,
    this.percent,
    this.direction = AlertDirection.above,
    this.newsCategory,
    this.enabled = true,
    this.repeat = false,
    DateTime? createdAt,
    this.triggeredAt,
  })  : id = id ?? _nextId(),
        createdAt = createdAt ?? DateTime.now();

  /// Tekrarlanabilir, deterministik olmayan ancak cakismasiz kimlik uretimi.
  /// (Ek paket gerekmez; yalnizca zaman damgasi + sayac.)
  static int _seq = 0;
  static String _nextId() {
    _seq = (_seq + 1) & 0x7fffffff;
    return 'a${DateTime.now().microsecondsSinceEpoch}$_seq';
  }

  final String id;

  /// Varsayilan 404 icin random degil; deterministik uretim icin `id` disinda
  /// hicbir ozellik alinmaz.
  final AlertType type;

  /// Alarm'a bagli varlik. [AlertType.importantNews] disinda zorunludur.
  final String? assetId;

  /// Hedef seviye (fiyat alarmlari icin). `null` ise alarm henuz tanimsizdir.
  final double? threshold;

  /// Yuzde esigi (yalnizca [AlertType.percentChange]).
  final double? percent;

  /// Yuzde alarminda yon.
  final AlertDirection direction;

  /// [AlertType.importantNews] icin haber kategorisi (`null` = tumu).
  final String? newsCategory;

  final bool enabled;

  /// Kosul saglandiktan sonra tekrar tekrar bildirilsin mi?
  final bool repeat;

  final DateTime createdAt;

  /// En son tetiklenme anı. `null` = hic tetiklenmedi.
  final DateTime? triggeredAt;

  /// Tanimin anlamliligi. Gecersiz alarm asla degerlendirilmez.
  bool get isValid {
    switch (type) {
      case AlertType.priceAbove:
      case AlertType.priceBelow:
        return assetId != null && threshold != null && threshold!.isFinite;
      case AlertType.percentChange:
        return assetId != null && percent != null && percent!.isFinite;
      case AlertType.dayHigh:
      case AlertType.dayLow:
        return assetId != null;
      case AlertType.importantNews:
        return true;
    }
  }

  /// Bildirim metni (nesnel). Kullanilmadan once kaynak degeri verilir.
  bool get isArmed => enabled && isValid;

  PriceAlert copyWith({
    bool? enabled,
    double? threshold,
    double? percent,
    AlertDirection? direction,
    String? newsCategory,
    bool? repeat,
    DateTime? triggeredAt,
    bool clearTriggered = false,
  }) {
    return PriceAlert(
      id: id,
      type: type,
      assetId: assetId,
      threshold: threshold ?? this.threshold,
      percent: percent ?? this.percent,
      direction: direction ?? this.direction,
      newsCategory: newsCategory ?? this.newsCategory,
      enabled: enabled ?? this.enabled,
      repeat: repeat ?? this.repeat,
      createdAt: createdAt,
      triggeredAt: clearTriggered ? null : (triggeredAt ?? this.triggeredAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'assetId': assetId,
        'threshold': threshold,
        'percent': percent,
        'direction': direction.name,
        'newsCategory': newsCategory,
        'enabled': enabled,
        'repeat': repeat,
        'createdAt': createdAt.toIso8601String(),
        'triggeredAt': triggeredAt?.toIso8601String(),
      };

  /// Bozuk/eksik JSON'dan alarm **uretilmez** (null donulur).
  static PriceAlert? fromJson(Map<String, dynamic> json) {
    try {
      final typeName = json['type'];
      final type = AlertType.values.where((t) => t.name == typeName).firstOrNull;
      if (type == null) return null;

      double? numField(String key) {
        final v = json[key];
        if (v is num && v.isFinite) return v.toDouble();
        return null;
      }

      final directionName = json['direction'];
      final direction = AlertDirection.values
              .where((d) => d.name == directionName)
              .firstOrNull ??
          AlertDirection.above;

      final alert = PriceAlert(
        id: json['id'] is String ? json['id'] as String : null,
        type: type,
        assetId: json['assetId'] is String ? json['assetId'] as String : null,
        threshold: numField('threshold'),
        percent: numField('percent'),
        direction: direction,
        newsCategory:
            json['newsCategory'] is String ? json['newsCategory'] as String : null,
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
        repeat: json['repeat'] is bool ? json['repeat'] as bool : false,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        triggeredAt: json['triggeredAt'] is String
            ? DateTime.tryParse(json['triggeredAt'] as String)
            : null,
      );
      return alert.isValid ? alert : null;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is PriceAlert && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
