import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'ai_chat_service.dart';
import 'growth_record_store.dart';

/// 生长检测 AI 建议服务
///
/// - 测试结束同步记录时立即生成AI建议
/// - 无网络时标记 aiPending 暂存，网络恢复后第一时间自动补全
/// - 支持对单条记录的追问对话（历史永久保留在记录中）
class AiSuggestionWorker {
  static final AiSuggestionWorker _instance = AiSuggestionWorker._();
  factory AiSuggestionWorker() => _instance;
  AiSuggestionWorker._();

  final GrowthRecordStore _store = GrowthRecordStore();
  final AiChatService _ai = AiChatService();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final Set<String> _processing = {};
  bool _started = false;

  /// 启动监听（App启动时调用一次）：
  /// 立即补全存量待生成记录，并监听网络恢复事件
  void start() {
    if (_started) return;
    _started = true;
    processPending();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      if (connected) {
        debugPrint('[AiWorker] 网络恢复，自动补全AI建议');
        processPending();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _started = false;
  }

  /// 为记录生成AI建议（失败则标记aiPending等待补全）
  Future<bool> generateFor(String recordId) async {
    if (_processing.contains(recordId)) return false;
    _processing.add(recordId);
    try {
      final record = _store.getById(recordId);
      if (record == null) return false;
      if (record.aiSuggestion != null && record.aiSuggestion!.isNotEmpty) {
        return true; // 已有建议，跳过
      }
      final suggestion = await _buildSuggestion(record);
      final hasResult = suggestion.isNotEmpty &&
          !suggestion.contains('网络连接出现问题');
      if (hasResult) {
        record.aiSuggestion = AiChatService.stripMarkdown(suggestion);
        record.aiPending = false;
        _store.update(record);
        return true;
      } else {
        record.aiPending = true;
        _store.update(record);
        return false;
      }
    } catch (e) {
      debugPrint('[AiWorker] 生成AI建议失败: $e');
      final record = _store.getById(recordId);
      if (record != null) {
        record.aiPending = true;
        _store.update(record);
      }
      return false;
    } finally {
      _processing.remove(recordId);
    }
  }

  /// 补全所有待生成记录
  Future<void> processPending() async {
    final pending = _store.pendingAiRecords();
    for (final r in pending) {
      await generateFor(r.id);
    }
  }

  /// 追问对话（流式输出），完整写入记录历史
  Stream<String> askFollowUp(String recordId, String question) async* {
    final record = _store.getById(recordId);
    if (record == null) {
      yield '记录不存在';
      return;
    }
    final history = <AiChatMessage>[];
    // 系统上下文作为首条user消息注入
    history.add(AiChatMessage(
      role: 'user',
      content: _recordContext(record),
      timestamp: record.createdAt,
    ));
    history.add(AiChatMessage(
      role: 'assistant',
      content: '已了解该生长检测记录，请继续提问。',
      timestamp: record.createdAt,
    ));
    for (final c in record.chat) {
      history.add(AiChatMessage(
        role: c['role']?.toString() ?? 'user',
        content: c['content']?.toString() ?? '',
        timestamp:
            DateTime.tryParse(c['ts']?.toString() ?? '') ?? DateTime.now(),
      ));
    }
    history.add(AiChatMessage(
      role: 'user',
      content: question,
      timestamp: DateTime.now(),
    ));

    final replyBuffer = StringBuffer();
    await for (final chunk in _ai.sendMessageStream(history)) {
      replyBuffer.write(chunk);
      yield chunk;
    }
    // 持久化本轮对话（回复去除Markdown标记）
    final fresh = _store.getById(recordId);
    if (fresh != null) {
      fresh.chat.add({
        'role': 'user',
        'content': question,
        'ts': DateTime.now().toIso8601String(),
      });
      fresh.chat.add({
        'role': 'assistant',
        'content': AiChatService.stripMarkdown(replyBuffer.toString()),
        'ts': DateTime.now().toIso8601String(),
      });
      _store.update(fresh);
    }
  }

  Future<String> _buildSuggestion(GrowthRecord record) async {
    final String problems;
    if (record.problems.isEmpty) {
      problems = '- 本次未识别到作物问题，生长状况良好。';
    } else {
      problems = record.problems
          .map((p) => '- ${p.zhName}（识别${p.hitCount}次，最高置信度${(p.maxConfidence * 100).toStringAsFixed(0)}%）：${p.desc}')
          .join('\n');
    }
    final prompt = '本次生长检测（地区：${record.locationName}，时间：${record.timeText}）'
        '通过AI视觉模型识别到以下作物问题：\n$problems\n'
        '请给出针对这些问题的综合处理建议，包括：推荐农药与配比、喷洒作业要点（飞行高度/速度/亩用量）、'
        '安全间隔期提醒。控制在300字以内，结尾注明"请以当地农技部门指导为准"。';
    return await _ai.quickAnalysis(prompt);
  }

  String _recordContext(GrowthRecord record) {
    final problems = record.problems
        .map((p) => '- ${p.zhName}：${p.desc}')
        .join('\n');
    return '以下是本次生长检测记录（地区：${record.locationName}，时间：${record.timeText}）\n'
        '识别到的问题：\n${problems.isEmpty ? "未识别到问题，生长状况良好" : problems}\n'
        '${record.aiSuggestion != null ? "\n已有的AI处理建议：\n${record.aiSuggestion}" : ""}\n'
        '后续用户会针对这条记录继续提问，请结合以上背景回答。';
  }
}
