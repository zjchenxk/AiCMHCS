import 'dart:convert';

import 'package:server/utils/log_sanitizer.dart';
import 'package:test/test.dart';

/// 测试便捷：脱敏并还原为 Map（测试入参均为非空 Map，脱敏不改结构）。
Map<String, dynamic> sanitize(Map<String, dynamic> value) => redactSensitive(value)! as Map<String, dynamic>;

void main() {
  test('顶层敏感键脱敏（口令与手机号）', () {
    final out = sanitize({
      'usercode': 'admin',
      'password': 'Admin@123',
      'phone': '13800000000',
    });
    expect(out['usercode'], 'admin');
    expect(out['password'], '***');
    expect(out['phone'], '***');
  });

  test('键名大小写不敏感', () {
    final out = sanitize({
      'Password': 'x',
      'newPassword': 'y',
      'OLDPASSWORD': 'z',
      'Mobile': 'm',
    });
    expect(out['Password'], '***');
    expect(out['newPassword'], '***');
    expect(out['OLDPASSWORD'], '***');
    expect(out['Mobile'], '***');
  });

  test('嵌套 Map 与 List 递归脱敏', () {
    final out = sanitize({
      'name': '张三',
      'profile': {
        'phone': '13800000000',
        'address': '北京市',
        'contacts': [
          {'phone': '13900000000', 'relation': '父'},
          {'relation': '母'},
        ],
      },
    });
    final profile = out['profile'] as Map<String, dynamic>;
    expect(profile['phone'], '***');
    expect(profile['address'], '北京市');
    final contacts = profile['contacts'] as List;
    expect((contacts[0] as Map)['phone'], '***');
    expect((contacts[0] as Map)['relation'], '父');
    expect((contacts[1] as Map)['relation'], '母');
  });

  test('非敏感标量原样保留（含 null/数字/布尔）', () {
    final out = sanitize({
      'code': '110000',
      'count': 3,
      'enabled': true,
      'remark': null,
    });
    expect(out['code'], '110000');
    expect(out['count'], 3);
    expect(out['enabled'], true);
    expect(out['remark'], isNull);
  });

  test('encodeForLog 输出合法 JSON 且敏感值已脱敏', () {
    final text = encodeForLog({
      'usercode': 'admin',
      'password': 'Admin@123',
      'nested': {'phone': '13800000000'},
    });
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    expect(decoded['password'], '***');
    expect((decoded['nested'] as Map)['phone'], '***');
    expect(text, isNot(contains('Admin@123')));
    expect(text, isNot(contains('13800000000')));
  });
}
