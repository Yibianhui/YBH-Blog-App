import 'package:flutter/material.dart';

import '../app_config.dart';
import '../data/blog_api.dart';
import '../data/wp_auth.dart';

/// 写文章页：标题 + 正文（按空行分段）+ 状态（发布 / 提交审核 / 草稿）。
///
/// 需要已登录（JWT / 应用密码兜底）。提交成功后 pop(true) 回「我的」页刷新列表。
///
/// **投稿者适配**：WordPress 的「投稿者（contributor）」没有 `publish_posts`
/// 能力，直接发布会被服务端以 403 拒绝。本页会在打开时读取当前账号的角色与
/// 能力，无直接发布权限时：
///   - 状态选项从「直接发布」换成「提交审核」；
///   - 顶部提示当前角色与审核说明；
///   - 提交后明确告诉用户「已提交，待审核」。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  List<BlogCategory> _categories = const [];
  int? _categoryId;
  String _status = 'publish';
  bool _submitting = false;
  String? _error;

  /// 当前登录用户（含角色与能力）；为 null 表示还在读取。
  WpUser? _me;
  bool _loadingCapabilities = false;

  /// 是否有直接发布权限（读不到能力时乐观视为 true）。
  bool get _canPublish => _me?.canPublish ?? true;

  @override
  void initState() {
    super.initState();
    _status = 'publish';
    _loadCategories();
    _loadCapabilities();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await BlogApi.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // 忽略：分类为可选项。
    }
  }

  /// 读取当前账号的角色 / 能力，决定能否「直接发布」。
  Future<void> _loadCapabilities() async {
    var me = wpAuth.user;
    if (me == null || !me.capabilitiesKnown) {
      if (mounted) setState(() => _loadingCapabilities = true);
      me = await wpAuth.refreshMe() ?? me;
    }
    if (!mounted) return;
    setState(() {
      _me = me;
      _loadingCapabilities = false;
      // 没有直接发布权限时，默认改为「提交审核」。
      if (!_canPublish && _status == 'publish') _status = 'pending';
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    if (content.isEmpty) {
      setState(() => _error = '请填写正文');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await wpAuth.publishPost(
      title: title,
      content: content,
      status: _status,
      categories: _categoryId == null ? null : [_categoryId!],
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result.ok) {
      setState(() => _error = result.message ?? '提交失败，请稍后重试');
      return;
    }
    // 刷新角色信息：若这是第一次发文，能力可能刚发生变化。
    await _loadCapabilities();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final notice = result.downgraded
        ? '当前账号不能直接发布，已转为「待审核」提交'
        : result.notice;
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(notice)));
  }

  /// 当前状态对应的提交按钮文案。
  String get _submitLabel => switch (_status) {
        'draft' => '保存草稿',
        'pending' => '提交审核',
        _ => '发布',
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('写文章'),
        actions: [
          if (_submitting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(_submitLabel),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PermissionBanner(
              user: _me,
              loading: _loadingCapabilities,
              onRetry: _loadCapabilities,
            ),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '标题',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            if (_categories.isNotEmpty)
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: '分类（可选）',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('未分类'),
                  ),
                  for (final c in _categories)
                    DropdownMenuItem<int?>(
                      value: c.id,
                      child: Text('${c.name} · ${c.count}'),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: '正文，空行分段；支持普通文字与换行。',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 16,
              minLines: 8,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 16),
            Text(
              '提交方式',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'publish',
                  label: Text(_canPublish ? '直接发布' : '提交审核'),
                ),
                const ButtonSegment(value: 'draft', label: Text('存为草稿')),
              ],
              selected: {_status == 'pending' ? 'publish' : _status},
              onSelectionChanged: (s) => setState(
                () => _status = s.first == 'publish'
                    ? (_canPublish ? 'publish' : 'pending')
                    : s.first,
              ),
            ),
            if (_status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '提交后进入「待审核」，管理员通过后才会公开显示。'
                      '可在「我的 → 我的文章」查看审核状态。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '文章将提交到 ${AppConfig.blogUrl}',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部角色提示条：投稿者等无发布权限的账号会看到审核说明。
///
/// 有直接发布权限时不显示，避免打扰。
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.user,
    required this.loading,
    required this.onRetry,
  });

  final WpUser? user;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final me = user;
    if (me == null) return const SizedBox.shrink();

    // 读不到能力时不臆测，保持安静。
    if (!me.capabilitiesKnown) return const SizedBox.shrink();

    final role = me.roleLabel;
    final canPublish = me.canPublish;
    final colorScheme = Theme.of(context).colorScheme;

    if (canPublish) {
      if (role.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, size: 15, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '当前身份：$role · 可直接发布',
              style: TextStyle(fontSize: 12.5, color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: colorScheme.onTertiaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  role.isEmpty ? '当前账号需要审核' : '当前身份：$role',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '「${role.isEmpty ? '投稿者' : role}」没有直接发布权限，'
            '点「提交审核」后的文章会进入待审核队列，管理员通过后即可公开显示。'
            '若你应当是「作者」，请联系站点管理员调整角色。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.65,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onRetry,
              child: const Text('重新读取权限'),
            ),
          ),
        ],
      ),
    );
  }
}
