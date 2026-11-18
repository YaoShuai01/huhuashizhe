import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/services/voice_service.dart';

void main() {
  group('VoiceService.condenseForSpeech', () {
    test('空文本返回空字符串', () {
      expect(VoiceService.condenseForSpeech(''), '');
      expect(VoiceService.condenseForSpeech('   \n\t  '), '');
    });

    test('短文本原样播报并压缩多余空白', () {
      expect(VoiceService.condenseForSpeech('  你好\n  世界  '), '你好 世界');
      expect(VoiceService.condenseForSpeech('检测到稻瘟病，置信度92%'),
          '检测到稻瘟病，置信度92%');
    });

    test('超长文本截断并提示查看屏幕', () {
      final long = 'x' * 200;
      final result = VoiceService.condenseForSpeech(long);
      expect(result.endsWith('……更多内容请查看屏幕'), isTrue);
      expect(result.replaceAll('……更多内容请查看屏幕', '').length, 80);
    });

    test('优先在句末标点处截断', () {
      final text = '这是一段比较长的回复内容，用于测试句末截断效果。后面还有大量内容。'
          '${'补充' * 60}';
      final result = VoiceService.condenseForSpeech(text);
      final head = result.replaceAll('……更多内容请查看屏幕', '');
      expect(head.endsWith('。'), isTrue);
      expect(head.length, lessThanOrEqualTo(80));
    });

    test('刚好达到上限时不追加提示', () {
      final exactly = 'a' * 80;
      expect(VoiceService.condenseForSpeech(exactly), exactly);
    });
  });
}
