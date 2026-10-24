import 'dart:io';

import 'package:server/utils/admin_division_importer.dart';

/// 测试专用行政区划数据源：写入小份临时 CSV 并注入导入器路径解析，
/// 使全量迁移（v3 seed）不依赖 assets 下的真实数据文件——后者可能是
/// 数十万行级大文件或处于待替换状态，不适合单元测试。
///
/// 内容与 assets/divisions/divisions.csv 示例保持一致（手工同步）。
/// 用法：setUp 中 `final divisionsDir = setUpTestDivisionsCsv();`，
/// tearDown 中 `clearTestDivisionsCsv(divisionsDir);`。
String setUpTestDivisionsCsv() {
  const rows = <String>[
    'CODE,NAME,PARENT_CODE',
    '110000,北京市,',
    '110100,北京市,110000',
    '110101,东城区,110100',
    '110101001,东华门街道,110101',
    '110101001001,多福巷社区,110101001',
    '110101001002,银闸社区,110101001',
    '110102,西城区,110100',
    '120000,天津市,',
    '120100,天津市,120000',
    '120101,和平区,120100',
    '130000,河北省,',
    '130100,石家庄市,130000',
    '130102,长安区,130100',
    '140000,山西省,',
    '440000,广东省,',
    '440100,广州市,440000',
    '440103,荔湾区,440100',
  ];
  final dir = Directory.systemTemp.createTempSync('test_divisions');
  final csv = File('${dir.path}${Platform.pathSeparator}divisions.csv')..writeAsStringSync('${rows.join('\n')}\n');
  divisionsCsvOverrideForTest = csv.path;
  return dir.path;
}

/// 清理测试数据注入与临时文件（与 [setUpTestDivisionsCsv] 配对）。
void clearTestDivisionsCsv(String dirPath) {
  divisionsCsvOverrideForTest = null;
  Directory(dirPath).deleteSync(recursive: true);
}
