import 'package:server/database/engine/dm/dm_param_rewrite.dart';
import 'package:test/test.dart';

void main() {
  test('ASCII 参数保持绑定', () {
    final (sql, params) = rewriteDmParams(
      'SELECT * FROM T WHERE A = ? AND B = ?',
      ['admin', 18],
    );
    expect(sql, 'SELECT * FROM T WHERE A = ? AND B = ?');
    expect(params, ['admin', 18]);
  });

  test('空参数原样返回', () {
    final (sql, params) = rewriteDmParams('SELECT 1 FROM T', const []);
    expect(sql, 'SELECT 1 FROM T');
    expect(params, isEmpty);
  });

  test('null 参数保持占位符走绑定指示器', () {
    final (sql, params) = rewriteDmParams('INSERT INTO T (A) VALUES (?)', [
      null,
    ]);
    expect(sql, 'INSERT INTO T (A) VALUES (?)');
    expect(params, [isNull]);
  });

  test('含中文的参数内联为字面量', () {
    final (sql, params) = rewriteDmParams(
      'INSERT INTO T (NAME) VALUES (?)',
      ['王小明'],
    );
    expect(sql, "INSERT INTO T (NAME) VALUES ('王小明')");
    expect(params, isEmpty);
  });

  test('内联时单引号翻倍转义', () {
    final (sql, params) = rewriteDmParams(
      'INSERT INTO T (NAME) VALUES (?)',
      ["张'三"],
    );
    expect(sql, "INSERT INTO T (NAME) VALUES ('张''三')");
    expect(params, isEmpty);
  });

  test('混合参数：ASCII 绑定、非 ASCII 内联，顺序保持', () {
    final (sql, params) = rewriteDmParams(
      'UPDATE T SET NAME = ?, AGE = ? WHERE CODE = ?',
      ['王小明', 18, 'admin'],
    );
    expect(sql, "UPDATE T SET NAME = '王小明', AGE = ? WHERE CODE = ?");
    expect(params, [18, 'admin']);
  });

  test('字符串字面量中的问号不消费参数', () {
    final (sql, params) = rewriteDmParams(
      "SELECT * FROM T WHERE A = 'a?b' AND B = ?",
      ['中文'],
    );
    expect(sql, "SELECT * FROM T WHERE A = 'a?b' AND B = '中文'");
    expect(params, isEmpty);
  });

  test('字面量内的转义单引号正确跳过', () {
    final (sql, params) = rewriteDmParams(
      "SELECT * FROM T WHERE A = 'it''s ?' AND B = ?",
      ['中文'],
    );
    expect(sql, "SELECT * FROM T WHERE A = 'it''s ?' AND B = '中文'");
    expect(params, isEmpty);
  });
}
