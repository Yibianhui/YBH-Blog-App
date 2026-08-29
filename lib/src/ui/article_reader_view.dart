import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app_config.dart';
import 'article_fonts.dart';

/// WebView 文章正文阅读器（Android / iOS / macOS）。
///
/// 为什么用 WebView 而不是 flutter_html：
/// - 站点正文里大量使用 `width/height` 属性 + `srcset/sizes` 的图片，
///   浏览器能按窗口宽度正确缩放（修复「图片过大」），并原生支持懒加载
///   （修复「图片不显示」）；
/// - `<ruby><rt>` 振假名由浏览器原生排版（修复「Ruby 不显示」）；
/// - `<pre><code class="language-*">` 代码块提取语言标签、带复制按钮；
/// - 站点自定义字体（Klee One / Boxed）以 base64 内嵌，绕过
///   download.yibianhui.cn 无 CORS 头导致的字体加载失败（修复「自定义
///   字体不显示」），并挂载站点 block 样式表，使 `wp-block-*` /
///   `has-*-font-family` 等 CSS 类样式生效（修复「CSS 定义样式失效」）；
/// - iframe（bilibili 等）视频直接内嵌播放。
class ArticleWebView extends StatefulWidget {
  const ArticleWebView({
    super.key,
    required this.content,
    required this.dark,
  });

  /// 文章正文 HTML（WordPress REST API rendered 内容）。
  final String content;

  /// 是否深色（跟随 App 内手动夜间模式）。
  final bool dark;

