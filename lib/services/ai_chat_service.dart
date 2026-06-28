import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AiChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  const AiChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// 小米MiMo大模型AI对话服务（OpenAI兼容格式）
class AiChatService {
  static const _baseUrl = 'https://api.xiaomimimo.com/v1';
  static const _model = 'mimo-v2-flash';
  static const _apiKey = 'sk-cmg9hlk0p32xk3zvwlx3q1ui4q4b5qql3qua554jfl5lshef';

  /// 护花使者智能体系统提示词
  static const _systemPrompt = '''
你是"护花使者"智能植保助手，专门为植保无人机飞手提供专业建议。

你的身份定位：
- 你是植保无人机领域的AI专家，精通农药喷洒、病虫害防治、飞行作业规划
- 你的语气专业但亲切，像一位经验丰富的老师傅指导新手
- 你了解以下作物：水稻、小麦、玉米、棉花、果树、蔬菜、茶叶、油菜等
- 你熟悉农药知识：杀虫剂、杀菌剂、除草剂、植物生长调节剂的使用方法

你的核心能力：
1. 病虫害诊断：根据用户描述的作物症状，推荐防治方案
2. 用药建议：推荐农药种类、配比浓度、喷洒量（升/亩）
3. 飞行参数：推荐飞行高度、速度、行距、喷幅
4. 安全提醒：强调安全间隔期、农药混用禁忌、防护措施
5. 作业规划：根据地块面积估算作业时间和药剂用量

回答规则：
- 每次回答控制在200字以内，简洁专业
- 涉及到具体用药时，必须提醒"请以当地农技部门指导为准"
- 如果用户问无关问题，引导回植保话题
- 使用中文回答，适当使用专业术语但需解释
''';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'api-key': _apiKey,
      'Content-Type': 'application/json',
    },
  ));

  /// 发送消息并获取AI回复（流式输出）
  Stream<String> sendMessageStream(List<AiChatMessage> history) async* {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
    ];

    // 只保留最近20轮对话（40条消息），避免超出上下文
    final recentHistory = history.length > 40 ? history.sublist(history.length - 40) : history;
    for (final msg in recentHistory) {
      messages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': messages,
          'max_tokens': 512,
          'temperature': 0.7,
          'top_p': 0.95,
          'stream': true,
          'extra_body': {'thinking': {'type': 'disabled'}},
        },
        options: Options(
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final chunk in stream) {
        final text = utf8.decode(chunk);
        buffer += text;

        // 解析SSE格式: data: {...}\n\n
        while (buffer.contains('\n\n')) {
          final index = buffer.indexOf('\n\n');
          final line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 2);

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') return;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            } catch (_) {
              // 跳过无法解析的chunk
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AI] 流式请求异常: $e');
      yield '抱歉，网络连接出现问题，请稍后再试。';
    }
  }

  /// 发送消息并获取AI回复（非流式，备用）
  Future<String> sendMessage(List<AiChatMessage> history) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
    ];

    final recentHistory = history.length > 40 ? history.sublist(history.length - 40) : history;
    for (final msg in recentHistory) {
      messages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': messages,
          'max_tokens': 512,
          'temperature': 0.7,
          'top_p': 0.95,
          'stream': false,
          'extra_body': {'thinking': {'type': 'disabled'}},
        },
      );

      final choices = response.data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>?;
        return message?['content']?.toString() ?? '抱歉，未能获取回复。';
      }
      return '抱歉，AI暂时无法回复，请稍后再试。';
    } catch (e) {
      debugPrint('[AI] 请求异常: $e');
      return '网络连接出现问题，请检查网络后重试。';
    }
  }

  /// 一次性AI分析（供其他模块调用，如飞行参数分析、病虫害诊断等）
  /// [prompt] 分析提示词，[context] 可选的上下文信息
  Future<String> quickAnalysis(String prompt, {String? context}) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
    ];

    final userContent = context != null ? '$prompt\n\n相关上下文：$context' : prompt;
    messages.add({'role': 'user', 'content': userContent});

    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': messages,
          'max_tokens': 512,
          'temperature': 0.7,
          'top_p': 0.95,
          'stream': false,
          'extra_body': {'thinking': {'type': 'disabled'}},
        },
      );

      final choices = response.data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>?;
        return message?['content']?.toString() ?? '抱歉，未能获取分析结果。';
      }
      return '抱歉，AI暂时无法分析，请稍后再试。';
    } catch (e) {
      debugPrint('[AI] 分析请求异常: $e');
      return '网络连接出现问题，请检查网络后重试。';
    }
  }
}