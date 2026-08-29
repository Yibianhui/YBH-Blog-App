import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'desktop_fallback_page.dart';
import 'shell/home_shell.dart';
import 'web_redirect_stub.dart' if (dart.library.html) 'web_redirect_page.dart';

/// 根据运行平台选择应用外壳：
/// - Android / iOS / macOS：完整三栏外壳（文章 + 整站 WebView + 我的）；
/// - Web：品牌启动页后自动跳转博客整站；
/// - Windows / Linux：轻量桌面壳（跳转系统浏览器打开站点）。
class BlogHost extends StatelessWidget {
  const BlogHost({
    super.key,
    required this.darkMode,
    required this.onToggleDarkMode,
  });

  final bool darkMode;
  final ValueChanged<bool> onToggleDarkMode;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const BlogRedirectPage();
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return HomeShellPage(
          darkMode: darkMode,
          onToggleDarkMode: onToggleDarkMode,
        );
      default:
        return const DesktopFallbackPage();
    }
  }
}
