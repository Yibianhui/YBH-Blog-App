import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../data/blog_api.dart';
import '../data/update_checker.dart';
import '../data/wp_auth.dart';
import 'editor_page.dart';
import 'post_card.dart';
import 'post_detail_page.dart';

/// 「我的」页：未登录显示登录表单；登录后显示用户信息、我的文章与写文章入口。
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, this.onOpenCategoryOrder});

  /// 打开「分类排序」页（由外壳实现，返回后刷新文章页分类顺序）。
  final Future<void> Function()? onOpenCategoryOrder;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _logging = false;
  String? _loginError;
  bool _showAppPwHelp = false;
  bool _pwdVisible = false;

  List<PostSummary> _myPosts = const [];
  bool _loadingPosts = false;
  bool _postsError = false;

  String _version = '…';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    if (wpAuth.isLoggedIn) _loadMyPosts();
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = '0.0.0');
    }
  }

  Future<void> _login() async {
    if (_logging) return;
    setState(() {
      _logging = true;
      _loginError = null;
    });
    final ok = await wpAuth.login(_userController.text, _passController.text);
    if (!mounted) return;
    setState(() => _logging = false);
    if (ok) {
      _passController.clear();
      _loadMyPosts();
    } else {
      setState(() => _loginError = '登录失败，请检查用户名与应用密码');
    }
  }

  Future<void> _loadMyPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = false;
    });
    try {
      final posts = await wpAuth.fetchMyPosts();
      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _loadingPosts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPosts = false;
        _postsError = true;
      });
    }
  }

  Future<void> _logout() async {
    await wpAuth.logout();
    if (!mounted) return;
    setState(() {
      _myPosts = const [];
    });
  }

  Future<void> _checkUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    final info = await UpdateChecker.fetch();
    if (!mounted) return;
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('检查更新失败，请稍后重试')),
      );
      return;
    }
    if (UpdateChecker.isNewerVersion(_version, info.version)) {
      await UpdateChecker.showUpdateDialog(context, info);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('已是最新版本 v$_version')),
      );
    }
  }

  Future<void> _writeArticle() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const EditorPage()),
    );
    if (result == true && mounted) _loadMyPosts();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        if (!wpAuth.isLoggedIn) _LoginCard(
          userController: _userController,
          passController: _passController,
          logging: _logging,
          error: _loginError,
          pwdVisible: _pwdVisible,
          onTogglePwd: () => setState(() => _pwdVisible = !_pwdVisible),
          onLogin: _login,
          showHelp: _showAppPwHelp,
          onToggleHelp: () => setState(() => _showAppPwHelp = !_showAppPwHelp),
        )
        else
          _LoggedInHeader(
            user: wpAuth.user!,
            onLogout: _logout,
            onWrite: _writeArticle,
          ),
        const SizedBox(height: 20),
        if (wpAuth.isLoggedIn) ...[
          Text(
            '我的文章',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          _MyPostsList(
            loading: _loadingPosts,
            error: _postsError,
            posts: _myPosts,
            onRetry: _loadMyPosts,
            onOpen: (index) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PostDetailPage(
                  posts: _myPosts,
                  initialIndex: index,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.system_update_alt_outlined),
                title: const Text('检查更新'),
                subtitle: const Text('查看是否有新版本可用'),
                onTap: _checkUpdate,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('站点地址'),
                subtitle: const Text(AppConfig.blogUrl),
                trailing: IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      const ClipboardData(text: AppConfig.blogUrl),
                    );
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('站点地址已复制到剪贴板')),
                      );
                    }
                  },
                ),
                onTap: () => launchUrl(
                  Uri.parse(AppConfig.blogUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('分享应用'),
                subtitle: const Text('把 YBH 推荐给朋友'),
                onTap: () => SharePlus.instance.share(
                  ShareParams(
                    text: '推荐这个博客客户端给你：${AppConfig.appName}\n站点：${AppConfig.blogUrl}',
                    uri: Uri.parse(AppConfig.blogUrl),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sort_outlined),
                title: const Text('分类排序'),
                subtitle: const Text('调整「文章」页分类筛选的显示顺序'),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: widget.onOpenCategoryOrder == null
                    ? null
                    : () async {
                        await widget.onOpenCategoryOrder!();
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '关于本应用',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '义编会（YBH）WordPress 博客的多平台客户端。\n'
                  '「文章」页通过 WordPress REST API 原生渲染，速度快、不依赖 WebView；'
                  '「整站」页内嵌完整站点，保留评论、播放器等全部功能。\n'
                  '支持 Android / iOS / macOS / Web，桌面端会跳转到系统浏览器。',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.7,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'v$_version ($_buildNumber)',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 未登录：登录表单 + 应用密码获取说明。
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.userController,
    required this.passController,
    required this.logging,
    required this.error,
    required this.pwdVisible,
    required this.onTogglePwd,
    required this.onLogin,
    required this.showHelp,
    required this.onToggleHelp,
  });

  final TextEditingController userController;
  final TextEditingController passController;
  final bool logging;
  final String? error;
  final bool pwdVisible;
  final VoidCallback onTogglePwd;
  final VoidCallback onLogin;
  final bool showHelp;
  final VoidCallback onToggleHelp;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '登录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '使用站点账号的「用户名 + 密码」登录后可发布文章。',
              style: TextStyle(fontSize: 12.5, color: colorScheme.outline),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: '用户名 / 邮箱',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              obscureText: !pwdVisible,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: '账号登录密码（JWT，登录后整站自动同步）',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    pwdVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: onTogglePwd,
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onLogin(),
              autofillHints: const [AutofillHints.password],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: logging ? null : onLogin,
                icon: logging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.login, size: 18),
                label: const Text('登录'),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: onToggleHelp,
              child: Text(showHelp ? '收起说明' : '登录方式说明'),
            ),
            if (showHelp)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '默认用「用户名 + 账号密码」通过 JWT 登录（站点已安装 JWT 插件，最方便）。\n'
                  '若 JWT 不可用（插件未装/未配置），会自动改用 WordPress 核心的「应用密码」：\n'
                  '  1. 用浏览器登录站点后台（WordPress 仪表盘）；\n'
                  '  2. 进入「用户 → 个人资料」；\n'
                  '  3. 找到「应用密码」一栏，输入名称后点击「添加新应用密码」；\n'
                  '  4. 复制生成的 24 位密码（含空格），粘贴到「密码」框即可。\n'
                  '（两种方式均需站点启用 HTTPS，本站已满足。）',
                  style: TextStyle(fontSize: 12.5, height: 1.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 已登录：用户信息头部 + 写文章按钮。
class _LoggedInHeader extends StatelessWidget {
  const _LoggedInHeader({
    required this.user,
    required this.onLogout,
    required this.onWrite,
  });

  final WpUser user;
  final VoidCallback onLogout;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage:
                  user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (user.email != null && user.email!.isNotEmpty)
                    Text(
                      user.email!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onWrite,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('写文章'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '退出登录',
              icon: const Icon(Icons.logout_outlined),
              onPressed: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

/// 已登录：我的文章列表。
class _MyPostsList extends StatelessWidget {
  const _MyPostsList({
    required this.loading,
    required this.error,
    required this.posts,
    required this.onRetry,
    required this.onOpen,
  });

  final bool loading;
  final bool error;
  final List<PostSummary> posts;
  final VoidCallback onRetry;
  final void Function(int) onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error) {
      return Center(
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40),
            const SizedBox(height: 8),
            const Text('加载失败'),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '还没有发布文章',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < posts.length; i++) ...[
          PostCard(post: posts[i], onTap: () => onOpen(i)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
