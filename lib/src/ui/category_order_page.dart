import 'dart:async';

import 'package:flutter/material.dart';

import '../data/blog_api.dart';
import '../data/category_order.dart';

/// 分类排序页：调整「文章」页分类筛选条中分类的显示方式。
///
/// 支持三种调整：
/// - **拖拽排序**：长按右侧手柄拖动；
/// - **置顶**：钉住的分类始终排在最前；
/// - **隐藏**：隐藏的分类不出现在筛选条中（在本页可随时恢复）。
///
/// 偏好仅保存在本机（[CategoryOrderStore]），不影响服务器。
/// 「重置」可恢复为服务器默认排序（按文章数降序）。
class CategoryOrderPage extends StatefulWidget {
  const CategoryOrderPage({super.key, this.initialCategories = const []});

  /// 可选：从「文章」页已加载的分类直接带入，避免重复联网。
  final List<BlogCategory> initialCategories;

  @override
  State<CategoryOrderPage> createState() => _CategoryOrderPageState();
}

class _CategoryOrderPageState extends State<CategoryOrderPage> {
  /// 服务器原始顺序（按文章数降序），作为重置与拖拽的基准。
  List<BlogCategory> _all = const [];

  /// 当前展示顺序（含已隐藏项，便于恢复）。
  List<BlogCategory> _display = const [];

