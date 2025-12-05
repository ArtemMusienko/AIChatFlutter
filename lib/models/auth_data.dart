// Модель данных аутентификации
class AuthData {
  // API ключ пользователя
  final String apiKey;
  // PIN-код для быстрого входа
  final String pin;
  // Тип провайдера (openrouter или vsegpt)
  final ProviderType providerType;
  // Последний известный баланс
  final String lastBalance;
  // Время последней проверки баланса
  final DateTime lastChecked;

  AuthData({
    required this.apiKey,
    required this.pin,
    required this.providerType,
    required this.lastBalance,
    required this.lastChecked,
  });

  // Преобразование объекта в Map для сохранения в БД
  Map<String, dynamic> toMap() {
    return {
      'api_key': apiKey,
      'pin': pin,
      'provider_type': providerType.toString().split('.').last,
      'last_balance': lastBalance,
      'last_checked': lastChecked.toIso8601String(),
    };
  }

  // Создание объекта из Map (из БД)
  factory AuthData.fromMap(Map<String, dynamic> map) {
    return AuthData(
      apiKey: map['api_key'] as String,
      pin: map['pin'] as String,
      providerType: ProviderType.values.firstWhere(
        (e) => e.toString().split('.').last == map['provider_type'],
      ),
      lastBalance: map['last_balance'] as String,
      lastChecked: DateTime.parse(map['last_checked'] as String),
    );
  }

  // Копирование объекта с изменением полей
  AuthData copyWith({
    String? apiKey,
    String? pin,
    ProviderType? providerType,
    String? lastBalance,
    DateTime? lastChecked,
  }) {
    return AuthData(
      apiKey: apiKey ?? this.apiKey,
      pin: pin ?? this.pin,
      providerType: providerType ?? this.providerType,
      lastBalance: lastBalance ?? this.lastBalance,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

// Перечисление типов провайдеров
enum ProviderType {
  openrouter, // OpenRouter API
  vsegpt, // VSEGPT API
}

// Расширение для работы с ProviderType
extension ProviderTypeExtension on ProviderType {
  // Получение базового URL для провайдера
  String get baseUrl {
    switch (this) {
      case ProviderType.openrouter:
        return 'https://openrouter.ai/api/v1';
      case ProviderType.vsegpt:
        return 'https://api.vsegpt.ru/v1';
    }
  }

  // Получение названия провайдера
  String get displayName {
    switch (this) {
      case ProviderType.openrouter:
        return 'OpenRouter';
      case ProviderType.vsegpt:
        return 'VSEGPT';
    }
  }

  // Определение типа провайдера по API ключу
  static ProviderType fromApiKey(String apiKey) {
    if (apiKey.startsWith('sk-or-vv-')) {
      return ProviderType.vsegpt;
    } else if (apiKey.startsWith('sk-or-v1-')) {
      return ProviderType.openrouter;
    } else {
      throw Exception('Неизвестный формат API ключа');
    }
  }
}
