// Web 平台实现：品牌启动页后自动跳转博客整站。
//
// 站点响应头包含 `X-Frame-Options: SAMEORIGIN`，不允许被 iframe 内嵌，
// 因此 Web 版采用「启动即跳转」策略。
//
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'app_config.dart';

class BlogRedirectPage extends StatefulWidget {
  const BlogRedirectPage({super.key});

  @override
  State<BlogRedirectPage> createState() => _BlogRedirectPageState();
}

class _BlogRedirectPageState extends State<BlogRedirectPage> {
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _scheduleRedirect();
  }

  void _scheduleRedirect() {
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_redirected) {
        _redirected = true;
        html.window.location.assign(AppConfig.blogUrl);
      }
    });
  }

  void _redirectNow() {
    if (_redirected) return;
    _redirected = true;
    html.window.location.assign(AppConfig.blogUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: const Color(AppConfig.themeColorValue),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 120,
                  height: 120,
                  cacheWidth: 240,
                  cacheHeight: 240,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.article,
                    size: 96,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                AppConfig.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '正在进入义编会博客…',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(AppConfig.themeColorValue),
                ),
                onPressed: _redirectNow,
                icon: const Icon(Icons.open_in_browser_outlined),
                label: const Text('立即进入'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
