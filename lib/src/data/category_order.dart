import 'package:shared_preferences/shared_preferences.dart';

/// 分类显示偏好的本地持久化与合并。
///
/// 文章分类本身由 [BlogApi.fetchCategories] 联网拉取（WordPress REST API）。
/// 用户可在「分类排序」页自定义「文章」页分类筛选条的展示方式，本类负责把
/// 这些偏好保存到本地，并在联网结果之上套用：
///   - [CategoryPrefs.pinned]：置顶分类，始终排在最前；
///   - [CategoryPrefs.order]：其余分类的自定义顺序；
///   - [CategoryPrefs.hidden]：隐藏分类，默认不出现在筛选条中（可在排序页恢复）；
///   - 服务器新增、本地没有记录的分类追加到末尾；
///   - 服务器已删除（拉取不到）的分类自动忽略。
class CategoryPrefs {
  const CategoryPrefs({
    this.order = const <int>[],
    this.pinned = const <int>{},
    this.hidden = const <int>{},
  });

  /// 自定义顺序（分类 id 列表）。
  final List<int> order;

  /// 置顶的分类 id。
  final Set<int> pinned;

  /// 隐藏的分类 id。
  final Set<int> hidden;

  bool get isEmpty => order.isEmpty && pinned.isEmpty && hidden.isEmpty;

  CategoryPrefs copyWith({
    List<int>? order,
    Set<int>? pinned,
    Set<int>? hidden,
  }) {
    return CategoryPrefs(
      order: order ?? this.order,
      pinned: pinned ?? this.pinned,
      hidden: hidden ?? this.hidden,
    );
  }

  bool isPinned(int id) => pinned.contains(id);

  bool isHidden(int id) => hidden.contains(id);
}

/// 分类显示偏好的本地持久化与合并。
abstract final class CategoryOrderStore {
  static const String _prefsKey = 'ybh_category_order';
  static const String _pinnedKey = 'ybh_category_pinned';
  static const String _hiddenKey = 'ybh_category_hidden';

  /// 读取用户保存的完整偏好（顺序 / 置顶 / 隐藏）。
  static Future<CategoryPrefs> load() async {
    final prefs = await _prefs();
    if (prefs == null) return const CategoryPrefs();
    return CategoryPrefs(
      order: _readIntList(prefs, _prefsKey),
      pinned: _readIntList(prefs, _pinnedKey).toSet(),
      hidden: _readIntList(prefs, _hiddenKey).toSet(),
    );
  }

  /// 保存用户自定义的完整偏好。
  static Future<bool> save(CategoryPrefs prefs) async {
    final store = await _prefs();
    if (store == null) return false;
    try {
      await Future.wait(<Future<void>>[
        store.setStringList(_prefsKey, prefs.order.map((e) => '$e').toList()),
        store.setStringList(_pinnedKey, prefs.pinned.map((e) => '$e').toList()),
        store.setStringList(_hiddenKey, prefs.hidden.map((e) => '$e').toList()),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清除所有自定义偏好（恢复服务器默认的按文章数排序）。
  static Future<bool> clear() async {
    final prefs = await _prefs();
    if (prefs == null) return false;
    try {
      await Future.wait(<Future<void>>[
        prefs.remove(_prefsKey),
        prefs.remove(_pinnedKey),
        prefs.remove(_hiddenKey),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // 兼容旧 API：仅处理顺序列表。
  // ------------------------------------------------------------------

  /// 读取用户保存的分类 id 顺序（可能为 null，表示从未设置过）。
  static Future<List<int>?> loadOrder() async {
    final prefs = await load();
    return prefs.order.isEmpty ? null : prefs.order;
  }

  /// 保存用户自定义的分类 id 顺序（保留已存在的置顶/隐藏设置）。
  static Future<bool> saveOrder(List<int> order) async {
    final current = await load();
    return save(current.copyWith(order: order));
  }

  /// 清除自定义顺序（恢复服务器默认排序）。
  static Future<bool> clearOrder() => clear();

  // ------------------------------------------------------------------
  // 合并逻辑（纯函数，便于单测）
  // ------------------------------------------------------------------

  /// 把联网拉取到的分类，按用户保存的顺序重新排列。
  ///
  /// [categories] 为服务器返回（已按文章数降序）。若用户从未设置过顺序，
  /// 或自定义列表为空，则原样返回（保持服务器默认排序）。
  static List<T> applyOrder<T>({
    required List<T> categories,
    required int Function(T) idOf,
  }) {
    return applyOrderWith(categories: categories, idOf: idOf, order: null);
  }

  /// 同 [applyOrder]，但显式接受已读取的顺序 / 置顶 / 隐藏设置。
  ///
  /// 排列优先级：置顶 → 自定义顺序 → 服务器原顺序。
  /// 当 [excludeHidden] 为 true 时，[hidden] 中的分类不会出现在结果里
  /// （用于「文章」页筛选条）；为 false 时保留但排在其原本位置
  /// （用于「分类排序」页，用户需要看到它们才能恢复显示）。
  static List<T> applyOrderWith<T>({
    required List<T> categories,
    required int Function(T) idOf,
    required List<int>? order,
    List<int>? pinned,
    List<int>? hidden,
    bool excludeHidden = false,
  }) {
    final pinnedSet = pinned?.toSet() ?? const <int>{};
    final hiddenSet = hidden?.toSet() ?? const <int>{};

    final byId = <int, T>{};
    for (final c in categories) {
      byId[idOf(c)] = c;
    }

    final result = <T>[];
    final used = <int>{};

    void take(int id) {
      if (used.contains(id)) return;
      final c = byId[id];
      if (c == null) return;
      if (excludeHidden && hiddenSet.contains(id)) return;
      used.add(id);
      result.add(c);
    }

    // 1) 置顶分类在最前。
    //    注：若某分类同时被置顶与隐藏，以「隐藏」为准——隐藏是更强的意图。
    //    UI 层（category_order_page）在置顶时会自动取消隐藏，两者互斥。
    for (final id in pinnedSet) {
      take(id);
    }
    // 2) 用户自定义顺序。
    if (order != null) {
      for (final id in order) {
        take(id);
      }
    }
    // 3) 其余分类（新出现 / 未记录）保持服务器原顺序追加到末尾。
    for (final c in categories) {
      take(idOf(c));
    }
    return result;
  }

  // ------------------------------------------------------------------
  // 内部工具
  // ------------------------------------------------------------------

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static List<int> _readIntList(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key);
    if (raw == null || raw.isEmpty) return const <int>[];
    return raw
        .where((e) => e.isNotEmpty)
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
  }
}
