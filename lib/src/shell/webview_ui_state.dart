import 'package:flutter/foundation.dart';

import '../app_config.dart';

/// 外壳与 WebView 页共享的 UI 状态（加载进度、导航能力、当前地址等），
/// 由 HomeShell 持有并监听，用于构建 AppBar 进度条与操作按钮。
class WebViewUiState {
  final ValueNotifier<int> progress = ValueNotifier<int>(0);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> hasError = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canGoBack = ValueNotifier<bool>(false);
  final ValueNotifier<String> currentUrl = ValueNotifier<String>(AppConfig.blogUrl);

  Listenable get merged => Listenable.merge([progress, loading, hasError, canGoBack, currentUrl]);

  void dispose() {
    progress.dispose();
    loading.dispose();
    hasError.dispose();
    canGoBack.dispose();
    currentUrl.dispose();
  }
}
