// 重灌行政区划基础数据（BASE_ADMIN_DIVISIONS，全量替换
// assets/divisions/divisions.csv 的内容）。
//
// 用法（在 server/ 目录执行）：
//   dart run tool/import_divisions.dart                                # 达梦
//   AICMHCS_DB_DRIVER=sqlite dart run tool/import_divisions.dart       # 单机版
//
// 首次执行（v3 迁移未应用）时由迁移 seed 自动导入；此后国标区划更新，
// 替换数据文件后无需新增迁移版本，再执行本工具即全量重灌。
// 连接参数与后端一致（AICMHCS_DB_HOST/PORT/USER/PASSWORD、AICMHCS_DB_FILE、
// AICMHCS_FIELD_MASTER_KEY/KEY_FILE）。
import 'package:server/app_config.dart';
import 'package:server/database/engine/db_factory.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/utils/admin_division_importer.dart';
import 'package:server/utils/field_cipher.dart';

Future<void> main() async {
  final config = AppConfig.fromEnv();
  final db = await openDatabaseGateway(config);
  final cipher = await FieldCipher.fromConfig(config);
  try {
    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final seeded = applied.where((m) => m.seed != null).toList(growable: false);
    for (final m in seeded) {
      print('结构迁移 v${m.version}：${m.description}');
      print('  行政区划基础数据已随迁移导入');
    }
    if (seeded.isEmpty) {
      print('结构已是最新，全量重灌行政区划数据…');
      final count = await importAdminDivisions(
        db,
        onProgress: (n) {
          if (n % 20000 == 0) print('  已导入 $n 行');
        },
      );
      print('行政区划重灌完成：$count 行');
    }
    print('完成。');
  } finally {
    await db.close();
  }
}
