// 结构迁移注册表（建表、加列等全部结构变更在此按版本维护，双方言）。
//
// 铁律：
// 1. 已发布的迁移不可修改，只能向后追加新版本（版本号严格递增）；
// 2. 迁移里不要写 DROP TABLE IF EXISTS——对升级用户而言那是数据丢失，
//    开发期推倒重来：达梦库执行 ./tools/init_db.sh 重建应用模式，
//    单机版直接删除数据文件；
// 3. 演示/测试数据不写进迁移（生产环境不得自动长出演示账号），
//    见 tool/seed_demo_data.dart；生产必需的基础字典数据（如行政区划）
//    用 seed 回调随迁移加载，数据本体放资源文件不内联进代码；
// 4. 通用语句放 common，方言专属（COMMENT ON、类型差异）放 dm/sqlite；
// 5. SQLite 无 COMMENT ON，注释以 `--` 形式附在语句内；
// 6. 语句表达不了的数据订正（如存量明文字段加密）用 dataFix 回调，
//    密钥经 SchemaMigrator 注入，回调必须幂等（中断重跑不重复处理）。
import 'package:server/database/migrator/migrations/base/migration.dart';
import 'package:server/database/migrator/migrations/migration_202610212021.dart';
import 'package:server/database/migrator/migrations/migration_202610231703.dart';
import 'package:server/database/migrator/migrations/migration_202610241630.dart';
import 'package:server/database/migrator/migrations/migration_202610251100.dart';

/// 结构迁移注册表：按版本号严格递增，已发布的迁移不可修改，只能追加新版本。
const dbMigrations = <DbMigration>[
  dbMigration_202610212021,
  dbMigration_202610231703,
  dbMigration_202610241630,
  dbMigration_202610251100,
];
