/// 达梦参数改写：DPI 绑定参数（dpi_bind_param 无宽字符版本）按本地码页
/// 编码，仅支持 ASCII 值。含非 ASCII 的参数改写为单引号翻倍转义的
/// SQL 字面量直接内联（经 W 路径执行，中文无乱码），其余参数照常绑定。
///
/// 返回 (改写后的 SQL, 实际需绑定的参数)。
(String, List<Object?>) rewriteDmParams(String sql, List<Object?> params) {
  if (params.isEmpty) return (sql, params);

  final bound = <Object?>[];
  final out = StringBuffer();
  var paramIndex = 0;
  var inString = false;
  var i = 0;
  while (i < sql.length) {
    final ch = sql[i];
    if (inString) {
      out.write(ch);
      if (ch == "'") {
        // 字符串字面量内的 '' 是转义单引号，不属于结束定界符。
        if (i + 1 < sql.length && sql[i + 1] == "'") {
          out.write("'");
          i++;
        } else {
          inString = false;
        }
      }
    } else if (ch == "'") {
      out.write(ch);
      inString = true;
    } else if (ch == '?' && paramIndex < params.length) {
      final value = params[paramIndex++];
      if (value == null) {
        // null 走绑定指示器路径，无需编码。
        bound.add(null);
        out.write('?');
      } else {
        final text = value is String ? value : value.toString();
        if (isAscii(text)) {
          bound.add(value);
          out.write('?');
        } else {
          out.write("'${text.replaceAll("'", "''")}'");
        }
      }
    } else {
      out.write(ch);
    }
    i++;
  }
  return (out.toString(), bound);
}

/// 是否为纯 ASCII 文本。
bool isAscii(String s) {
  for (final code in s.codeUnits) {
    if (code >= 128) return false;
  }
  return true;
}
