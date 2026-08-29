import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

/// Windows / Linux 桌面回退页：展示站点信息，并跳转系统浏览器打开博客。
class DesktopFallbackPage extends StatelessWidget {
  const DesktopFallbackPage({super.key});

  Future<void> _openBlog(BuildContext context) async {
    final uri = Uri.parse(AppConfig.blogUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请手动访问 yibianhui.cn')),
      );
    }
  }

  Future<void> _copyUrl(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: AppConfig.blogUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('站点地址已复制到剪贴板')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 112,
                    height: 112,
                    cacheWidth: 224,
                    cacheHeight: 224,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.article,
                      size: 96,
                      color: primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  AppConfig.appName,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  AppConfig.blogUrl,
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  '义编会（YBH）WordPress 博客\n'
                  '桌面版通过系统浏览器访问站点，完整功能请以 Android / iOS / Web 版为准。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, height: 1.6),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => _openBlog(context),
                  icon: const Icon(Icons.open_in_browser_outlined),
                  label: const Text('打开博客'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _copyUrl(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制站点地址'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
