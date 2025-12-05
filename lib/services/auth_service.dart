// Импорт библиотеки для HTTP запросов
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/auth_data.dart';
import 'database_service.dart';

// Сервис аутентификации
class AuthService {
  // Единственный экземпляр класса (Singleton)
  static final AuthService _instance = AuthService._internal();

  // Кэшированные данные аутентификации
  AuthData? _cachedAuthData;

  // Фабричный метод для получения экземпляра
  factory AuthService() {
    return _instance;
  }

  // Приватный конструктор для реализации Singleton
  AuthService._internal();

  // Проверка наличия сохраненной аутентификации
  Future<bool> hasStoredAuth() async {
    final authData = await DatabaseService().getAuthData();
    return authData != null;
  }

  // Получение сохраненных данных аутентификации
  Future<AuthData?> getAuthData() async {
    if (_cachedAuthData != null) {
      return _cachedAuthData;
    }
    _cachedAuthData = await DatabaseService().getAuthData();
    return _cachedAuthData;
  }

  // Проверка API ключа и получение баланса
  Future<Map<String, dynamic>> validateApiKey(String apiKey) async {
    try {
      // Определение типа провайдера по ключу
      final providerType = ProviderTypeExtension.fromApiKey(apiKey);
      final baseUrl = providerType.baseUrl;

      // Заголовки для запроса
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

      // Запрос баланса в зависимости от провайдера
      String endpoint;
      if (providerType == ProviderType.vsegpt) {
        // Для VseGPT используем стандартный endpoint согласно документации
        endpoint = '$baseUrl/balance';
      } else {
        endpoint = '$baseUrl/credits';
      }

      final response = await http.get(
        Uri.parse(endpoint),
        headers: headers,
      );

      if (kDebugMode) {
        print('Validate API key response: ${response.statusCode}');
        print('Response body: ${response.body}');
        print('Endpoint used: $endpoint');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Парсинг баланса
        double balance = 0.0;
        String formattedBalance = '';

        if (providerType == ProviderType.vsegpt) {
          // VSEGPT возвращает баланс в рублях
          // Пробуем разные возможные структуры ответа
          if (data['balance'] != null) {
            balance = double.tryParse(data['balance'].toString()) ?? 0.0;
          } else if (data['data'] != null && data['data']['balance'] != null) {
            balance =
                double.tryParse(data['data']['balance'].toString()) ?? 0.0;
          } else if (data['data'] != null && data['data']['credits'] != null) {
            balance =
                double.tryParse(data['data']['credits'].toString()) ?? 0.0;
          } else if (data['credits'] != null) {
            balance = double.tryParse(data['credits'].toString()) ?? 0.0;
          }

          formattedBalance = '${balance.toStringAsFixed(2)}₽';

          if (kDebugMode) {
            print('VseGPT balance parsed: $balance');
          }
        } else {
          // OpenRouter возвращает credits и usage
          if (data['data'] != null) {
            final totalCredits = data['data']['total_credits'] ?? 0.0;
            final totalUsage = data['data']['total_usage'] ?? 0.0;
            balance = totalCredits - totalUsage;
            formattedBalance = '\$${balance.toStringAsFixed(2)}';
          }
        }

        // Проверка положительного баланса
        if (balance <= 0) {
          return {
            'success': false,
            'error': 'На счете недостаточно средств. Баланс: $formattedBalance',
          };
        }

        return {
          'success': true,
          'balance': formattedBalance,
          'providerType': providerType,
        };
      } else {
        final errorBody = response.body;
        if (kDebugMode) {
          print('Error response: $errorBody');
        }

        return {
          'success': false,
          'error':
              'Неверный API ключ или ошибка сервера (${response.statusCode})',
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error validating API key: $e');
      }
      return {
        'success': false,
        'error': 'Ошибка при проверке ключа: ${e.toString()}',
      };
    }
  }

  // Генерация 4-значного PIN-кода
  String _generatePin() {
    final random = Random.secure();
    // Генерация случайного числа от 1000 до 9999
    final pin = 1000 + random.nextInt(9000);
    return pin.toString();
  }

  // Регистрация нового API ключа
  Future<Map<String, dynamic>> registerApiKey(String apiKey) async {
    try {
      // Валидация ключа и проверка баланса
      final validation = await validateApiKey(apiKey);

      if (!validation['success']) {
        return validation;
      }

      // Генерация PIN-кода
      final pin = _generatePin();

      // Создание объекта AuthData
      final authData = AuthData(
        apiKey: apiKey,
        pin: pin,
        providerType: validation['providerType'] as ProviderType,
        lastBalance: validation['balance'] as String,
        lastChecked: DateTime.now(),
      );

      // Сохранение в базу данных
      await DatabaseService().saveAuthData(authData);
      _cachedAuthData = authData;

      return {
        'success': true,
        'pin': pin,
        'balance': validation['balance'],
        'providerType': validation['providerType'],
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error registering API key: $e');
      }
      return {
        'success': false,
        'error': 'Ошибка при регистрации ключа: ${e.toString()}',
      };
    }
  }

  // Проверка PIN-кода
  Future<bool> validatePin(String enteredPin) async {
    final authData = await getAuthData();
    if (authData == null) {
      return false;
    }
    return authData.pin == enteredPin;
  }

  // Сброс аутентификации (удаление ключа)
  Future<void> resetAuth() async {
    await DatabaseService().deleteAuthData();
    _cachedAuthData = null;
  }

  // Обновление баланса
  Future<String?> updateBalance() async {
    try {
      final authData = await getAuthData();
      if (authData == null) {
        return null;
      }

      // Проверяем баланс через API
      final validation = await validateApiKey(authData.apiKey);
      if (validation['success']) {
        final newBalance = validation['balance'] as String;

        // Обновляем данные в БД
        final updatedAuthData = authData.copyWith(
          lastBalance: newBalance,
          lastChecked: DateTime.now(),
        );

        await DatabaseService().saveAuthData(updatedAuthData);
        _cachedAuthData = updatedAuthData;

        return newBalance;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating balance: $e');
      }
      return null;
    }
  }

  // Получение заголовков для API запросов
  Future<Map<String, String>?> getApiHeaders() async {
    final authData = await getAuthData();
    if (authData == null) {
      return null;
    }

    return {
      'Authorization': 'Bearer ${authData.apiKey}',
      'Content-Type': 'application/json',
      'X-Title': 'AI Chat Flutter',
    };
  }

  // Получение базового URL для текущего провайдера
  Future<String?> getBaseUrl() async {
    final authData = await getAuthData();
    if (authData == null) {
      return null;
    }
    return authData.providerType.baseUrl;
  }
}
