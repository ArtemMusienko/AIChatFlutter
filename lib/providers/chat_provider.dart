// Импорт библиотеки для работы с JSON
import 'dart:convert';
// Импорт библиотеки для работы с файловой системой
import 'dart:io';
// Импорт основных классов Flutter
import 'package:flutter/foundation.dart';
// Импорт пакета для получения путей к директориям
import 'package:path_provider/path_provider.dart';
// Импорт модели сообщения
import '../models/message.dart';
// Импорт клиента для работы с API
import '../api/openrouter_client.dart';
// Импорт сервиса для работы с базой данных
import '../services/database_service.dart';
// Импорт сервиса для аналитики
import '../services/analytics_service.dart';

// Основной класс провайдера для управления состоянием чата
class ChatProvider with ChangeNotifier {
  // Клиент для работы с API
  final OpenRouterClient _api = OpenRouterClient();
  // Список сообщений чата
  final List<ChatMessage> _messages = [];
  // Логи для отладки
  final List<String> _debugLogs = [];
  // Список доступных моделей
  List<Map<String, dynamic>> _availableModels = [];
  // Текущая выбранная модель
  String? _currentModel;
  // Баланс пользователя
  String _balance = '\$0.00';
  // Флаг загрузки
  bool _isLoading = false;

  // Метод для логирования сообщений
  void _log(String message) {
    // Добавление сообщения в логи с временной меткой
    _debugLogs.add('${DateTime.now()}: $message');
    // Вывод сообщения в консоль
    debugPrint(message);
  }

  // Геттер для получения неизменяемого списка сообщений
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  // Геттер для получения списка доступных моделей
  List<Map<String, dynamic>> get availableModels => _availableModels;
  // Геттер для получения текущей модели
  String? get currentModel => _currentModel;
  // Геттер для получения баланса
  String get balance => _balance;
  // Геттер для получения состояния загрузки
  bool get isLoading => _isLoading;

  // Конструктор провайдера
  ChatProvider() {
    // Инициализация провайдера
    _initializeProvider();
  }