  CategoryPrefs _prefs = const CategoryPrefs();
  bool _loading = true;
  bool _saving = false;
  /// 用户是否已在本页做过改动（有改动时不再后台刷新，避免打断排序）。
  bool _dirty = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await CategoryOrderStore.load();
    if (!mounted) return;
    if (widget.initialCategories.isNotEmpty) {
      // 复用「文章」页已拉取的分类，首屏无需等待联网。
      setState(() {
        _all = widget.initialCategories;
        _prefs = prefs;
        _display = _reorder(widget.initialCategories, prefs);
        _loading = false;
      });
      // 后台静默补齐服务器新增的分类。
      unawaited(_refreshInBackground());
      return;
    }
    await _loadFromNetwork();
  }

  /// 静默重新拉取分类；若用户已改动过顺序则不打扰。
  Future<void> _refreshInBackground() async {
    if (_dirty || _saving) return;
    try {
      final fetched = await BlogApi.fetchCategories();
      if (!mounted || fetched.isEmpty || _dirty) return;
      setState(() {
        _all = fetched;
        _display = _reorder(fetched, _prefs);
      });
    } catch (_) {
      // 静默失败：保留已展示的列表，不影响用户操作。
    }
  }

  Future<void> _loadFromNetwork() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetched = await BlogApi.fetchCategories();
      final prefs = await CategoryOrderStore.load();
      if (!mounted) return;
      // 若「文章」页已带入分类且本次拉取为空（离线/异常），回退使用带入的数据，
      // 保证排序页在弱网下仍可用。
      final base = fetched.isNotEmpty ? fetched : widget.initialCategories;
      setState(() {
        _all = base;
        _prefs = prefs;
        _display = _reorder(base, prefs);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (widget.initialCategories.isNotEmpty) {
        final prefs = await CategoryOrderStore.load();
        if (!mounted) return;
        setState(() {
          _all = widget.initialCategories;
          _prefs = prefs;
          _display = _reorder(widget.initialCategories, prefs);
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// 按偏好重排（保留已隐藏项，让用户可以恢复）。
  List<BlogCategory> _reorder(List<BlogCategory> base, CategoryPrefs prefs) {
    return CategoryOrderStore.applyOrderWith<BlogCategory>(
      categories: base,
      idOf: (c) => c.id,
      order: prefs.order,
      pinned: prefs.pinned.toList(),
      hidden: prefs.hidden.toList(),
      excludeHidden: false,
    );
  }

  void _moveToTop(int id) {
    setState(() {
      final index = _display.indexWhere((c) => c.id == id);
      if (index <= 0) return;
      final item = _display.removeAt(index);
      _display.insert(0, item);
      _dirty = true;
      _syncPrefs();
    });
  }

  void _togglePin(int id) {
    setState(() {
      _dirty = true;
      final pinned = _prefs.pinned.toSet();
      if (pinned.contains(id)) {
        pinned.remove(id);
      } else {
        pinned.add(id);
        // 置顶的分类若处于隐藏状态会自动显示，此处同步取消隐藏以免状态矛盾。
        final hidden = _prefs.hidden.toSet()..remove(id);
        _prefs = _prefs.copyWith(pinned: pinned, hidden: hidden);
        _display = _reorder(_all, _prefs);
        return;
      }
      _prefs = _prefs.copyWith(pinned: pinned);
      _display = _reorder(_all, _prefs);
    });
  }

  void _toggleHidden(int id) {
    setState(() {
      _dirty = true;
      final hidden = _prefs.hidden.toSet();
      if (hidden.contains(id)) {
        hidden.remove(id);
      } else {
        hidden.add(id);
        // 隐藏与置顶互斥：隐藏时自动取消置顶。
        final pinned = _prefs.pinned.toSet()..remove(id);
        _prefs = _prefs.copyWith(hidden: hidden, pinned: pinned);
      }
      _prefs = _prefs.copyWith(hidden: hidden);
      _display = _reorder(_all, _prefs);
    });
  }

  /// 把当前展示顺序写回偏好（[CategoryPrefs.order]）。
  void _syncPrefs() {
    _prefs = _prefs.copyWith(order: _display.map((c) => c.id).toList());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _syncPrefs();
    final ok = await CategoryOrderStore.save(_prefs);
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
        const SnackBar(content: Text('分类设置已保存')),
      );
      // 返回 true，通知「文章」页重新套用偏好。
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _reset() async {
    final ok = await CategoryOrderStore.clear();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重置失败，请稍后重试')),
      );
      return;
    }
    setState(() {
      _prefs = const CategoryPrefs();
      _display = _reorder(_all, _prefs);
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认排序')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类排序'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          if (_error != null)
            IconButton(
              tooltip: '重试',
              onPressed: _loadFromNetwork,
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
                onPressed: _saving || _display.isEmpty ? null : _save,
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
              Icon(Icons.wifi_off_rounded,
                  size: 56, color: colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              const Text('分类加载失败',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('请检查网络后重试',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_display.isEmpty) {
      return Center(
        child: Text(
          '暂无可排序的分类',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    final pinnedCount = _prefs.pinned.length;
    final hiddenCount = _prefs.hidden.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            '长按右侧手柄拖动调整顺序；点图钉置顶、点眼睛隐藏。'
            '${pinnedCount > 0 ? '已置顶 $pinnedCount 个，' : ''}'
            '${hiddenCount > 0 ? '已隐藏 $hiddenCount 个。' : ''}',
            style: TextStyle(fontSize: 13, color: colorScheme.outline, height: 1.6),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _display.length,
            // 拖动时给浮起项加阴影与圆角，提升拖拽手感。
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final elevation = 1 + animation.value * 5;
                  return Material(
                    color: Colors.transparent,
                    elevation: elevation,
                    borderRadius: BorderRadius.circular(14),
                    shadowColor: Colors.black.withValues(alpha: 0.28),
                    child: child,
                  );
                },
                child: child,
              );
            },
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _display.removeAt(oldIndex);
                _display.insert(newIndex, item);
                _dirty = true;
                _syncPrefs();
              });
            },
            itemBuilder: (context, index) {
              final category = _display[index];
              final pinned = _prefs.isPinned(category.id);
              final hidden = _prefs.isHidden(category.id);
              return Opacity(
                key: ValueKey(category.id),
                opacity: hidden ? 0.45 : 1,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                    leading: pinned
                        ? CircleAvatar(
                            backgroundColor: colorScheme.primary,
                            child: Icon(Icons.push_pin,
                                size: 18, color: colorScheme.onPrimary),
                          )
                        : CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                    title: Text(
                      category.name,
                      style: TextStyle(
                        decoration: hidden ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      hidden
                          ? '${category.count} 篇文章 · 已隐藏'
                          : '${category.count} 篇文章',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: pinned ? '取消置顶' : '置顶',
                          icon: Icon(
                            pinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 20,
                            color: pinned ? colorScheme.primary : null,
                          ),
                          onPressed: () => _togglePin(category.id),
                        ),
                        IconButton(
                          tooltip: hidden ? '恢复显示' : '隐藏',
                          icon: Icon(
                            hidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: hidden ? colorScheme.error : null,
                          ),
                          onPressed: () => _toggleHidden(category.id),
                        ),
                        // 长按手柄拖动；单击「移到最前」作为快捷操作。
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: Icon(Icons.drag_handle_outlined),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          onSelected: (value) {
                            if (value == 'top') _moveToTop(category.id);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'top',
                              child: Text('移到最前'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
