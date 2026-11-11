// 临时演示脚本：写入冒烟用户 / 查询登录审计 IP（验证完删除）。
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/auth_service.dart';

Future<void> main(List<String> args) async {
  final db = await SqliteGateway.start('data/smoke_roles.db');
  if (args.isEmpty) {
    await db.execute(
      'INSERT INTO SYS_USER '
      '(USER_CODE, PASSWORD, USER_NAME, USER_TYPE, STATUS) '
      'VALUES (?, ?, ?, ?, 1)',
      ['roleuser', AuthService.makeStoredPassword('Admin@123'), '冒烟用户', 'ADMIN'],
    );
    print('冒烟种子写入完成');
  } else {
    final logs = await db.query('SELECT LOGIN_IP, LOGIN_RESULT FROM SYS_LOGIN_LOG');
    for (final row in logs.rowsAsMaps) {
      print('LOGIN_IP=${row['LOGIN_IP']} | ${row['LOGIN_RESULT']}');
    }
  }
  db.close();
}
