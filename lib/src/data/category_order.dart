import 'package:shared_preferences/shared_preferences.dart';

/// 分类显示顺序的本地持久化与合并。
///
/// 文章分类本身由 [BlogApi.fetchCategories] 联网拉取（WordPress REST API）。
/// 用户可在「分类排序」页自定义筛选条中分类的显示顺序，本类负责把
/// 用户的自定义顺序保存到本地，并在联网结果之上套用该顺序：
///   - 自定义列表里的分类 id 按用户顺序排在前面；
///   - 服务器新增、本地没有记录的分类追加到末尾；
///   - 服务器已删除（拉取不到）的分类自动忽略。
abstract final class CategoryOrderStore {
  static const String _prefsKey = 'ybh_category_order';

  /// 读取用户保存的分类 id 顺序（可能为 null，表示从未设置过）。
  static Future<List<int>?> loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      return raw
          .where((e) => e.isNotEmpty)
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 保存用户自定义的分类 id 顺序。
  static Future<bool> saveOrder(List<int> order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        order.map((e) => e.toString()).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清除自定义顺序（恢复服务器默认排序）。
  static Future<bool> clearOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把联网拉取到的分类，按用户保存的顺序重新排列。
  ///
  /// [categories] 为服务器返回（已按文章数降序）。若用户从未设置过顺序，
  /// 或自定义列表为空，则原样返回（保持服务器默认排序）。
  static List<T> applyOrder<T>({
    required List<T> categories,
    required int Function(T) idOf,
  }) {
    // 同步读取不可靠（async），故排序函数接受外部传入的 order。
    // 这里提供一个纯函数版本：order 为 null/空时保持原样。
    return applyOrderWith(categories: categories, idOf: idOf, order: null);
  }

  /// 同 [applyOrder]，但显式接受已读取的 [order]。
  static List<T> applyOrderWith<T>({
    required List<T> categories,
    required int Function(T) idOf,
    required List<int>? order,
  }) {
    if (order == null || order.isEmpty) return categories;
    final byId = <int, T>{};
    for (final c in categories) {
      byId[idOf(c)] = c;
    }
    final result = <T>[];
    // 1) 按用户自定义顺序放入仍在服务器返回中的分类。
    for (final id in order) {
      final c = byId.remove(id);
      if (c != null) result.add(c);
    }
    // 2) 其余分类（新出现 / 未记录）保持服务器原顺序追加到末尾。
    for (final c in categories) {
      final id = idOf(c);
      if (byId.containsKey(id)) result.add(c);
    }
    return result;
  }
}
