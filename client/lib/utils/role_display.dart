/// 「角色-科室」授权组合的展示/取值工具（登录页角色下拉与主界面切换
/// 角色对话框共用）。
///
/// 组合数据源为后端 `GET /api/auth/roles` 返回的
/// `[{id, roleName, deptId, deptName}]`（同一角色按科室细分授权会返回
/// 多行，deptId 为空表示存量未指定科室的哨兵组合）。下拉框以
/// 「角色ID|科室ID」复合键作值（仅用角色 ID 会重复），显示文本为
/// 「科室 角色」（科室与角色之间空格分隔；存量无科室组合只显示角色名）。
library;

/// 组合的显示文本：`科室 角色`；无科室（存量哨兵组合）时仅角色名。
String roleGrantLabel(Map<String, String> grant) {
  final deptName = grant['deptName']?.trim() ?? '';
  final roleName = grant['roleName'] ?? '';
  return deptName.isEmpty ? roleName : '$deptName $roleName';
}

/// 组合的复合键（下拉框值）：`角色ID|科室ID`，科室可为空串。
String roleGrantKey(Map<String, String> grant) => '${grant['id'] ?? ''}|${grant['deptId'] ?? ''}';

/// 从复合键拆出角色 ID 与科室 ID（兼容不含分隔符的纯角色 ID 取值）。
({String roleId, String deptId}) parseRoleGrantKey(String key) {
  final index = key.indexOf('|');
  if (index < 0) return (roleId: key, deptId: '');
  return (roleId: key.substring(0, index), deptId: key.substring(index + 1));
}
