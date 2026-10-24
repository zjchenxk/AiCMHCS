import 'dart:convert';
import 'dart:io';

import 'package:server/database/engine/database_gateway.dart';

/// 行政区划基础数据导入器。
///
/// 数据本体在资源文件 `assets/divisions/` 下（UTF-8、首行表头、三列
/// `CODE,NAME,PARENT_CODE`、省级 PARENT_CODE 留空），不内联进迁移代码
/// ——70 万行级数据写进 Dart 源码会让分析器与版本库失去可维护性，且
/// 国标区划每年更新，只需替换数据文件。真实数据建议以 gzip 压缩存放
/// （`divisions.csv.gz`，约 27MB 压至 7MB 左右，利于工作区检出与单机版
/// 交付包），读取按文件魔数自动识别压缩格式，明文 `divisions.csv`
/// 同样支持（示例数据与手工调试用）。
///
/// 导入为全量替换：先清空 BASE_ADMIN_DIVISIONS，再分批 multi-row INSERT
/// （每批一条语句即一个事务，两库均无需显式事务包裹）。中断后重跑会
/// 重新清空重来，幂等且不残留半途数据。达梦侧 NAME 为中文，由网关参数
/// 改写自动转义内联进 SQL 文本，批大小由此（单条语句长度）与网络往返
/// 次数共同权衡，取 500。

/// 行政区划数据文件候选路径（同一目录下压缩版优先于明文版；不同启动
/// 方式的 cwd 差异，依次尝试）。
const divisionsCsvCandidates = <String>[
  // cwd 为 server/ 或 server/build/：dart_frog dev、dart run tool/、直接运行 build 产物。
  'assets/divisions/divisions.csv.gz',
  'assets/divisions/divisions.csv',
  // cwd 为仓库根：VS Code F5 调试 build/bin/server.dart（launch.json 未设 cwd）。
  'server/assets/divisions/divisions.csv.gz',
  'server/assets/divisions/divisions.csv',
];

/// 数据文件路径的测试注入点（仅供测试覆写，优先级最高；生产环境不设）。
String? divisionsCsvOverrideForTest;

