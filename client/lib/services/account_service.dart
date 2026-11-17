import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 切换角色结果：携带新身份上下文的用户信息 + 该角色授权的菜单项目。
typedef SwitchRoleResult = ({LoginUser user, List<Menu> menus});

/// 账户与会话服务：登录后的会话级操作（切换角色等）。基于 BaseService
/// 走加密通道（登录/登录前接口的明文通道在 AuthService，勿混用）。
class AccountService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 切换当前会话的「角色-科室」授权组合：后端校验目标组合已分配给当前
  /// 登录用户并更新会话身份上下文（角色 ID/名称与科室及其院区、医院），
  /// 随响应下发新角色的授权菜单。
  ///param roleId: 目标角色 ID
  ///param deptId: 目标角色适用科室 ID（空/缺省表示存量未指定科室的哨兵组合）
  ///returns: 携带新身份上下文的用户信息与该角色授权的模块/菜单，失败抛带 message 的异常
  Future<SwitchRoleResult> switchRole(String roleId, {String? deptId}) async {
    final data = await _base.post('/api/auth/switchRole', {'role': roleId, 'deptId': ?deptId});
    final user = LoginUser.fromJson(data['user'] as Map<String, dynamic>);
    final menusJson = data['menus'] as List<dynamic>? ?? const [];
    final menus = menusJson.whereType<Map>().map((m) => Menu.fromJson(Map<String, dynamic>.from(m))).toList();
    return (user: user, menus: menus);
  }
}
