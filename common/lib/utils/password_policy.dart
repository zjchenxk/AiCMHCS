/// 等保三级口令复杂度策略：前后端共用的口令校验规则与文案。
///
/// 服务端经 `PasswordPolicy.complexityError` 做兜底校验（防绕过前端直调
/// 接口），客户端表单同规则即时提示；修改密码场景用更强的
/// `quickError` / `strongError`。规则或文案调整只改本文件，两端自动同步。
final class PasswordPolicy {
  PasswordPolicy._();

  /// 口令最小长度（等保三级复杂度要求）。
  static const int minLength = 8;

  /// 口令最大长度（等保三级复杂度要求）。
  static const int maxLength = 32;

  /// 口令复杂度校验（等保三级，用户表单 / 服务端兜底同规则同文案）：
  /// 去空格、非空、8-32 位、不得与登录账号相同、须包含大写字母 /
  /// 小写字母 / 数字 / 特殊字符中的至少三类。
  ///returns: 校验失败返回错误提示文本，通过返回 null
  static String? complexityError(String password, {String userCode = ''}) {
    final v = password.trim();
    if (v.isEmpty) {
      return '密码不能为空';
    }
    if (v.length < minLength || v.length > maxLength) {
      return '密码长度须在 $minLength-$maxLength 位之间';
    }
    if (userCode.trim().isNotEmpty && v == userCode.trim()) {
      return '密码不能与登录账号相同';
    }
    // 特殊字符按「非字母数字」计（宽松口径，与服务端历史规则一致）
    var complexityKinds = 0;
    if (RegExp(r'[A-Z]').hasMatch(v)) complexityKinds++;
    if (RegExp(r'[a-z]').hasMatch(v)) complexityKinds++;
    if (RegExp(r'[0-9]').hasMatch(v)) complexityKinds++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(v)) complexityKinds++;
    if (complexityKinds < 3) {
      return '密码复杂度不足：须包含大写字母、小写字母、数字、特殊字符中的至少三类';
    }
    return null;
  }

  /// 修改密码对话框新密码即时校验（便捷版）：非空、8-32 位、须同时
  /// 包含大写字母、小写字母、数字和特殊字符。完整校验（用户名/旧密码
  /// 比对、连续与重复字符检测）见 [strongError]，在提交时执行。
  ///returns: 校验失败返回错误提示文本，通过返回 null
  static String? quickError(String? password) {
    final v = password ?? '';
    if (v.isEmpty) return '请输入新密码';
    if (v.length < minLength) return '密码长度不能少于 $minLength 位';
    if (v.length > maxLength) return '密码长度不能超过 $maxLength 位';
    if (kinds(v) < 4) return '需包含大小写字母、数字和特殊字符';
    return null;
  }

  /// 修改密码场景三级等保强口令完整校验（提交时执行）：在 [quickError]
  /// 基础上增加不得与原密码相同、不得包含用户名、连续与重复字符检测。
  ///returns: 校验失败返回错误提示文本，通过返回 null
  static String? strongError(String password, {String username = '', String oldPassword = ''}) {
    if (password.isEmpty) return '请输入新密码';
    if (password.length < minLength) return '密码长度不能少于 $minLength 位';
    if (password.length > maxLength) return '密码长度不能超过 $maxLength 位';
    if (password == oldPassword) return '新密码不能与原密码相同';
    if (username.isNotEmpty && password.toLowerCase().contains(username.toLowerCase())) {
      return '密码不能包含用户名';
    }
    if (kinds(password) < 4) {
      return '密码必须同时包含大写字母、小写字母、数字和特殊字符';
    }

    // 连续字符检测（如 abc、123，正/逆序，长度≥3）
    for (int i = 0; i + 2 < password.length; i++) {
      final a = password.codeUnitAt(i);
      final b = password.codeUnitAt(i + 1);
      final c = password.codeUnitAt(i + 2);
      if (b == a + 1 && c == b + 1) return '密码不能包含连续字符（如 abc、123）';
      if (b == a - 1 && c == b - 1) return '密码不能包含连续字符（如 cba、321）';
    }

    // 重复字符检测（如 aaa、111，长度≥3）
    for (int i = 0; i + 2 < password.length; i++) {
      final a = password.codeUnitAt(i);
      if (password.codeUnitAt(i + 1) == a && password.codeUnitAt(i + 2) == a) {
        return '密码不能包含 3 个及以上重复字符';
      }
    }

    return null;
  }

  /// 统计口令中包含的字符类别数：大写 / 小写 / 数字 / 特殊（修改密码
  /// 场景口径，特殊字符为常见符号集）。
  static int kinds(String password) {
    return [
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[a-z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?~`€£¥§]''').hasMatch(password),
    ].where((e) => e).length;
  }
}
