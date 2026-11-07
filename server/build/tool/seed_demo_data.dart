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
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/database/engine/db_factory.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/field_cipher.dart';

/// 演示账号（userCode / 口令 / 姓名 / 用户类别 / 权限级别 / 手机号）。
/// TEACHER / PARENT 不在新值域内，按迁移约定原值保留待人工订正。
const demoUsers = [
  ('admin', 'Admin@123', '系统管理员', 'ADMIN', 2, '13800000001'),
  ('doctor01', 'Doctor@123', '王心怡', 'DOCTOR', 1, '13900000111'),
  ('teacher01', 'Teacher@123', '李晓芳', 'TEACHER', 0, '13700000222'),
  ('parent01', 'Parent@123', '张浩然', 'PARENT', 0, '13600000333'),
];

/// 演示医院（医联体两级）：按 CODE 幂等写入，parentCode 取同列表内代码。
const demoHospitals = [
  (
    'HDEMO001',
    null,
    '示例人民医院',
    '北京市',
    '北京市',
    '东城区',
    '示例路1号',
    '010-88886666',
  ),
  (
    'HDEMO002',
    'HDEMO001',
    '示例人民医院-儿童心理分院',
    '北京市',
    '北京市',
    '东城区',
    '示例路1-1号',
    '010-88886667',
  ),
];

/// 演示院区：按 CODE 幂等写入，hospCode 取 demoHospitals 内代码。
const demoCampuses = [
  ('CDEMO001', 'HDEMO001', '主院区', '北京市东城区示例路1号', '010-88886601'),
  ('CDEMO002', 'HDEMO001', '顺义院区', '北京市顺义区示例路2号', '010-88886602'),
  ('CDEMO003', 'HDEMO002', '东城院区', '北京市东城区示例路1-1号', '010-88886603'),
];

Future<void> main() async {
  final config = AppConfig.fromEnv();
  final db = await openDatabaseGateway(config);
  final cipher = await FieldCipher.fromConfig(config);
  try {
    final applied = await SchemaMigrator(db, fieldCipher: cipher).migrate();
    final migrated = applied.isEmpty ? '已是最新' : '已应用 ${applied.map((m) => 'v${m.version}').join('、')}';
    print('结构迁移：$migrated');
    for (final (userCode, password, userName, userType, permissionLevel, phone) in demoUsers) {
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
        '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, PERMISSION_LEVEL, '
        'PHONE, PHONE_HMAC, STATUS, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)',
        [
          userCode,
          AuthService.makeStoredPassword(password),
          userName,
          userType,
          permissionLevel,
          await cipher.seal(FieldCipher.phonePurpose, phone),
          await cipher.mac(FieldCipher.phonePurpose, phone),
          formatTimestamp(DateTime.now()),
        ],
      );
      print('  $userCode / $password 已写入');
    }
    // 演示医院：按 CODE 幂等写入，先全部落库再回填父子引用
    final hospitalIds = <String, int>{};
    for (final (code, _, name, province, city, county, address, tel) in demoHospitals) {
      final exists = await db.query(
        'SELECT ID FROM SYS_HOSPITAL WHERE CODE = ?',
        [code],
      );
      if (exists.rows.isNotEmpty) {
        hospitalIds[code] = int.parse(exists.rows.first[0]!);
        print('  医院 $code 已存在，跳过');
        continue;
      }
      await db.execute(
        'INSERT INTO SYS_HOSPITAL (PARENT_ID, CODE, NAME, PROVINCE, CITY, '
        'COUNTY, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [null, code, name, province, city, county, address, tel, formatTimestamp(DateTime.now())],
      );
      final row = await db.query(
        'SELECT ID FROM SYS_HOSPITAL WHERE CODE = ?',
        [code],
      );
      hospitalIds[code] = int.parse(row.rows.first[0]!);
      print('  医院 $code $name 已写入');
    }
    for (final (code, parentCode, _, _, _, _, _, _) in demoHospitals) {
      final parent = parentCode == null ? null : hospitalIds[parentCode];
      if (parent == null) continue;
      await db.execute(
        'UPDATE SYS_HOSPITAL SET PARENT_ID = ? WHERE CODE = ?',
        [parent, code],
      );
    }
    // 演示院区：按 CODE 幂等写入，医院 ID 经上方 hospitalIds 映射取得
    for (final (code, hospCode, name, address, tel) in demoCampuses) {
      final exists = await db.query(
        'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE CODE = ?',
        [code],
      );
      if (int.parse(exists.rowsAsMaps.first['CNT'] ?? '0') > 0) {
        print('  院区 $code 已存在，跳过');
        continue;
      }
      final hospId = hospitalIds[hospCode];
      if (hospId == null) {
        print('  院区 $code 所属医院 $hospCode 不存在，跳过');
        continue;
      }
      await db.execute(
        'INSERT INTO SYS_CAMPUS (HOSP_ID, CODE, NAME, ADDRESS, TEL, '
        'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?)',
        [hospId, code, name, address, tel, formatTimestamp(DateTime.now())],
      );
      print('  院区 $code $name 已写入');
    }
    // 演示账号归属医院：未设置时绑到示例人民医院，供院区管理等按登录
    // 用户所属医院过滤的功能演示（幂等，只补空值不覆盖既有绑定）
    final demoHospId = hospitalIds['HDEMO001'];
    if (demoHospId != null) {
      final userCodes = demoUsers.map((u) => u.$1).toList();
      final placeholders = List.filled(userCodes.length, '?').join(', ');
      await db.execute(
        'UPDATE SYS_USER SET HOSP_ID = ? WHERE USER_CODE IN ($placeholders) '
        'AND HOSP_ID IS NULL',
        [demoHospId, ...userCodes],
      );
    }
    print('完成。');
  } finally {
    await db.close();
  }
}
