import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/services/ys_image_store.dart';

void main() {
  final store = YsImageStore();

  group('YS加密容器 加解密往返', () {
    test('小数据往返一致', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 255, 0, 128]);
      final encrypted = store.encryptBytes(payload);
      expect(encrypted[0], 0x59); // 'Y'
      expect(encrypted[1], 0x53); // 'S'
      expect(encrypted[2], 0x01); // 版本
      final decrypted = store.decryptBytes(encrypted);
      expect(decrypted, payload);
    });

    test('大数据（模拟JPEG）往返一致', () {
      final payload = Uint8List.fromList(
        List.generate(100000, (i) => (i * 7 + 13) % 256),
      );
      final decrypted = store.decryptBytes(store.encryptBytes(payload));
      expect(decrypted, payload);
    });

    test('密文不含明文特征（简单模式校验）', () {
      final payload = Uint8List.fromList(List.filled(512, 0xAB));
      final encrypted = store.encryptBytes(payload);
      // 负载区不应有大段连续相同字节
      var run = 1;
      var maxRun = 1;
      for (var i = 13; i < encrypted.length; i++) {
        if (encrypted[i] == encrypted[i - 1]) {
          run++;
          if (run > maxRun) maxRun = run;
        } else {
          run = 1;
        }
      }
      expect(maxRun, lessThan(8));
    });

    test('魔数错误抛FormatException', () {
      final encrypted = store.encryptBytes(Uint8List.fromList([1, 2, 3]));
      encrypted[0] = 0x00;
      expect(() => store.decryptBytes(encrypted), throwsFormatException);
    });

    test('版本错误抛FormatException', () {
      final encrypted = store.encryptBytes(Uint8List.fromList([1, 2, 3]));
      encrypted[2] = 0x09;
      expect(() => store.decryptBytes(encrypted), throwsFormatException);
    });

    test('负载被截断抛FormatException', () {
      final encrypted = store.encryptBytes(Uint8List.fromList(List.filled(100, 7)));
      final truncated = Uint8List.sublistView(encrypted, 0, 50);
      expect(() => store.decryptBytes(Uint8List.fromList(truncated)),
          throwsFormatException);
    });

    test('长度校验码被篡改抛FormatException', () {
      final encrypted = store.encryptBytes(Uint8List.fromList(List.filled(100, 7)));
      encrypted[8] = encrypted[8] ^ 0xFF;
      expect(() => store.decryptBytes(encrypted), throwsFormatException);
    });
  });
}