import 'package:flutter/material.dart';

import '../app_config.dart';
import '../data/blog_api.dart';
import '../data/wp_auth.dart';

/// 写文章页：标题 + 正文（按空行分段）+ 状态（发布/草稿）。
///
/// 需要已登录（JWT / 应用密码兜底）。发布成功后 pop(true) 回「我的」页刷新列表。
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

  @override
  void initState() {
    super.initState();
    _loadCategories();
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
    final link = await wpAuth.publishPost(
      title: title,
      content: content,
      status: _status,
      categories: _categoryId == null ? null : [_categoryId!],
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (link == null) {
      setState(() => _error = '发布失败，请检查应用密码与发布权限');
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

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
              label: const Text('发布'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              '发布状态',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'publish', label: Text('直接发布')),
                ButtonSegment(value: 'draft', label: Text('存为草稿')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13.5),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '文章将发布到 ${AppConfig.blogUrl}',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
