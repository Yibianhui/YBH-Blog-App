import 'package:flutter_test/flutter_test.dart';
import 'package:yibianhui_blog/src/data/category_order.dart';

/// 测试分类顺序合并逻辑（纯函数，不依赖平台/存储）。
void main() {
  // 用一个简单的包装类型充当 BlogCategory 以隔离数据层。
  (int id, String name) cat(int id, String name) => (id, name);

  int idOf((int, String) c) => c.$1;

  test('order 为 null/空时保持服务器原顺序', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    expect(
      CategoryOrderStore.applyOrderWith(categories: server, idOf: idOf, order: null),
      equals(server),
    );
    expect(
      CategoryOrderStore.applyOrderWith(categories: server, idOf: idOf, order: const []),
      equals(server),
    );
  });

  test('按自定义顺序重排，且保留服务器仍有记录的分类', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [3, 1, 2],
    );
    expect(ordered.map(idOf).toList(), equals([3, 1, 2]));
  });

  test('服务器已删除的分类被忽略，新分类追加到末尾（保持服务器顺序）', () {
    // 本地保存顺序 [3, 1, 2]，但服务器现在返回 [1, 2, 4, 5]（3 被删，4/5 新增）。
    final server = [cat(1, 'A'), cat(2, 'B'), cat(4, 'D'), cat(5, 'E')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [3, 1, 2],
    );
    // 3 已不存在 -> 忽略；1,2 按记录在前；4,5 新出现追加到末尾。
    expect(ordered.map(idOf).toList(), equals([1, 2, 4, 5]));
  });

  test('自定义顺序中含有服务器不存在的 id 不会报错', () {
    final server = [cat(10, 'X')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [99, 10, 100],
    );
    expect(ordered.map(idOf).toList(), equals([10]));
  });

  test('置顶分类排在最前，优先于自定义顺序', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2, 3],
      pinned: const [3],
    );
    expect(ordered.map(idOf).toList(), equals([3, 1, 2]));
  });

  test('多个置顶分类按 pinned 列表顺序排列', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C'), cat(4, 'D')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2, 3, 4],
      pinned: const [4, 2],
    );
    expect(ordered.map(idOf).toList(), equals([4, 2, 1, 3]));
  });

  test('excludeHidden 为真时剔除隐藏分类', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2, 3],
      hidden: const [2],
      excludeHidden: true,
    );
    expect(ordered.map(idOf).toList(), equals([1, 3]));
  });

  test('excludeHidden 为假时保留隐藏分类（排序页需要展示以便恢复）', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2, 3],
      hidden: const [2],
      excludeHidden: false,
    );
    expect(ordered.map(idOf).toList(), equals([1, 2, 3]));
  });

  test('隐藏优先于置顶：同时置顶与隐藏的分类不显示', () {
    // 隐藏是更强的意图；UI 层在置顶时会自动取消隐藏，两者实际互斥，
    // 这里仅约定合并函数在状态残留（旧数据）时的行为。
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2, 3],
      pinned: const [2],
      hidden: const [2],
      excludeHidden: true,
    );
    expect(ordered.map(idOf).toList(), equals([1, 3]));
  });

  test('置顶分类先于自定义顺序，且不重复出现', () {
    final server = [cat(1, 'A'), cat(2, 'B'), cat(3, 'C')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      // 自定义顺序里也写了 3（与 pinned 重复），结果中 3 只应出现一次。
      order: const [1, 3, 2],
      pinned: const [3],
    );
    expect(ordered.map(idOf).toList(), equals([3, 1, 2]));
  });

  test('全部隐藏时结果为空', () {
    final server = [cat(1, 'A'), cat(2, 'B')];
    final ordered = CategoryOrderStore.applyOrderWith(
      categories: server,
      idOf: idOf,
      order: const [1, 2],
      hidden: const [1, 2],
      excludeHidden: true,
    );
    expect(ordered, isEmpty);
  });

  test('CategoryPrefs 为空时视为未设置', () {
    expect(const CategoryPrefs().isEmpty, isTrue);
    expect(const CategoryPrefs(order: [1]).isEmpty, isFalse);
    expect(const CategoryPrefs(pinned: {1}).isEmpty, isFalse);
    expect(const CategoryPrefs(hidden: {1}).isEmpty, isFalse);
  });

  test('CategoryPrefs.copyWith 只覆盖传入字段', () {
    const prefs = CategoryPrefs(order: [1, 2], pinned: {1}, hidden: {3});
    final next = prefs.copyWith(hidden: const {});
    expect(next.order, equals([1, 2]));
    expect(next.pinned, equals({1}));
    expect(next.hidden, isEmpty);
  });
}
