import 'package:client/models/current_child.dart';
import 'package:client/views/child/child_create_page.dart';
import 'package:client/views/child/photo_management_page.dart';
import 'package:client/views/system/admin_division_management_page.dart';
import 'package:client/views/system/campus_management_page.dart';
import 'package:client/views/system/department_management_page.dart';
import 'package:client/views/system/dictionary_management_page.dart';
import 'package:common/model.dart';
import 'package:client/views/home/home_page.dart';
import 'package:client/views/system/hospital_management_page.dart';
import 'package:client/views/system/high_risk_factor_management_page.dart';
import 'package:client/views/system/high_risk_factor_exclusion_management_page.dart';
import 'package:client/views/system/menu_management_page.dart';
import 'package:client/views/system/role_management_page.dart';
import 'package:client/views/system/user_management_page.dart';
import 'package:material_ui/material_ui.dart';

/// 统一的页面构造签名：每个功能页都能拿到当前登录用户和当前儿童
typedef MenuPageBuilder =
    Widget Function(
      BuildContext context,
      LoginUser loginUser,
      CurrentChild child,
    );

/// 路由注册表：key 与 MenuItem.route 一一对应
Map<String, MenuPageBuilder> menuRoutes = {
  '/home': _buildPage(HomePage.new),
  '/child/create': _buildPage(ChildCreatePage.new),
  '/child/photo': _buildPage(PhotoManagementPage.new),
  '/system/hospital': _buildPage(HospitalManagementPage.new),
  '/system/campus': _buildPage(CampusManagementPage.new),
  '/system/department': _buildPage(DepartmentManagementPage.new),
  '/system/dictionary': _buildPage(DictionaryManagementPage.new),
  '/system/highRiskFactor': _buildPage(HighRiskFactorManagementPage.new),
  '/system/highRiskFactorExclusion': _buildPage(HighRiskFactorExclusionManagementPage.new),
  '/system/menu': _buildPage(MenuManagementPage.new),
  '/system/role': _buildPage(RoleManagementPage.new),
  '/system/user': _buildPage(UserManagementPage.new),
  '/system/adminDivision': _buildPage(AdminDivisionManagementPage.new),
};

/// 简化注册的辅助函数（普通 function，不用 tear-off 时也可直接写 lambda）
MenuPageBuilder _buildPage(
  Widget Function({required LoginUser loginUser, required CurrentChild child}) ctor,
) {
  return (context, loginUser, child) => ctor(loginUser: loginUser, child: child);
}
