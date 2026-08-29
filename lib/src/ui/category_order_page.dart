import 'package:flutter/material.dart';

import '../data/blog_api.dart';
import '../data/category_order.dart';

/// 分类排序页：用拖拽方式调整「文章」页分类筛选条中分类的显示顺序。
///
/// 顺序仅保存在本机（[CategoryOrderStore]），不影响服务器。
/// 「重置」可恢复为服务器默认排序（按文章数降序）。
class CategoryOrderPage extends StatefulWidget {
  const CategoryOrderPage({super.key, this.initialCategories = const []});

  /// 可选：从「文章」页已加载的分类直接带入，避免重复联网。
  final List<BlogCategory> initialCategories;

  @override
  State<CategoryOrderPage> createState() => _CategoryOrderPageState();
}

class _CategoryOrderPageState extends State<CategoryOrderPage> {
  List<BlogCategory> _categories = const [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.initialCategories.isNotEmpty) {
      // 带入的分类已是「套用自定义顺序后」的结果，需要先还原成服务器原始顺序，
      // 以让用户从默认顺序重新调整。这里重新联网拉取以保证基准一致。
      await _loadFromNetwork(keepLocalOrder: false);
    } else {
      await _loadFromNetwork(keepLocalOrder: true);
    }
  }

  Future<void> _loadFromNetwork({required bool keepLocalOrder}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetched = await BlogApi.fetchCategories();
      if (!mounted) return;
      List<BlogCategory> ordered = fetched;
      if (keepLocalOrder) {
        final order = await CategoryOrderStore.loadOrder();
        ordered = CategoryOrderStore.applyOrderWith(
          categories: fetched,
          idOf: (c) => c.id,
          order: order,
        );
      }
      setState(() {
        _categories = ordered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final order = _categories.map((c) => c.id).toList();
    final ok = await CategoryOrderStore.saveOrder(order);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分类顺序已保存')),
      );
      // 返回 true，通知「文章」页重新套用顺序。
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _reset() async {
    final ok = await CategoryOrderStore.clearOrder();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重置失败，请稍后重试')),
      );
      return;
    }
    // 重置后按服务器默认（文章数降序）重新加载。
    await _loadFromNetwork(keepLocalOrder: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复默认排序')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类排序'),
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: const LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          if (_error != null)
            IconButton(
              tooltip: '重试',
              onPressed: () => _loadFromNetwork(keepLocalOrder: true),
              icon: const Icon(Icons.refresh),
            )
          else ...[
            TextButton.icon(
              onPressed: _saving ? null : _reset,
              icon: const Icon(Icons.restart_alt_outlined, size: 20),
              label: const Text('重置'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _saving || _categories.isEmpty ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.save_outlined, size: 20),
                label: const Text('保存'),
              ),
            ),
          ],
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              const Text('分类加载失败', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('请检查网络后重试', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          '暂无可排序的分类',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            '长按并拖动右侧手柄调整顺序，保存后将在「文章」页的分类筛选条生效。',
            style: TextStyle(fontSize: 13, color: colorScheme.outline, height: 1.6),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _categories.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _categories.removeAt(oldIndex);
                _categories.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final category = _categories[index];
              return Card(
                key: ValueKey(category.id),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(category.name),
                  subtitle: Text('${category.count} 篇文章'),
                  trailing: const Icon(Icons.drag_handle_outlined),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
