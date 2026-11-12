// 初始化数据库结构并写入演示账号（口令散列直接复用 PasswordUtil 算法、
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
import 'package:server/utils/field_cipher.dart';
import 'package:server/utils/password_helper.dart';

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

/// 演示科室：按 CODE 幂等写入，campusCode 取 demoCampuses 内代码、
/// parentCode 取同列表内代码（上级科室在前，写入顺序即依赖顺序）。
const demoDepartments = [
  ('DDEMO001', 'CDEMO001', null, '儿童保健科', '北京市东城区示例路1号门诊楼2层', '010-88886011'),
  ('DDEMO002', 'CDEMO001', null, '儿童心理科', '北京市东城区示例路1号门诊楼3层', '010-88886012'),
  ('DDEMO003', 'CDEMO001', 'DDEMO002', '儿童心理门诊', '北京市东城区示例路1号门诊楼3层', '010-88886013'),
  ('DDEMO004', 'CDEMO001', 'DDEMO002', '发育行为门诊', '北京市东城区示例路1号门诊楼3层', '010-88886014'),
  ('DDEMO005', 'CDEMO002', null, '儿童保健科', '北京市顺义区示例路2号门诊楼1层', '010-88886021'),
  ('DDEMO006', 'CDEMO003', null, '儿童心理科', '北京市东城区示例路1-1号门诊楼2层', '010-88886031'),
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
          PasswordHelper.makeStoredPassword(password),
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
    // 演示院区：按 CODE 幂等写入，医院 ID 经上方 hospitalIds 映射取得，
    // ID 收进 campusIds 供下方演示科室挂载
    final campusIds = <String, int>{};
    for (final (code, hospCode, name, address, tel) in demoCampuses) {
      final exists = await db.query(
        'SELECT ID FROM SYS_CAMPUS WHERE CODE = ?',
        [code],
      );
      if (exists.rows.isNotEmpty) {
        campusIds[code] = int.parse(exists.rows.first[0]!);
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
      final row = await db.query(
        'SELECT ID FROM SYS_CAMPUS WHERE CODE = ?',
        [code],
      );
      campusIds[code] = int.parse(row.rows.first[0]!);
      print('  院区 $code $name 已写入');
    }
    // 演示科室：按 CODE 幂等写入，院区 ID 经上方 campusIds 映射取得、
    // 上级科室 ID 经本循环边写边存的 deptIds 映射取得（列表上级在前）
    final deptIds = <String, int>{};
    for (final (code, campusCode, parentCode, name, address, tel) in demoDepartments) {
      final exists = await db.query(
        'SELECT ID FROM SYS_DEPARTMENT WHERE CODE = ?',
        [code],
      );
      if (exists.rows.isNotEmpty) {
        deptIds[code] = int.parse(exists.rows.first[0]!);
        print('  科室 $code 已存在，跳过');
        continue;
      }
      final campus = campusIds[campusCode];
      if (campus == null) {
        print('  科室 $code 所属院区 $campusCode 不存在，跳过');
        continue;
      }
      // 按院区代码反查所属医院：演示数据院区与医院一一对应，
      // 直接在 demoCampuses 内找到该院区的医院代码
      final hospCode = demoCampuses.where((c) => c.$1 == campusCode).map((c) => c.$2).firstOrNull;
      final hosp = hospitalIds[hospCode ?? ''];
      if (hosp == null) {
        print('  科室 $code 所属医院不存在，跳过');
        continue;
      }
      final parent = parentCode == null ? null : deptIds[parentCode];
      if (parentCode != null && parent == null) {
        print('  科室 $code 上级科室 $parentCode 未写入，跳过');
        continue;
      }
      await db.execute(
        'INSERT INTO SYS_DEPARTMENT (HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, '
        'NAME, ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          hosp,
          campus,
          parent,
          code,
          name,
          address,
          tel,
          formatTimestamp(DateTime.now()),
        ],
      );
      final row = await db.query(
        'SELECT ID FROM SYS_DEPARTMENT WHERE CODE = ?',
        [code],
      );
      deptIds[code] = int.parse(row.rows.first[0]!);
      print('  科室 $code $name 已写入');
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
    // 演示账号挂载科室：未设置时按账号补挂到示例人民医院的演示科室，
    // 供用户管理页「科室→下级科室→用户」树演示（幂等，只补空值）
    const demoDeptOfUser = {
      'admin': 'DDEMO001',
      'doctor01': 'DDEMO002',
      'teacher01': 'DDEMO003',
      'parent01': 'DDEMO004',
    };
    for (final entry in demoDeptOfUser.entries) {
      final deptId = deptIds[entry.value];
      if (deptId == null) {
        print('  演示科室 ${entry.value} 不存在，${entry.key} 跳过挂载');
        continue;
      }
      await db.execute(
        'UPDATE SYS_USER SET DEPT_ID = ? WHERE USER_CODE = ? '
        'AND DEPT_ID IS NULL',
        [deptId, entry.key],
      );
    }
    print('完成。');
  } finally {
    await db.close();
  }
}
