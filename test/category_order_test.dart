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
}
