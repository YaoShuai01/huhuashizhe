import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/model_test/data/model_labels.dart';

void main() {
  group('模型标签表', () {
    test('类别数量为39（与TFLite模型输出维度一致）', () {
      expect(kModelLabels.length, 39);
    });

    test('每个标签都有中文名与描述', () {
      for (final label in kModelLabels) {
        expect(label.zh.isNotEmpty, isTrue, reason: label.en);
        expect(label.desc.isNotEmpty, isTrue, reason: label.en);
      }
    });

    test('中文名不重复', () {
      final names = kModelLabels.map((l) => l.zh).toSet();
      expect(names.length, kModelLabels.length);
    });

    test('isProblemClass 健康类不预警、问题类预警', () {
      final healthyIndexes = <int>[];
      for (var i = 0; i < kModelLabels.length; i++) {
        if (kModelLabels[i].healthy) healthyIndexes.add(i);
      }
      expect(healthyIndexes.contains(3), isTrue); // Apple healthy
      expect(healthyIndexes.contains(31), isTrue); // Tomato healthy
      expect(isProblemClass(0), isTrue); // Apple scab
      expect(isProblemClass(16), isTrue); // 柑橘黄龙病
      for (final h in healthyIndexes) {
        expect(isProblemClass(h), isFalse, reason: kModelLabels[h].zh);
      }
    });

    test('越界索引安全', () {
      expect(isProblemClass(-1), isFalse);
      expect(isProblemClass(39), isFalse);
      expect(zhLabelOf(-1), '未知');
      expect(zhLabelOf(39), '未知');
    });
  });
}
