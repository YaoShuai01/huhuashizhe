import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/services/growth_record_store.dart';

void main() {
  group('生长检测记录模型', () {
    test('JSON往返序列化完整', () {
      final record = GrowthRecord(
        id: 'session_1000',
        name: '武汉市洪山区 2026-11-07 10:30',
        locationName: '武汉市洪山区',
        timeText: '2026-11-07 10:30',
        createdAt: DateTime.parse('2026-11-07 10:30:00'),
        problems: [
          ProblemGroup(
            labelIndex: '0',
            zhName: '苹果黑星病',
            desc: '叶片出现橄榄绿至黑色斑点',
            maxConfidence: 0.87,
            hitCount: 3,
            imagePaths: ['/data/x/a.ys', '/data/x/b.ys'],
          ),
          ProblemGroup(
            labelIndex: '16',
            zhName: '柑橘黄龙病',
            desc: '叶片斑驳黄化',
            maxConfidence: 0.62,
            hitCount: 1,
            imagePaths: ['/data/x/c.ys'],
          ),
        ],
        aiPending: true,
        chat: [
          {'role': 'user', 'content': '怎么治？', 'ts': '2026-11-07T10:40:00'},
        ],
      );

      final restored = GrowthRecord.fromJson(record.toJson());
      expect(restored.id, record.id);
      expect(restored.name, record.name);
      expect(restored.timeText, record.timeText);
      expect(restored.aiPending, isTrue);
      expect(restored.problems.length, 2);
      expect(restored.problems[0].zhName, '苹果黑星病');
      expect(restored.problems[0].imagePaths.length, 2);
      expect(restored.problems[0].maxConfidence, closeTo(0.87, 1e-9));
      expect(restored.totalImages, 3);
      expect(restored.chat.length, 1);
      expect(restored.chat[0]['role'], 'user');
    });

    test('空记录默认值安全', () {
      final record = GrowthRecord.fromJson({});
      expect(record.problems, isEmpty);
      expect(record.chat, isEmpty);
      expect(record.aiPending, isFalse);
      expect(record.aiSuggestion, isNull);
    });

    test('问题描述字段缺失时兜底', () {
      final group = ProblemGroup.fromJson({});
      expect(group.zhName, '未知问题');
      expect(group.imagePaths, isEmpty);
    });
  });
}
