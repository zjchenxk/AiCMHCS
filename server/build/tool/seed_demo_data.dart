// 初始化数据库结构并写入演示账号（口令散列直接复用 AuthService 算法、
// 联系电话直接复用 FieldCipher 加密，保证与后端读写逻辑一致——
// 原 generate_demo_data.dart 的两处维护已合并）。
//
// 用法（在 server/ 目录执行）：
//   dart run tool/seed_demo_data.dart                                # 达梦
//   AICMHCS_DB_DRIVER=sqlite dart run tool/seed_demo_data.dart       # 单机版
// 连接参数与后端一致（AICMHCS_DB_HOST/PORT/USER/PASSWORD、AICMHCS_DB_FILE、
// AICMHCS_FIELD_MASTER_KEY/KEY_FILE）。
import 'package:server/app_config.dart';
import 'package:server/database/engine/db_factory.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/field_cipher.dart';

const demoUsers = [
  ('admin', 'Admin@123', '系统管理员', 'ADMIN', '13800000001'),
  ('doctor01', 'Doctor@123', '王心怡', 'DOCTOR', '13900000111'),
  ('teacher01', 'Teacher@123', '李晓芳', 'TEACHER', '13700000222'),
  ('parent01', 'Parent@123', '张浩然', 'PARENT', '13600000333'),
];

Future<void> main() async {
  final config = AppConfig.fromEnv();
  final db = await openDatabaseGateway(config);
  final cipher = await FieldCipher.fromConfig(config);
  try {
    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final migrated = applied.isEmpty ? '已是最新' : '已应用 ${applied.map((m) => 'v${m.version}').join('、')}';
    print('结构迁移：$migrated');
    for (final (userCode, password, userName, role, phone) in demoUsers) {
      final exists = await db.query(
        'SELECT COUNT(*) AS CNT FROM SYS_USER WHERE USER_CODE = ?',
        [userCode],
      );
      if (int.parse(exists.rowsAsMaps.first['CNT'] ?? '0') > 0) {
        print('  $userCode 已存在，跳过');
        continue;
      }
      await db.execute(
        'INSERT INTO SYS_USER '
        '(USER_CODE, PASSWORD, USER_NAME, ROLE_CODE, PHONE, PHONE_HMAC, '
        'STATUS) VALUES (?, ?, ?, ?, ?, ?, 1)',
        [
          userCode,
          AuthService.makeStoredPassword(password),
          userName,
          role,
          await cipher.seal(FieldCipher.phonePurpose, phone),
          await cipher.mac(FieldCipher.phonePurpose, phone),
        ],
      );
      print('  $userCode / $password 已写入');
    }
    print('完成。');
  } finally {
    await db.close();
  }
}
