import 'package:flutter_test/flutter_test.dart';
import 'package:yibianhui_blog/src/data/update_checker.dart';

void main() {
  group('parseVersion', () {
    test('解析标准 0.0.X 格式', () {
      expect(UpdateChecker.parseVersion('0.0.5'), (0, 0, 5));
      expect(UpdateChecker.parseVersion('0.0.1'), (0, 0, 1));
      expect(UpdateChecker.parseVersion('1.2.3'), (1, 2, 3));
      expect(UpdateChecker.parseVersion('0.0'), (0, 0, 0));
    });

    test('拒绝非法格式', () {
      expect(UpdateChecker.parseVersion(''), isNull);
      expect(UpdateChecker.parseVersion('a.b.c'), isNull);
      expect(UpdateChecker.parseVersion('0.0.5.1'), isNull);
      expect(UpdateChecker.parseVersion('0.-1.2'), isNull);
    });
  });

  group('isNewerVersion', () {
    test('小改动递增判定', () {
      expect(UpdateChecker.isNewerVersion('0.0.5', '0.0.6'), isTrue);
      expect(UpdateChecker.isNewerVersion('0.0.5', '0.0.5'), isFalse);
      expect(UpdateChecker.isNewerVersion('0.0.6', '0.0.5'), isFalse);
      expect(UpdateChecker.isNewerVersion('0.0.5', '0.1.0'), isTrue);
      expect(UpdateChecker.isNewerVersion('0.9.9', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewerVersion('0.0.1', '0.0.1'), isFalse);
    });
  });
}