// 生成 database/03_demo_data.sql（口令散列算法必须与后端 AuthService 一致：
// sha256(salt + password) 十六进制，库内存储格式 `salt:hash`）。
//
// 用法：dart run tool/generate_demo_data.dart > ../database/03_demo_data.sql
import 'dart:convert';

import 'package:crypto/crypto.dart';

String stored(String saltHex, String password) =>
    '$saltHex:${sha256.convert(utf8.encode('$saltHex$password'))}';

void main() {
  const demoUsers = [
    ('admin', 'Admin@123', '系统管理员', 'ADMIN', '13800000001',
        '0a1b2c3d4e5f6071'),
    ('doctor01', 'Doctor@123', '王心怡', 'DOCTOR', '13900000111',
        '1a2b3c4d5e6f7081'),
    ('teacher01', 'Teacher@123', '李晓芳', 'TEACHER', '13700000222',
        '2b3c4d5e6f708192'),
    ('parent01', 'Parent@123', '张浩然', 'PARENT', '13600000333',
        '3c4d5e6f70819203'),
  ];

  print('-- AiCMHCS 演示数据（由 backend/tool/generate_demo_data.dart 生成，请勿手工编辑）');
  print('-- 演示账号：');
  for (final (u, p, _, _, _, _) in demoUsers) {
    print('--   $u / $p');
  }
  for (final (username, password, realName, role, phone, salt) in demoUsers) {
    final pwd = stored(salt, password);
    print("INSERT INTO SYS_USER "
        "(USERNAME, PASSWORD, REAL_NAME, ROLE_CODE, PHONE, STATUS) VALUES "
        "('$username', '$pwd', '$realName', '$role', '$phone', 1);");
  }
  print('COMMIT;');
}
