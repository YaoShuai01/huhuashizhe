import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/model_test/pages/model_test_page.dart';

void main() {
  group('模型测试页预览尺寸', () {
    test('手机：400 宽 body，预览等比缩到留给列表的空间', () {
      final size = modelTestPreviewSize(const Size(400, 720));
      expect(size.width, closeTo(390, 0.1));
      expect(size.height, closeTo(520, 0.1));
    });

    test('平板横屏：宽 480 上限，高度给列表留 200', () {
      final size = modelTestPreviewSize(const Size(1280, 672));
      expect(size.height, closeTo(472, 0.1));
      expect(size.width, closeTo(354, 0.1));
    });

    test('平板竖屏：限宽 480、保持 3:4', () {
      final size = modelTestPreviewSize(const Size(800, 1200));
      expect(size.width, closeTo(480, 0.1));
      expect(size.height, closeTo(640, 0.1));
    });

    test('始终不超过可用宽高，且保持 3:4', () {
      const bodies = [
        Size(320, 400),
        Size(400, 720),
        Size(800, 1200),
        Size(1280, 672),
        Size(1920, 900),
      ];
      for (final body in bodies) {
        final size = modelTestPreviewSize(body);
        expect(size.width, lessThanOrEqualTo(body.width + 0.01));
        expect(size.height, lessThanOrEqualTo(body.height + 0.01));
        expect(size.width / size.height, closeTo(0.75, 0.001));
      }
    });
  });
}
