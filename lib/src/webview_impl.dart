import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'app_config.dart';
import 'data/wp_auth.dart';
import 'shell/webview_ui_state.dart';

/// 整站 WebView 页（Android / iOS / macOS）。
///
/// 仅承载 WebView 本体与加载/错误浮层；AppBar、返回键等由 HomeShell 统一处理。
/// 内嵌 https://www.yibianhui.cn 整站，特性：
/// - 加载进度与错误页通过 [WebViewUiState] 上报给外壳
/// - 站外链接自动转交系统浏览器，站内链接留在应用内
/// - 页面加载完成后注入“性能模式”样式，关闭站点重特效提升旧设备滚动流畅度
/// - **登录态同步**：App 在「我的」页登录后，WebView 用内存中的最新凭据
///   自动完成 wp-login 表单登录（服务端只信任真实浏览器指纹的登录，
///   应用内 HttpClient 拿到的会话无效，故必须由 WebView 自身登录）；
///   退出登录时清空 WebView Cookie。
class BlogWebViewPage extends StatefulWidget {
  const BlogWebViewPage({super.key, required this.uiState});

  final WebViewUiState uiState;

  @override
  State<BlogWebViewPage> createState() => BlogWebViewState();
}

class BlogWebViewState extends State<BlogWebViewPage> {
  /// 站点主题自带动画/毛玻璃/固定背景等效果，在低端 Android WebView 上会
  /// 导致滚动掉帧。页面加载完成后注入一段“性能模式”样式：
  /// - 关闭 CSS 动画与过渡
  /// - 固定背景改为随内容滚动（Android WebView 固定背景重绘开销极大）
  /// - 关闭 backdrop-filter / filter（GPU 合成开销大）
  /// - 隐藏粒子 canvas
  /// - 还原 AOS 进入动画元素的最终可见状态
  static const String _performanceScript = '''
(function () {
  if (window.__ybhPerfApplied) { return; }
  window.__ybhPerfApplied = true;
  try {
    var css = [
      '*{-webkit-animation-duration:0s!important;animation-duration:0s!important;',
      '-webkit-animation-iteration-count:1!important;animation-iteration-count:1!important;',
      '-webkit-transition-duration:0s!important;transition-duration:0s!important;}',
      '*{background-attachment:scroll!important;}',
      '*{-webkit-backdrop-filter:none!important;backdrop-filter:none!important;}',
      '*{filter:none!important;}',
      'canvas{display:none!important;}',
      '[data-aos]{opacity:1!important;-webkit-transform:none!important;transform:none!important;}',
      'html,body{scroll-behavior:auto!important;}'
    ].join('\\n');
    var style = document.createElement('style');
    style.id = 'ybh-perf-style';
    style.appendChild(document.createTextNode(css));
    document.head.appendChild(style);
    if (window.AOS && typeof window.AOS.refreshHard === 'function') {
      try { window.AOS.refreshHard(); } catch (e) {}
    }
  } catch (e) {}
})();
''';

  /// 在登录页填表并提交的脚本。
  ///
  /// 凭据以 JSON 字符串嵌入（避免引号/反斜杠注入）。返回值为诊断用字符串：
  /// - `'ok'` 表单已提交；
  /// - `'no-form'` 页面上找不到密码输入框（可能是错误页/已登录的重定向页）；
  /// - `'no-user-field'` 表单里找不到用户名输入框。
  ///
  /// 站点主题（Sakurairo）可能用自己的登录表单而非标准 wp-login 结构，
  /// 因此这里不依赖 `#user_login` / `#loginform` 等固定 id，改为：
  /// 先定位密码框 → 取其所属 form → 在 form 内找用户名框（按常见 name/id 依次回退）。
  /// 提交时优先 `requestSubmit()`（会触发主题绑定的校验与 AJAX 逻辑），
  /// 失败再退回点击提交按钮、最后才是 `form.submit()`。
  static String _loginScript(String user, String pass) {
    final u = jsonEncode(user);
    final p = jsonEncode(pass);
    return '''
(function () {
  var u = $u, p = $p;
  var pass = document.querySelector('input[type="password"]');
  if (!pass) return 'no-form';
  var form = pass.form;
  if (!form) return 'no-form';
  var user = form.querySelector('input[name="log"]')
          || form.querySelector('#user_login')
          || form.querySelector('input[name="username"]')
          || form.querySelector('input[name="user_login"]')
          || form.querySelector('input[autocomplete="username"]')
          || form.querySelector('input[type="email"]')
          || form.querySelector('input[type="text"]');
  if (!user) return 'no-user-field';

  // 用原生 setter 赋值并派发事件，确保 Vue/React 等框架能感知到输入。
  function setVal(el, v) {
    var proto = el instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) { desc.set.call(el, v); } else { el.value = v; }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  setVal(user, u);
  setVal(pass, p);

  // 勾上「记住我」，让整站会话在下次冷启动仍然有效。
  var remember = form.querySelector('input[name="rememberme"]');
  if (remember && !remember.checked) {
    remember.checked = true;
    remember.dispatchEvent(new Event('change', { bubbles: true }));
  }

  var btn = form.querySelector('input[type="submit"]')
         || form.querySelector('button[type="submit"]')
         || form.querySelector('button');
  var fired = false;
  form.addEventListener('submit', function () { fired = true; });

  // requestSubmit 会走表单校验与主题绑定的 submit 处理器，是首选。
  if (typeof form.requestSubmit === 'function') {
    try { form.requestSubmit(btn || undefined); } catch (e) {}
  }
  // 若没触发 submit 事件（主题用 click 处理器），退回到点击按钮。
  if (!fired && btn) {
    try { btn.click(); } catch (e) {}
  }
  // 最后兜底：直接提交（不触发 submit 事件，但一定会导航）。
  if (!fired) {
    try { form.submit(); } catch (e) {}
  }
  return 'ok';
})();
''';
  }