  /// 构造阅读器 HTML 文档。
  ///
  /// - 内嵌站点自定义字体（base64，见 [ArticleFonts]）；
  /// - 挂载站点 wp-block-library 样式表 + ruby 插件样式表 + Google Fonts；
  /// - 注入阅读器样式（图片自适应 / ruby / 代码块 / 表格 / 深色模式）；
  /// - 注入小脚本：代码块语言标签 + 复制按钮 + 懒加载图片占位。
  static String buildHtml({required String content, required bool dark}) {
    final theme = dark ? 'dark' : 'light';
    return '''
<!DOCTYPE html>
<html data-theme="$theme">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>YBH</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Noto+Serif+SC|Noto+Sans+SC|Fira+Code&display=swap">
<link rel="stylesheet" href="https://www.yibianhui.cn/wp-includes/css/dist/block-library/style.min.css">
<link rel="stylesheet" href="https://www.yibianhui.cn/wp-content/plugins/ruby-markup-converter//public/css/ruby-markup-converter.css">
<style>
/* ===== 站点自定义字体（base64 内嵌，跨域/CORS 失效免疫） ===== */
@font-face {
  font-family: 'Klee One';
  src: url(${ArticleFonts.kleeOneRegular}) format('woff2');
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: 'Klee One';
  src: url(${ArticleFonts.kleeOneSemiBold}) format('woff2');
  font-weight: 600;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: 'Boxed';
  src: url(${ArticleFonts.boxed}) format('woff2');
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}

/* ===== 主题变量 ===== */
html[data-theme='light'] {
  --bg: #ffffff;
  --text: #1f2328;
  --text2: #667085;
  --bg2: #f2f4f7;
  --border: #e4e7ec;
  --accent: #505050;
  --code-bg: #f6f8fa;
  color-scheme: light;
}
html[data-theme='dark'] {
  --bg: #121417;
  --text: #e3e6ea;
  --text2: #99a0a8;
  --bg2: #20242a;
  --border: #2e333a;
  --accent: #7aa2f7;
  --code-bg: #191c21;
  color-scheme: dark;
}

/* ===== 阅读器基础排版 ===== */
html, body {
  margin: 0;
  padding: 0;
}
body {
  background: var(--bg);
  color: var(--text);
  font-family: 'Noto Sans SC', -apple-system, BlinkMacSystemFont, 'PingFang SC',
    'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
  font-size: 16px;
  line-height: 1.8;
  overflow-wrap: break-word;
  word-break: break-word;
  -webkit-text-size-adjust: 100%;
  -webkit-font-smoothing: antialiased;
}
.ybh-article {
  max-width: 100%;
  padding: 14px 18px 48px;
}

/* ===== 图片：自适应宽度 + 保持比例（修复“图片过大”） ===== */
img {
  max-width: 100% !important;
  height: auto !important;
  display: block;
  margin: 1em auto;
  border-radius: 8px;
}
figure {
  margin: 1.2em 0;
  text-align: center;
}
figure img {
  margin: 0 auto;
}
figcaption {
  font-size: 13px;
  line-height: 1.6;
  color: var(--text2);
  margin-top: 0.5em;
}

/* ===== 标题 / 段落 / 引用 ===== */
h1, h2, h3, h4, h5, h6 {
  margin: 1.3em 0 0.6em;
  line-height: 1.45;
  font-weight: 700;
}
h1 { font-size: 1.45em; }
h2 { font-size: 1.32em; }
h3 { font-size: 1.18em; }
h4 { font-size: 1.08em; }
p { margin: 0 0 1em; }
blockquote {
  margin: 1em 0;
  padding: 0.4em 1em;
  border-left: 3px solid var(--accent);
  background: var(--bg2);
  color: var(--text2);
  border-radius: 0 10px 10px 0;
}
blockquote p { margin: 0.4em 0; }
hr {
  border: none;
  border-top: 1px solid var(--border);
  margin: 1.6em 0;
}

/* ===== 链接 ===== */
a {
  color: var(--accent);
  text-decoration: none;
}
a:active { opacity: 0.7; }

/* ===== Ruby 振假名（浏览器原生排版） ===== */
ruby { ruby-align: center; }
ruby rt {
  font-size: 0.52em;
  line-height: 1.2;
  color: var(--text2);
}

/* ===== 代码块：语言标签 + 复制按钮 ===== */
pre {
  position: relative;
  margin: 1em 0;
  padding: 16px 14px 14px;
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 10px;
  overflow-x: auto;
  font-size: 13.5px;
  line-height: 1.65;
}
pre code {
  font-family: 'Fira Code', ui-monospace, SFMono-Regular, Consolas,
    'Liberation Mono', monospace;
  background: transparent;
  padding: 0;
  border-radius: 0;
  font-size: inherit;
}
code {
  font-family: 'Fira Code', ui-monospace, SFMono-Regular, Consolas,
    'Liberation Mono', monospace;
  background: var(--bg2);
  padding: 2px 6px;
  border-radius: 5px;
  font-size: 0.9em;
}
pre[data-lang]::before {
  content: attr(data-lang);
  position: absolute;
  top: 7px;
  right: 72px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.5px;
  color: var(--text2);
  text-transform: uppercase;
}
.copy-btn {
  position: absolute;
  top: 6px;
  right: 8px;
  padding: 3px 10px;
  font-size: 11px;
  line-height: 1.6;
  color: var(--text2);
  background: var(--bg2);
  border: 1px solid var(--border);
  border-radius: 6px;
  cursor: pointer;
}
.copy-btn:active { opacity: 0.7; }

/* ===== 表格 ===== */
table {
  width: 100%;
  max-width: 100%;
  border-collapse: collapse;
  margin: 1em 0;
  font-size: 14px;
}
th, td {
  border: 1px solid var(--border);
  padding: 7px 10px;
  text-align: left;
}
th {
  background: var(--bg2);
  font-weight: 600;
}

/* ===== 媒体 ===== */
iframe, video {
  max-width: 100%;
  width: 100%;
  aspect-ratio: 16 / 9;
  border: 0;
  border-radius: 10px;
  background: #000;
  margin: 1em auto;
  display: block;
}
audio { width: 100%; margin: 1em 0; }

/* ===== 列表 / 其他块 ===== */
ul, ol { padding-left: 1.6em; margin: 0 0 1em; }
li { margin: 0.25em 0; }
</style>
</head>
<body>
<article class="ybh-article">
$content
</article>
<script>
(function () {
  // 代码块：提取 language-* 语言标签 + 添加复制按钮。
  function fallbackCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
  }
  document.querySelectorAll('pre').forEach(function (pre) {
    var code = pre.querySelector('code');
    if (!code) return;
    var m = (code.className || '').match(/language-([A-Za-z0-9_+#-]+)/);
    if (m && m[1]) pre.setAttribute('data-lang', m[1]);
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = '复制';
    btn.addEventListener('click', function () {
      var text = code.innerText;
      var done = function () {
        btn.textContent = '已复制';
        setTimeout(function () { btn.textContent = '复制'; }, 1400);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {
          fallbackCopy(text); done();
        });
      } else {
        fallbackCopy(text); done();
      }
    });
    pre.appendChild(btn);
  });

  // 修复：懒加载图片未带宽高时高度跳动，用 width/height 属性预占位。
  document.querySelectorAll('img[loading="lazy"]').forEach(function (img) {
    if (img.getAttribute('width') && img.getAttribute('height')) {
      var w = parseInt(img.getAttribute('width'), 10);
      var h = parseInt(img.getAttribute('height'), 10);
      if (w > 0 && h > 0 && !img.style.aspectRatio) {
        img.style.aspectRatio = String(w) + ' / ' + String(h);
        img.style.height = 'auto';
      }
    }
  });
})();
</script>
</body>
</html>
''';
  }

  @override
  State<ArticleWebView> createState() => _ArticleWebViewState();
}

class _ArticleWebViewState extends State<ArticleWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.dark ? const Color(0xFF121417) : Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            // 站内链接留在阅读器里（如文内互链），外部链接交给系统浏览器。
            if (AppConfig.isInAppUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            launchUrl(
              Uri.parse(request.url),
              mode: LaunchMode.externalApplication,
            );
            return NavigationDecision.prevent;
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    // 仅调试构建开启 WebView 远程调试（CDP），便于真机验证渲染；发布版不受影响。
    if (kDebugMode) {
      await AndroidWebViewController.enableDebugging(true);
    }
    await _controller.loadHtmlString(
      ArticleWebView.buildHtml(
        content: widget.content,
        dark: widget.dark,
      ),
      baseUrl: '${AppConfig.blogUrl}/',
    );
  }

  @override
  void didUpdateWidget(covariant ArticleWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content || oldWidget.dark != widget.dark) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        // 顶部加载进度条（文章 HTML 本地注入，仅资源加载期间短暂显示）。
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _loading ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}