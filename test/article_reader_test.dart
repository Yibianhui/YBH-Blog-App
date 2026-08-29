import 'package:flutter_test/flutter_test.dart';
import 'package:yibianhui_blog/src/ui/article_reader_view.dart';

void main() {
  group('ArticleWebView.buildHtml', () {
    test('包含阅读器核心结构', () {
      final html = ArticleWebView.buildHtml(
        content: '<p>你好</p>',
        dark: false,
      );
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('class="ybh-article"'));
      expect(html, contains('<p>你好</p>'));
      expect(html, contains('data-theme="light"'));
      // 图片自适应。
      expect(html, contains('max-width: 100% !important'));
      // Ruby 振假名样式。
      expect(html, contains('ruby rt'));
      // 代码块语言标签脚本。
      expect(html, contains('language-'));
      expect(html, contains('copy-btn'));
      // 内嵌字体。
      expect(html, contains("font-family: 'Klee One'"));
      expect(html, contains('data:font/woff2;base64,'));
    });

    test('深色模式切换主题变量', () {
      final html = ArticleWebView.buildHtml(
        content: '',
        dark: true,
      );
      expect(html, contains('data-theme="dark"'));
      expect(html, contains("--bg: #121417"));
    });

    test('正文 HTML 原样注入', () {
      final html = ArticleWebView.buildHtml(
        content: '<ruby><bdo lang="ja">き</bdo><rt>ki</rt></ruby>',
        dark: false,
      );
      expect(html, contains('<ruby><bdo lang="ja">き</bdo><rt>ki</rt></ruby>'));
    });
  });
}