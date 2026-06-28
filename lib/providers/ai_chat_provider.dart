import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_chat_service.dart';
import '../services/weather_service.dart';
import '../data/local_database.dart';

final aiChatServiceProvider = Provider<AiChatService>((ref) => AiChatService());

class AiChatState {
  final List<AiChatMessage> messages;
  final bool isLoading;
  final String? error;

  const AiChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  AiChatState copyWith({
    List<AiChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AiChatNotifier extends StateNotifier<AiChatState> {
  final AiChatService _service;
  final LocalDatabase _db = LocalDatabase();

  AiChatNotifier(this._service) : super(const AiChatState()) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final data = _db.get('ai_chat_history');
      if (data != null && data.isNotEmpty) {
        final list = jsonDecode(data) as List<dynamic>;
        final messages = list
            .map((e) => AiChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(messages: messages);
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      // 只保留最近50条消息
      final toSave = state.messages.length > 50
          ? state.messages.sublist(state.messages.length - 50)
          : state.messages;
      final json = jsonEncode(toSave.map((m) => m.toJson()).toList());
      _db.set('ai_chat_history', json);
    } catch (_) {}
  }

  Future<void> sendMessage(String content, {WeatherData? weather}) async {
    if (content.trim().isEmpty || state.isLoading) return;

    final userMsg = AiChatMessage(
      role: 'user',
      content: content.trim(),
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
    );

    try {
      final reply = await _service.sendMessage(state.messages, weather: weather);

      final assistantMsg = AiChatMessage(
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
      );
      _saveHistory();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '请求失败: $e',
      );
    }
  }

  Future<void> sendMessageStream(String content) async {
    if (content.trim().isEmpty || state.isLoading) return;

    final userMsg = AiChatMessage(
      role: 'user',
      content: content.trim(),
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
    );

    // 添加占位消息，后续流式更新
    final assistantMsg = AiChatMessage(
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(messages: [...state.messages, assistantMsg]);

    try {
      final stream = _service.sendMessageStream(state.messages);
      String fullReply = '';

      await for (final chunk in stream) {
        fullReply += chunk;
        final updatedMessages = [...state.messages];
        updatedMessages[updatedMessages.length - 1] = AiChatMessage(
          role: 'assistant',
          content: fullReply,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(messages: updatedMessages);
      }

      state = state.copyWith(isLoading: false);
      _saveHistory();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '请求失败: $e',
      );
    }
  }

  void clearHistory() {
    state = const AiChatState();
    _db.remove('ai_chat_history');
  }

  /// 删除最后一条AI回复，重新回答（保留上一条用户消息重新发送）
  Future<void> removeLastAndRetry({WeatherData? weather}) async {
    if (state.messages.length < 2) return;
    final messages = [...state.messages];
    // 移除最后一条AI回复
    messages.removeLast();
    final lastUserMsg = messages.last;
    if (lastUserMsg.role != 'user') return;

    state = state.copyWith(
      messages: messages,
      isLoading: true,
      error: null,
    );

    try {
      final reply = await _service.sendMessage(messages, weather: weather);
      final assistantMsg = AiChatMessage(
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
      );
      _saveHistory();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '请求失败: $e',
      );
    }
  }
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  final service = ref.read(aiChatServiceProvider);
  return AiChatNotifier(service);
});