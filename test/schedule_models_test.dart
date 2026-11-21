import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/schedule/models/schedule_models.dart';

void main() {
  group('ScheduleDate', () {
    test('日期 key 与解析保持稳定', () {
      final date = DateTime(2026, 11, 17);
      expect(ScheduleDate.key(date), '2026-11-17');
      final parsed = ScheduleDate.tryParseKey('2026-11-17');
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 11);
      expect(parsed.day, 17);
      expect(ScheduleDate.tryParseKey('2026-02-30'), isNull);
      expect(ScheduleDate.tryParseKey('2026/11/17'), isNull);
    });

    test('月历网格按周一开头补齐', () {
      final cells = ScheduleDate.monthGrid(DateTime(2026, 11, 1));
      expect(cells.length % 7, 0);
      expect(cells.first, isNull); // 2026-11-01 是周日，前面补 6 个空
      expect(cells.whereType<DateTime>().length, 30);
    });

    test('天数差按自然日计算', () {
      expect(
        ScheduleDate.daysBetween(DateTime(2026, 11, 16), DateTime(2026, 11, 17)),
        1,
      );
    });
  });

  group('ScheduleData', () {
    final json = {
      'schemaVersion': 1,
      'revision': 3,
      'updatedAt': '2026-11-16T10:00:00.000Z',
      'updatedBy': '管理员',
      'members': [
        {'id': 'm1', 'name': '张三', 'active': true},
        {'id': 'm2', 'name': '李四', 'active': true},
      ],
      'assignments': {
        '2026-11-17': 'm1',
        '2026-11-18': 'm2',
        '2026-11-19': 'm1',
      },
      'rotation': ['m2', 'm1'],
      'changeLog': [
        {
          'at': '2026-11-16T10:00:00.000Z',
          'by': '管理员',
          'changes': [
            {'date': '2026-11-17', 'from': null, 'to': 'm1'},
          ],
        },
      ],
    };

    test('解析成员、排班和变更日志', () {
      final data = ScheduleData.fromJson(json);
      expect(data.revision, 3);
      expect(data.members.length, 2);
      expect(data.memberName('m1'), '张三');
      expect(data.memberName('m2'), '李四');
      expect(data.memberName('missing'), '未安排');
      expect(data.rotation, ['m2', 'm1']);
      expect(data.changeLog.length, 1);
      expect(data.changeLog.first.changes.first.date, '2026-11-17');
    });

    test('按成员查询日期并按今天过滤', () {
      final data = ScheduleData.fromJson(json);
      final all = data.datesForMember('m1');
      expect(all.map(ScheduleDate.key), ['2026-11-17', '2026-11-19']);
      final upcoming = data.upcomingDatesForMember(
        'm1',
        now: DateTime(2026, 11, 18),
      );
      expect(upcoming.map(ScheduleDate.key), ['2026-11-19']);
    });

    test('编码后可无损解码', () {
      final data = ScheduleData.fromJson(json);
      final decoded = ScheduleData.tryDecode(data.encode());
      expect(decoded, isNotNull);
      expect(decoded!.revision, data.revision);
      expect(decoded.assignments, data.assignments);
      expect(decoded.rotation, data.rotation);
      expect(decoded.members.length, data.members.length);
    });

    test('提交结果解析变更成员', () {
      final result = ScheduleSubmitResult.fromJson({
        'schedule': json,
        'changes': [
          {'date': '2026-11-17', 'from': 'm2', 'to': 'm1'},
        ],
        'changedMemberIds': ['m1', 'm2'],
      });
      expect(result.schedule.revision, 3);
      expect(result.changes.first.from, 'm2');
      expect(result.changedMemberIds, ['m1', 'm2']);
    });
  });
}