/// 定位行政区划数据文件，找不到时抛出列出候选路径的错误。
///
/// 解析优先级：测试注入 → 环境变量 `AICMHCS_DIVISIONS_CSV`（数据文件
/// 不随包分发、放别处的部署场景）→ 候选路径列表。
String resolveDivisionsCsvPath() {
  final injected = divisionsCsvOverrideForTest;
  if (injected != null) return injected;
  final fromEnv = Platform.environment['AICMHCS_DIVISIONS_CSV'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    if (!File(fromEnv).existsSync()) {
      throw StateError('AICMHCS_DIVISIONS_CSV 指向的文件不存在: $fromEnv');
    }
    return fromEnv;
  }
  for (final path in divisionsCsvCandidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError(
    '未找到行政区划数据文件，已尝试：${divisionsCsvCandidates.join('、')}'
    '（当前目录 ${Directory.current.path}）',
  );
}

/// 打开数据文件字节流，gzip 魔数（1F 8B）开头时自动挂解压转换。
Stream<List<int>> _openDataBytes(File file) {
  final handle = file.openSync();
  final List<int> magic;
  try {
    magic = handle.lengthSync() >= 2 ? handle.readSync(2) : const <int>[];
  } finally {
    handle.closeSync();
  }
  final bytes = file.openRead();
  final isGzip = magic.length == 2 && magic[0] == 0x1F && magic[1] == 0x8B;
  return isGzip ? bytes.transform(gzip.decoder) : bytes;
}

/// 单个数据行的解析结果。
typedef DivisionRow = (String code, String name, String? parentCode);

/// 解析单行数据（三列 `CODE,NAME,PARENT_CODE`，省级 PARENT_CODE 留空转
/// NULL），格式非法时抛 [FormatException]（错误信息带行号）。
DivisionRow _parseDivisionLine(String line, int lineNo) {
  final cols = line.split(',');
  if (cols.length != 3) {
    throw FormatException('行政区划数据第 $lineNo 行应为三列: $line');
  }
  final code = cols[0].trim();
  final name = cols[1].trim();
  if (code.isEmpty || name.isEmpty) {
    throw FormatException(
      '行政区划数据第 $lineNo 行 CODE/NAME 不能为空: $line',
    );
  }
  final parent = cols[2].trim();
  return (code, name, parent.isEmpty ? null : parent);
}

/// CODE 合法格式：2~12 位纯数字。数据源位数体系不统一——国标全码为
/// 6（省/市/县）/9（乡）/12（村）位，亦有最短码体系（省 2 / 市 4 /
/// 县 6 / 乡 9 位，逐级去尾零），只要父引用自洽即可建树，主键唯一性
/// 才是硬约束（由重复校验与表主键共同保证）。
final RegExp _codePattern = RegExp(r'^\d{2,12}$');

/// 写库前预检数据文件：CODE 格式与重复校验。
///
/// 在清空/写入任何数据之前完整扫一遍文件，校验失败时库保持原样
/// （若带病导入，重复 CODE 会在中途撞主键失败并在表里留下半途脏数据）。
/// 科学计数法 CODE（如 1.10101E+11）是 Excel 处理 12 位村级代码的典型
/// 损坏——精度已被截断、同段代码全部塌缩，**无法在导入侧补救**，
/// 必须把 CODE 列设为文本格式后重新导出数据源。
Future<void> precheckDivisionsCsv(String path) async {
  final seen = <String, int>{};
  String? firstDupCode;
  var firstDupOriginal = 0;
  var firstDupAt = 0;
  var dupCount = 0;
  var lineNo = 0;
  final lines = _openDataBytes(File(path)).transform(utf8.decoder).transform(const LineSplitter());
  await for (final raw in lines) {
    lineNo++;
    var line = raw;
    if (line.startsWith('﻿')) line = line.substring(1);
    if (line.trim().isEmpty || line.startsWith('CODE,NAME')) continue;
    final (code, _, _) = _parseDivisionLine(line, lineNo);
    if (!_codePattern.hasMatch(code)) {
      if (code.contains(RegExp('[eE]'))) {
        throw FormatException(
          '行政区划数据第 $lineNo 行 CODE「$code」为科学计数法——数据疑似经 Excel 打开后导出，12 位区划代码已被截断损坏且无法还原，请将 CODE 列设为文本格式后重新导出原始数据',
        );
      }
      throw FormatException('行政区划数据第 $lineNo 行 CODE「$code」应为 2~12 位数字');
    }
    final originalLine = seen[code];
    if (originalLine != null) {
      dupCount++;
      if (firstDupCode == null) {
        firstDupCode = code;
        firstDupOriginal = originalLine;
        firstDupAt = lineNo;
      }
    } else {
      seen[code] = lineNo;
    }
  }
  if (firstDupCode != null) {
    throw FormatException(
      '行政区划数据存在重复 CODE（共 $dupCount 行重复），首个「$firstDupCode」首现于第 $firstDupOriginal 行、重复于第 $firstDupAt 行，请检查数据源是否拼接了多份文件或被 Excel 改写',
    );
  }
}

/// 全量重灌行政区划表 BASE_ADMIN_DIVISIONS，返回导入行数。
///
///param db: 数据库网关。
///param onProgress: 每批写入完成后的进度回调（参数为累计导入行数）。
///param csvPath: 数据文件路径，缺省经 [resolveDivisionsCsvPath] 定位；
///测试可注入临时文件。
Future<int> importAdminDivisions(DatabaseGateway db, {void Function(int imported)? onProgress, String? csvPath}) async {
  final path = csvPath ?? resolveDivisionsCsvPath();
  await precheckDivisionsCsv(path);
  await db.execute('DELETE FROM BASE_ADMIN_DIVISIONS');

  const batchSize = 500;
  final batch = <List<Object?>>[];
  var imported = 0;
  var lineNo = 0;

  Future<void> flush() async {
    if (batch.isEmpty) return;
    final sql = StringBuffer(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES ',
    );
    for (var i = 0; i < batch.length; i++) {
      sql.write(i == 0 ? '(?, ?, ?)' : ', (?, ?, ?)');
    }
    await db.execute(sql.toString(), [for (final row in batch) ...row]);
    imported += batch.length;
    batch.clear();
    onProgress?.call(imported);
  }

  final lines = _openDataBytes(File(path)).transform(utf8.decoder).transform(const LineSplitter());
  await for (final raw in lines) {
    lineNo++;
    var line = raw;
    if (line.startsWith('﻿')) line = line.substring(1);
    if (line.trim().isEmpty || line.startsWith('CODE,NAME')) continue;
    final (code, name, parent) = _parseDivisionLine(line, lineNo);
    batch.add([code, name, parent]);
    if (batch.length >= batchSize) await flush();
  }
  await flush();
  return imported;
}