  // Метод инициализации провайдера
  Future<void> _initializeProvider() async {
    try {
      // Логирование начала инициализации
      _log('Initializing provider...');
      // Загрузка доступных моделей
      await _loadModels();
      _log('Models loaded: $_availableModels');
      // Загрузка баланса
      await _loadBalance();
      _log('Balance loaded: $_balance');
      // Загрузка истории сообщений
      await _loadHistory();
      _log('History loaded: ${_messages.length} messages');
    } catch (e, stackTrace) {
      // Логирование ошибок инициализации
      _log('Error initializing provider: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  // Метод загрузки доступных моделей
  Future<void> _loadModels() async {
    try {
      // Получение списка моделей из API
      _availableModels = await _api.getModels();
      // Сортировка моделей по имени по возрастанию
      _availableModels
          .sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      // Установка модели по умолчанию, если она не выбрана
      if (_availableModels.isNotEmpty && _currentModel == null) {
        _currentModel = _availableModels[0]['id'];
      }
      // Уведомление слушателей об изменениях
      notifyListeners();
    } catch (e) {
      // Логирование ошибок загрузки моделей
      _log('Error loading models: $e');
    }
  }

  // Метод загрузки баланса пользователя
  Future<void> _loadBalance() async {
    try {
      // Получение баланса из API
      _balance = await _api.getBalance();
      // Уведомление слушателей об изменениях
      notifyListeners();
    } catch (e) {
      // Логирование ошибок загрузки баланса
      _log('Error loading balance: $e');
    }
  }

  // Сервис для работы с базой данных
  final DatabaseService _db = DatabaseService();
  // Сервис для сбора аналитики
  final AnalyticsService _analytics = AnalyticsService();

  // Метод загрузки истории сообщений
  Future<void> _loadHistory() async {
    try {
      // Получение сообщений из базы данных
      final messages = await _db.getMessages();
      // Очистка текущего списка и добавление новых сообщений
      _messages.clear();
      _messages.addAll(messages);
      // Уведомление слушателей об изменениях
      notifyListeners();
    } catch (e) {
      // Логирование ошибок загрузки истории
      _log('Error loading history: $e');
    }
  }

  // Метод сохранения сообщения в базу данных
  Future<void> _saveMessage(ChatMessage message) async {
    try {
      // Сохранение сообщения в базу данных
      await _db.saveMessage(message);
    } catch (e) {
      // Логирование ошибок сохранения сообщения
      _log('Error saving message: $e');
    }
  }

  // Метод отправки сообщения
  Future<void> sendMessage(String content, {bool trackAnalytics = true}) async {
    // Проверка на пустое сообщение или отсутствие модели
    if (content.trim().isEmpty || _currentModel == null) return;

    // Установка флага загрузки
    _isLoading = true;
    // Уведомление слушателей об изменениях
    notifyListeners();

    try {
      // Обеспечение правильного кодирования сообщения
      content = utf8.decode(utf8.encode(content));

      // Добавление сообщения пользователя
      final userMessage = ChatMessage(
        content: content,
        isUser: true,
        modelId: _currentModel,
      );
      _messages.add(userMessage);
      // Уведомление слушателей об изменениях
      notifyListeners();

      // Сохранение сообщения пользователя
      await _saveMessage(userMessage);

      // Запись времени начала отправки
      final startTime = DateTime.now();

      // Отправка сообщения в API
      final response = await _api.sendMessage(content, _currentModel!);
      // Логирование ответа API
      _log('API Response: $response');

      // Расчет времени ответа
      final responseTime =
          DateTime.now().difference(startTime).inMilliseconds / 1000;

      if (response.containsKey('error')) {
        // Добавление сообщения об ошибке
        final errorMessage = ChatMessage(
          content: utf8.decode(utf8.encode('Error: ${response['error']}')),
          isUser: false,
          modelId: _currentModel,
        );
        _messages.add(errorMessage);
        await _saveMessage(errorMessage);
      } else if (response.containsKey('choices') &&
          response['choices'] is List &&
          response['choices'].isNotEmpty &&
          response['choices'][0] is Map &&
          response['choices'][0].containsKey('message') &&
          response['choices'][0]['message'] is Map &&
          response['choices'][0]['message'].containsKey('content')) {
        // Добавление ответа AI
        final aiContent = utf8.decode(utf8.encode(
          response['choices'][0]['message']['content'] as String,
        ));
        // Получение количества использованных токенов
        final tokens = response['usage']?['total_tokens'] as int? ?? 0;

        // Трекинг аналитики, если включен
        if (trackAnalytics) {
          _analytics.trackMessage(
            model: _currentModel!,
            messageLength: content.length,
            responseTime: responseTime,
            tokensUsed: tokens,
          );
        }

        // Создание и добавление сообщения AI
        // Получение количества токенов из ответа
        final promptTokens = response['usage']['prompt_tokens'] ?? 0;
        final completionTokens = response['usage']['completion_tokens'] ?? 0;

        final totalCost = response['usage']?['total_cost'];

        // Получение тарифов для текущей модели
        final model = _availableModels
            .firstWhere((model) => model['id'] == _currentModel);

        // Расчет стоимости запроса
        final cost = (totalCost == null)
            ? ((promptTokens *
                    (double.tryParse(model['pricing']?['prompt']) ?? 0)) +
                (completionTokens *
                    (double.tryParse(model['pricing']?['completion']) ?? 0)))
            : totalCost;

        // Логирование ответа API
        _log('Cost Response: $cost');

        final aiMessage = ChatMessage(
          content: aiContent,
          isUser: false,
          modelId: _currentModel,
          tokens: tokens,
          cost: cost,
        );
        _messages.add(aiMessage);
        // Сохранение сообщения AI
        await _saveMessage(aiMessage);

        // Обновление баланса после успешного сообщения
        await _loadBalance();
      } else {
        throw Exception('Invalid API response format');
      }
    } catch (e) {
      // Логирование ошибок отправки сообщения
      _log('Error sending message: $e');
      // Добавление сообщения об ошибке
      final errorMessage = ChatMessage(
        content: utf8.decode(utf8.encode('Error: $e')),
        isUser: false,
        modelId: _currentModel,
      );
      _messages.add(errorMessage);
      // Сохранение сообщения об ошибке
      await _saveMessage(errorMessage);
    } finally {
      // Сброс флага загрузки
      _isLoading = false;
      // Уведомление слушателей об изменениях
      notifyListeners();
    }
  }

  // Метод установки текущей модели
  void setCurrentModel(String modelId) {
    // Установка новой модели
    _currentModel = modelId;
    // Уведомление слушателей об изменениях
    notifyListeners();
  }

  // Метод очистки истории
  Future<void> clearHistory() async {
    // Очистка списка сообщений
    _messages.clear();
    // Очистка истории в базе данных
    await _db.clearHistory();
    // Очистка данных аналитики
    _analytics.clearData();
    // Уведомление слушателей об изменениях
    notifyListeners();
  }

  // Метод экспорта логов
  Future<String> exportLogs() async {
    // Получение директории для сохранения файла
    final directory = await getApplicationDocumentsDirectory();
    // Генерация имени файла с текущей датой и временем
    final now = DateTime.now();
    final fileName =
        'chat_logs_${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.txt';
    // Создание файла
    final file = File('${directory.path}/$fileName');

    // Создание буфера для записи логов
    final buffer = StringBuffer();
    buffer.writeln('=== Debug Logs ===\n');
    // Запись всех логов
    for (final log in _debugLogs) {
      buffer.writeln(log);
    }

    buffer.writeln('\n=== Chat Logs ===\n');
    // Запись времени генерации
    buffer.writeln('Generated: ${now.toString()}\n');

    // Запись всех сообщений
    for (final message in _messages) {
      buffer.writeln('${message.isUser ? "User" : "AI"} (${message.modelId}):');
      buffer.writeln(message.content);
      // Запись количества токенов, если есть
      if (message.tokens != null) {
        buffer.writeln('Tokens: ${message.tokens}');
      }
      // Запись времени сообщения
      buffer.writeln('Time: ${message.timestamp}');
      buffer.writeln('---\n');
    }

    // Запись содержимого в файл
    await file.writeAsString(buffer.toString());
    // Возвращение пути к файлу
    return file.path;
  }

  // Метод экспорта сообщений в формате JSON
  Future<String> exportMessagesAsJson() async {
    // Получение директории для сохранения файла
    final directory = await getApplicationDocumentsDirectory();
    // Генерация имени файла с текущей датой и временем
    final now = DateTime.now();
    final fileName =
        'chat_history_${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.json';
    // Создание файла
    final file = File('${directory.path}/$fileName');

    // Преобразование сообщений в JSON
    final List<Map<String, dynamic>> messagesJson =
        _messages.map((message) => message.toJson()).toList();

    // Запись JSON в файл
    await file.writeAsString(jsonEncode(messagesJson));
    // Возвращение пути к файлу
    return file.path;
  }

  Future<String> formatPricing(double pricing) async {
    return await _api.formatPricing(pricing);
  }

  // Метод экспорта истории
  Future<Map<String, dynamic>> exportHistory() async {
    // Получение статистики из базы данных
    final dbStats = await _db.getStatistics();
    // Получение статистики аналитики
    final analyticsStats = _analytics.getStatistics();
    // Получение данных сессий
    final sessionData = _analytics.exportSessionData();
    // Получение эффективности моделей
    final modelEfficiency = _analytics.getModelEfficiency();
    // Получение статистики времени ответа
    final responseTimeStats = _analytics.getResponseTimeStats();
    // Получение статистики длины сообщений
    final messageLengthStats = _analytics.getMessageLengthStats();

    // Возвращение всех данных в виде Map
    return {
      'database_stats': dbStats,
      'analytics_stats': analyticsStats,
      'session_data': sessionData,
      'model_efficiency': modelEfficiency,
      'response_time_stats': responseTimeStats,
      'message_length_stats': messageLengthStats,
    };
  }
}
