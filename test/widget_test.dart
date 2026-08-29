import 'package:flutter_test/flutter_test.dart';
import 'package:yibianhui_blog/src/app_config.dart';

void main() {
  test('站点配置指向义编会博客', () {
    expect(AppConfig.blogUrl, 'https://www.yibianhui.cn');
    expect(AppConfig.isInAppUrl('https://www.yibianhui.cn/hello'), isTrue);
    expect(AppConfig.isInAppUrl('https://blog.yibianhui.cn/x'), isTrue);
    expect(AppConfig.isInAppUrl('https://example.com'), isFalse);
    expect(AppConfig.isInAppUrl('mailto:a@b.com'), isFalse);
  });
}
