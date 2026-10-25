import 'dart:convert';

/// 日志脱敏：请求入参落库前递归屏蔽敏感字段值。
///
/// 等保要求：口令、手机号等敏感个人信息不得以明文进入日志表（手机号
/// 在 SYS_USER 中由 FieldCipher 加密存储，日志表若记明文即旁路了字段
/// 加密）。匹配规则按字段名（小写比较），Map 递归、List 逐项递归。
const Set<String> _sensitiveKeys = {
  'password',
  'oldpassword',
  'newpassword',
  'passwd',
  'phone',
  'mobile',
  'idcardno',
};

///param value: 解密后的请求入参（Map/List/标量混合的任意 JSON 值）
///returns: 同结构副本，命中敏感键名的值替换为 ***
Object? redactSensitive(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key as String: _sensitiveKeys.contains((entry.key as String).toLowerCase()) ? '***' : redactSensitive(entry.value),
    };
  }
  if (value is List) {
    return [for (var i = 0; i < value.length; i++) redactSensitive(value[i])];
  }
  return value;
}

/// 脱敏后序列化为紧凑 JSON，供 LOG_CONTENT 落库。
String encodeForLog(Map<String, dynamic> json) => jsonEncode(redactSensitive(json));
