// Web 平台占位实现：web 构建不进入 HomeShell（BlogHost 直接跳转整站），
// 这里只保证编译期类型完整。
import 'package:flutter/material.dart';

import 'webview_ui_state.dart';

class BlogWebViewPage extends StatefulWidget {
  const BlogWebViewPage({super.key, required this.uiState});

  final WebViewUiState uiState;

  @override
  State<BlogWebViewPage> createState() => BlogWebViewState();
}

class BlogWebViewState extends State<BlogWebViewPage> {
  Future<void> reload() async {}
  Future<void> goHome() async {}
  Future<bool> goBackIfPossible() async => false;
  Future<void> share() async {}
  Future<void> openInBrowser() async {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
