import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/server_config.dart';

/// AI 初审结论
enum ForumAuditVerdict {
  /// 审核通过
  pass,

  /// 直接驳回
  reject,

  /// 待人工复审
  manualReview,
}

/// 单次初审结果
class ForumAuditResult {
  const ForumAuditResult({
    required this.verdict,
    required this.reason,
    this.violationType = '无',
  });

  final ForumAuditVerdict verdict;
  final String reason;
  final String violationType;

  bool get rejected => verdict == ForumAuditVerdict.reject;
  bool get needsManualReview => verdict == ForumAuditVerdict.manualReview;
}

/// 内容初审接口，外部可实现为服务端审核或第三方风控
abstract class ForumModerationService {
  /// 对发帖/评论文本做合规初审，[extraText] 可传入图片 OCR 文字、水印文字等
  Future<ForumAuditResult> review({
    required String title,
    String content = '',
    String extraText = '',
  });
}

/// 解析 AI 返回的固定 JSON，无法识别时一律转人工复审（不直接放行）
ForumAuditResult parseModerationResponse(String raw) {
  try {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('no json');
    final json = jsonDecode(raw.substring(start, end + 1));
    if (json is! Map) throw const FormatException('not object');

    final result = json['audit_result']?.toString().trim() ?? '';
    final reason = json['reason']?.toString().trim() ?? '';
    final type = json['violation_type']?.toString().trim() ?? '';

    final ForumAuditVerdict verdict;
    if (result.contains('驳回')) {
      verdict = ForumAuditVerdict.reject;
    } else if (result.contains('通过')) {
      verdict = ForumAuditVerdict.pass;
    } else {
      verdict = ForumAuditVerdict.manualReview;
    }

    return ForumAuditResult(
      verdict: verdict,
      reason: reason.isEmpty ? 'AI 未给出原因' : reason,
      violationType: type.isEmpty ? '无' : type,
    );
  } catch (e) {
    debugPrint('[ForumAudit] 审核结果解析失败: $e');
    return const ForumAuditResult(
      verdict: ForumAuditVerdict.manualReview,
      reason: '审核结果无法解析，已转人工复审',
      violationType: '其他违规',
    );
  }
}

/// 基于千问大模型的社区内容初审（经自有服务器代理，App 内不含密钥）
class AiForumModerationService implements ForumModerationService {
  AiForumModerationService({Dio? dio}) : _dio = dio ?? _createDio();

  static const String systemPrompt = '''
# 角色：社区帖子AI初审审核员
任务：对用户发帖文本（包含图片OCR识别出来的文字、标题、正文、评论、水印文字）进行合规初审，仅做初审，AI不替代人工终审。

审核判定标准：
【直接驳回】
1. 危害国家安全、国家统一、损害国家形象，歪曲诋毁英雄烈士、涉邪教、恐怖主义；
2. 色情、软色情、性暗示、血腥暴力、凶杀、毒品、赌博、管制器具、传授违法犯罪方法；
3. 辱骂诽谤、网暴、公开他人手机号、住址、身份证等隐私信息；
4. 虚假造谣、恶意带节奏、制造对立，蹭灾难热点；
5. 引流导流：包含微信、QQ、群号、电话、二维码、外部网址、引导私聊加好友；
6. 灰产广告：刷单、跑分、非法借贷、代办证件、无证医美、无资质医疗科普、荐股理财；
7. 刻意绕过审核：拆分敏感词、特殊符号、谐音、拼音、黑话、图片藏违规文字；
8. 宣扬自残自杀、危险行为、校园欺凌、拜金炫恶、低俗擦边内容。

【待人工复审】
内容边界模糊、无法直接判定、有争议、专业类内容，AI无法确认真伪的，全部标记待人工复审，不直接放行。

【审核通过】
内容正常，无违规、无导流、无不良导向。

要求：
1. 严格遵守规则，不宽松；
2. 输出固定JSON格式，不要多余解释、闲聊；
3. 理由精简，违规类型从上面分类里选择；
4. AI只负责初审，所有高风险内容一律交给人工。

固定输出JSON模板：
{
    "audit_result": "通过/驳回/待人工复审",
    "reason": "简要说明",
    "violation_type": "无/涉政/色情暴力/隐私泄露/导流营销/虚假信息/规避审核/其他违规"
}
''';

  static Dio _createDio() => Dio(
        BaseOptions(
          baseUrl: '$serverBaseUrl/schedule/ai',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 60),
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

  final Dio _dio;

  @override
  Future<ForumAuditResult> review({
    required String title,
    String content = '',
    String extraText = '',
  }) async {
    final buffer = StringBuffer()
      ..writeln('待审核内容：')
      ..writeln('标题：$title')
      ..writeln('正文：$content');
    if (extraText.trim().isNotEmpty) {
      buffer.writeln('图片OCR/水印文字：${extraText.trim()}');
    }

    try {
      final response = await _dio.post(
        '/chat',
        data: {
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': buffer.toString()},
          ],
          'max_tokens': 512,
          'temperature': 0.1,
          'stream': false,
        },
      );

      final choices = response.data['choices'] as List<dynamic>?;
      final message = choices?.isNotEmpty == true
          ? choices!.first['message'] as Map<String, dynamic>?
          : null;
      final text = message?['content']?.toString() ??
          message?['reasoning_content']?.toString() ??
          '';
      if (text.trim().isEmpty) {
        return const ForumAuditResult(
          verdict: ForumAuditVerdict.manualReview,
          reason: '审核服务未返回结果，已转人工复审',
          violationType: '其他违规',
        );
      }
      return parseModerationResponse(text);
    } catch (e) {
      debugPrint('[ForumAudit] 审核请求异常: $e');
      return const ForumAuditResult(
        verdict: ForumAuditVerdict.manualReview,
        reason: '审核服务暂不可用，已转人工复审',
        violationType: '其他违规',
      );
    }
  }
}

/// 默认审核实现，页面可通过构造参数注入替身
final ForumModerationService defaultForumModerationService =
    AiForumModerationService();
