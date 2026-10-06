import 'package:aicmhcs_client/models/child_info.dart';
import 'package:aicmhcs_client/models/login_user.dart';
import 'package:aicmhcs_client/views/home/home_page.dart';
import 'package:aicmhcs_client/views/system/hospital_management_page.dart';
import 'package:material_ui/material_ui.dart';

/// 统一的页面构造签名：每个功能页都能拿到当前登录用户和当前儿童
typedef MenuPageBuilder =
    Widget Function(
      BuildContext context,
      LoginUser loginUser,
      ChildInfo child,
    );

/// 路由注册表：key 与 MenuItem.route 一一对应
Map<String, MenuPageBuilder> menuRoutes = {
  '/home': _buildPage(HomePage.new),
  '/system/organ': _buildPage(HospitalManagementPage.new),
};

/// 简化注册的辅助函数（普通 function，不用 tear-off 时也可直接写 lambda）
MenuPageBuilder _buildPage(Widget Function({required LoginUser loginUser, required ChildInfo child}) ctor) {
  return (context, loginUser, child) => ctor(loginUser: loginUser, child: child);
}
