import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';

/// 业务主键生成器：UUID v7（48 位毫秒级 Unix 时间戳前缀 + 随机位）。
///
/// 全部业务表主键改为 CHAR(36) UUID v7 后，由应用侧在 INSERT 前生成
/// （数据库不依赖任何自增/序列机制，多进程 / 多 isolate 写入天然无冲突）。
/// v7 按创建时间单调有序：按字符串排序即近似按创建顺序（「ORDER BY ID」
/// 类查询从自增序切换为字符串序后语义保留——如拍照记录「最近一条生效」、
/// 监护人「按创建顺序」均仍按 ID 排序）。时间戳取自本机时钟，极端回拨
/// 仅影响排序近似性、不影响唯一性（低位随机数兜底）。
const _uuid = Uuid();

/// RFC 9562「monotonic random」的同毫秒单调计数器：12 位 rand_a 段承载
/// 进程内自增序号——同一毫秒内先后生成的 UUID 按字符串序严格递增（超出
/// 4096 个/毫秒时按规范借用下一毫秒时间戳）；时钟未前进（含极端回拨）
/// 时沿用上一时间戳继续计数，保证字符串序恒等于生成序。注意：单调性为
/// 进程内保证，跨进程并发写入同一毫秒时排序不再严格（该场景无业务依赖；
/// 严格跨进程时序需数据库侧序号列，当前无此需求）。
int _lastMillis = 0;
int _sequence = 0;
final Random _random = Random.secure();

/// 生成一个新的 UUID v7（标准 36 字符连字符形式，字符串序=生成序）。
String newUuid() {
  var millis = DateTime.timestamp().millisecondsSinceEpoch;
  if (millis <= _lastMillis) {
    // 时钟未前进：停留上一时间戳递增序号；序号溢出则推进到下一毫秒。
    millis = _lastMillis;
    _sequence++;
    if (_sequence > 0xFFF) {
      _sequence = 0;
      millis += 1;
    }
  } else {
    _sequence = 0;
  }
  _lastMillis = millis;
  // 随机段 10 字节 = rand_a（12 位，本实现放单调计数器）+ rand_b（62 位
  // 随机）；rand_a 低 8 位在 randomBytes[1]、高 4 位在 randomBytes[0]
  // 低半字节（高半字节为版本位，由包内覆写），与此处计数器占用段不冲突。
  final randomBytes = Uint8List(10)
    ..[0] = (_sequence >> 8) & 0x0F
    ..[1] = _sequence & 0xFF;
  for (var i = 2; i < randomBytes.length; i++) {
    randomBytes[i] = _random.nextInt(256);
  }
  return _uuid.v7(config: V7Options(millis, randomBytes));
}