  late final WebViewController _controller;
  bool _androidConfigured = false;

  /// 是否正在执行自动登录（页面完成回调里判断是否要填表提交）。
  bool _autoLogging = false;

  /// 自动登录成功后要回到的页面（登录前正在浏览的站内地址）。
  /// 为空表示回站点首页。
  String? _autoLoginReturnUrl;

  WebViewUiState get _ui => widget.uiState;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF5F6F8))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) => _ui.progress.value = progress,
          onPageStarted: (String url) {
            _ui.currentUrl.value = url;
            _ui.loading.value = true;
            _ui.hasError.value = false;
          },
          onPageFinished: (String url) async {
            _ui.currentUrl.value = url;
            _ui.loading.value = false;
            await _refreshNavigationState();
            await _configureAndroidWebView();
            // 自动登录：登录页加载完成后立即填表提交。
            if (_autoLogging && url.contains('wp-login.php')) {
              _autoLogging = false;
              final creds = wpAuth.webLoginCredentials;
              if (creds != null) {
                try {
                  final result = await _controller.runJavaScriptReturningResult(
                    _loginScript(creds.$1, creds.$2),
                  );
                  // 页面不是登录表单（可能已登录被重定向，或主题换了结构）：
                  // 主动回到目标页面，避免停在无意义的中间页。
                  if (result is String && result.startsWith('no-')) {
                    final target = _autoLoginReturnUrl;
                    if (target != null && target.isNotEmpty) {
                      await _controller.loadRequest(Uri.parse(target));
                    }
                  }
                } catch (_) {
                  // 忽略：自动登录失败不阻塞用户手动登录。
                }
              }
              _autoLoginReturnUrl = null;
            }
            // 仅调试构建开启远程调试（CDP），便于真机验证登录态/渲染。
            if (kDebugMode) {
              try {
                await AndroidWebViewController.enableDebugging(true);
              } catch (_) {
                // 忽略：仅调试用途。
              }
            }
            // 性能模式：关闭站点重特效，提升旧设备 WebView 滚动流畅度。
            await _controller.runJavaScript(_performanceScript);
          },
          onWebResourceError: (WebResourceError error) {
            // 只对主框架错误显示错误页，避免图片等子资源失败误报。
            if (!(error.isForMainFrame ?? true)) return;
            _ui.hasError.value = true;
            _ui.loading.value = false;
          },
          onNavigationRequest: (NavigationRequest request) {
            if (AppConfig.isInAppUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            openInBrowser(request.url);
            return NavigationDecision.prevent;
          },
        ),
      );
    _controller.loadRequest(Uri.parse(AppConfig.blogUrl));
    // App 登录/退出事件：登录 → WebView 自动登录；退出 → 清 Cookie。
    wpAuth.webLoginRequested.addListener(_onWebLoginRequested);
    // 冷启动时若 App 已登录但 WebView 尚无会话：尝试一次自动登录，
    // 保证「整站」与 App 登录态一致（WebView 自身会话在下次启动仍有效，
    // 此处仅兜底，不会重复登录）。
    if (wpAuth.isLoggedIn && wpAuth.webLoginCredentials != null) {
      _startAutoLogin();
    }
  }

  @override
  void dispose() {
    wpAuth.webLoginRequested.removeListener(_onWebLoginRequested);
    super.dispose();
  }

  void _onWebLoginRequested() {
    if (wpAuth.isLoggedIn && wpAuth.webLoginCredentials != null) {
      _startAutoLogin();
    } else {
      _clearSessionAndReload();
    }
  }

  /// 开始自动登录：导航到 wp-login.php，页面加载完自动填表提交。
  ///
  /// [returnTo] 指定登录成功后要回到的页面；不传则取当前正在浏览的页面，
  /// 这样「整站」登录后能回到原处而不是被踢回首页。
  void _startAutoLogin({String? returnTo}) {
    if (_autoLogging) return;
    _autoLogging = true;
    _ui.hasError.value = false;
    _autoLoginReturnUrl = _resolveReturnUrl(returnTo ?? _ui.currentUrl.value);
    _controller.loadRequest(
      Uri.parse(
        '${AppConfig.blogUrl}/wp-login.php'
        '?redirect_to=${Uri.encodeComponent(_autoLoginReturnUrl!)}',
      ),
    );
  }

  /// 决定登录成功后回到哪里。
  ///
  /// 仅接受站内地址；登录页自身、空地址、站外地址一律退回站点首页兜底，
  /// 避免把 `redirect_to` 指向登录页造成死循环。
  String _resolveReturnUrl(String? url) {
    const home = '${AppConfig.blogUrl}/';
    if (url == null || url.isEmpty) return home;
    if (url.contains('wp-login.php')) return home;
    if (!AppConfig.isInAppUrl(url)) return home;
    return url;
  }

  /// 退出登录：清空 WebView Cookie 并回到首页（整站随即呈未登录态）。
  Future<void> _clearSessionAndReload() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // 清理失败不阻塞重载。
    }
    if (mounted) {
      await _controller.loadRequest(Uri.parse(AppConfig.blogUrl));
    }
  }

  Future<void> _refreshNavigationState() async {
    _ui.canGoBack.value = await _controller.canGoBack();
  }

  /// Android 专项调优：关闭滚动条与过度滚动光晕，减少滚动时系统额外绘制。
  Future<void> _configureAndroidWebView() async {
    if (_androidConfigured) return;
    _androidConfigured = true;
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setOverScrollMode(WebViewOverScrollMode.never);
    await platform.setVerticalScrollBarEnabled(false);
    await platform.setHorizontalScrollBarEnabled(false);
  }

  Future<void> reload() async {
    _ui.hasError.value = false;
    _ui.loading.value = true;
    _ui.progress.value = 0;
    await _controller.reload();
  }

  Future<void> goHome() async {
    _ui.hasError.value = false;
    await _controller.loadRequest(Uri.parse(AppConfig.blogUrl));
  }

  /// 返回网页上一页；无可后退页面时返回 false，交由外壳处理。
  Future<bool> goBackIfPossible() async {
    if (_ui.hasError.value) {
      await reload();
      return true;
    }
    if (_ui.canGoBack.value) {
      await _controller.goBack();
      await _refreshNavigationState();
      return true;
    }
    return false;
  }

  Future<void> share() async {
    var url = _ui.currentUrl.value;
    try {
      final current = await _controller.currentUrl();
      if (current != null && current.isNotEmpty) url = current;
    } catch (_) {
      // 忽略：使用页面回调记录的地址。
    }
    await SharePlus.instance.share(
      ShareParams(
        text: '来自${AppConfig.appName}的分享：$url',
        uri: Uri.parse(url),
      ),
    );
  }

  Future<void> openInBrowser([String? url]) async {
    final uri = Uri.tryParse(url ?? _ui.currentUrl.value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(controller: _controller),
        ),
        // 首屏加载动画（progress 仍为 0 且无错误时显示）。
        ListenableBuilder(
          listenable: _ui.merged,
          builder: (context, child) {
            final showSplash =
                _ui.loading.value && _ui.progress.value == 0 && !_ui.hasError.value;
            if (!showSplash) return const SizedBox.shrink();
            return Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '正在加载 ${AppConfig.appName}…',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // 主框架加载失败错误页。
        ListenableBuilder(
          listenable: _ui.hasError,
          builder: (context, child) {
            if (!_ui.hasError.value) return const SizedBox.shrink();
            return Positioned.fill(
              child: _ErrorView(
                onRetry: reload,
                onOpenBrowser: openInBrowser,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, required this.onOpenBrowser});

  final VoidCallback onRetry;
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 72,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 20),
              const Text(
                '页面加载失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                '请检查网络连接后重试。',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenBrowser,
                icon: const Icon(Icons.open_in_browser_outlined),
                label: const Text('用系统浏览器打开'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}