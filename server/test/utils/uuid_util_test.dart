import 'package:server/utils/uuid_util.dart';
import 'package:test/test.dart';

/// 业务主键生成器（UUID v7 + 同毫秒单调计数器）单元测试：格式、
/// 唯一性与「字符串序 = 生成序」单调性（覆盖 12 位计数器同毫秒
/// 溢出借用下一毫秒时间戳的分支）。
void main() {
  test('格式：36 位标准 UUID v7（版本位 7、合法变体位）', () {
    final id = newUuid();
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('唯一性：批量生成无重复', () {
    final ids = List.generate(1000, (_) => newUuid());
    expect(ids.toSet().length, ids.length);
  });

  test('单调性：字符串序恒等于生成序（含同毫秒计数器递增）', () {
    final ids = List.generate(20000, (_) => newUuid());
    final sorted = [...ids]..sort();
    expect(ids, sorted, reason: 'v7 时间前缀 + 同毫秒单调计数器保证字符串序即生成序');
  });
}
