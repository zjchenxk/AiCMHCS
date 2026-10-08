import 'package:aicmhcs_server/services/auth_service.dart';
import 'package:test/test.dart';

void main() {
  group('口令散列', () {
    test('同一盐与口令散列结果一致', () {
      final h1 = AuthService.hashPassword('a1b2c3d4', 'Admin@123');
      final h2 = AuthService.hashPassword('a1b2c3d4', 'Admin@123');
      expect(h1, h2);
      expect(h1, hasLength(64));
    });

    test('不同盐或口令散列结果不同', () {
      final h1 = AuthService.hashPassword('a1b2c3d4', 'Admin@123');
      expect(h1, isNot(AuthService.hashPassword('ffff0000', 'Admin@123')));
      expect(h1, isNot(AuthService.hashPassword('a1b2c3d4', 'Admin@124')));
    });

    test('存储格式为 salt:hash 且可校验', () {
      final stored = AuthService.makeStoredPassword('Doctor@123');
      expect(stored.contains(':'), isTrue);
      expect(AuthService.verifyStoredPassword(stored, 'Doctor@123'), isTrue);
      expect(AuthService.verifyStoredPassword(stored, 'wrong'), isFalse);
    });

    test('损坏的存储串返回校验失败', () {
      expect(AuthService.verifyStoredPassword('not-a-valid-entry', 'x'), isFalse);
    });
  });

  group('令牌生成', () {
    test('令牌互不相同且为十六进制', () {
      final t1 = AuthService.makeSalt();
      final t2 = AuthService.makeSalt();
      expect(t1, isNot(t2));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(t1), isTrue);
    });
  });
}
