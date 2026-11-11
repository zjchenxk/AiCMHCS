import 'dart:async';
import 'dart:ui';
import 'package:client/utils/theme_color_mapper.dart';
import 'package:client/view_models/login/login_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/main/main_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);

    return Consumer<LoginViewModel>(
      builder: (context, loginViewModel, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.primaryFixed,
                ],
              ),
            ),
            child: Row(
              children: [
                //左屏
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end, //垂直底部对齐
                    crossAxisAlignment: CrossAxisAlignment.center, //水平居中
                    children: [
                      SvgPicture.asset(
                        'assets/images/welcome.svg',
                        height: MediaQuery.of(context).size.height * 0.85, //图片自适应屏幕高度的85%
                        fit: BoxFit.contain, //保持图片等比缩放
                        colorMapper: ThemeColorMapper(
                          primary: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                //右屏(加入毛玻璃卡片)
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ClipRRect(
                      //卡片圆角
                      borderRadius: BorderRadius.circular(24.0), //
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 15,
                          sigmaY: 15,
                        ), //毛玻璃效果
                        child: Container(
                          width: 500,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7), //半透明白色背景
                            borderRadius: BorderRadius.circular(24.0),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                            boxShadow: [
                              // 添加柔和阴影
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Form(
                            key: loginViewModel.formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min, //高度自适应内容
                              mainAxisAlignment: MainAxisAlignment.center, //垂直居中
                              crossAxisAlignment: CrossAxisAlignment.center, //水平居中
                              children: [
                                Text(
                                  'AiCMHCS',
                                  style: theme.textTheme.displayLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.primaryColorDark,
                                    fontSize: 48.0,
                                  ),
                                ),
                                SizedBox(height: 20),
                                Text(
                                  '智慧儿童心理保健系统',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.primaryColorDark,
                                    fontSize: 36.0,
                                  ),
                                ),
                                SizedBox(height: 80),

                                //用户名输入框
                                TextFormField(
                                  controller: loginViewModel.userCodeController,
                                  focusNode: loginViewModel.userCodeFocusNode, //失去焦点事件
                                  decoration: InputDecoration(
                                    labelText: '用户名',
                                    prefixIcon: Icon(Icons.person_outline), //添加图标
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12), //增大圆角
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: theme.primaryColor,
                                        width: 1.5,
                                      ),
                                    ),
                                    errorText: loginViewModel.userCodeError,
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                  textInputAction: TextInputAction.next, //设置回车为“下一步”
                                  onFieldSubmitted: (value) {
                                    //按下回车键后：加载该用户名拥有的角色绑定到角色下拉框，
                                    //焦点移到密码输入框（同一用户名不重复请求）
                                    unawaited(loginViewModel.loadRoles());
                                    loginViewModel.passwordFocusNode.requestFocus();
                                  },
                                ),
                                SizedBox(height: 20),

                                //密码输入框
                                TextFormField(
                                  controller: loginViewModel.passwordController,
                                  focusNode: loginViewModel.passwordFocusNode,
                                  obscureText: !_isPasswordVisible,
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    prefixIcon: Icon(Icons.lock_outline), //添加图标
                                    suffixIcon: _buildPasswordToggleIcon(),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
                                    ),
                                    errorText: loginViewModel.passwordError,
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                  textInputAction: TextInputAction.next,
                                ),
                                SizedBox(height: 20),

                                //角色（值域来自后端：输入用户名回车后加载该用户拥有的角色）
                                DropdownButtonFormField<String>(
                                  //绑定 VM 选中值：VM 侧清空/重置时经 key 重建同步显示
                                  key: ValueKey(loginViewModel.selectedRole),
                                  initialValue: loginViewModel.selectedRole,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: '角色',
                                    prefixIcon: Icon(Icons.home_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12), // 增大圆角
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
                                    ),
                                    //尚未加载到角色时给出引导提示
                                    hintText: loginViewModel.roles.isEmpty ? '请先输入用户名' : null,
                                    errorText: loginViewModel.roleError,
                                  ),
                                  items: loginViewModel.roles
                                      .map(
                                        (role) => DropdownMenuItem(
                                          value: role['id'],
                                          child: Text(role['roleName'] ?? '', style: theme.textTheme.bodyMedium),
                                        ),
                                      )
                                      .toList(),
                                  style: theme.textTheme.bodyMedium,
                                  onChanged: loginViewModel.selectRole,
                                ),
                                SizedBox(height: 20),

                                //登录按钮 (胶囊形/大圆角)
                                SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: FilledButton(
                                    onPressed: loginViewModel.isLoading
                                        ? null
                                        : () async {
                                            //跳转前统一收起键盘（注意只限用于移用端）
                                            //FocusScope.of(context).unfocus();

                                            final success = await loginViewModel.login();

                                            if (!context.mounted) return;

                                            if (success) {
                                              //登录成功，将全局 loginUser 同步进主界面工作副本
                                              context.read<MainViewModel>().syncLoginUser();

                                              //登录成功，替换路由跳转到主页
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => const MainPage(),
                                                ),
                                              );
                                            } else {
                                              if (loginViewModel.errorMessage != null) {
                                                //登录失败且存在错误信息，弹出 SnackBar
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      loginViewModel.errorMessage!,
                                                    ),
                                                    backgroundColor: theme.colorScheme.error, //错误色背景
                                                    behavior: SnackBarBehavior.floating, //浮动样式（有圆角），更扁平现代
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(
                                                        12,
                                                      ), //与整体圆角风格统一
                                                    ),
                                                    duration: const Duration(
                                                      seconds: 4,
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          16,
                                        ), // 现代圆角风格
                                      ),
                                    ),
                                    child: loginViewModel.isLoading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            '登  录',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                SizedBox(height: 100),

                                Text(
                                  '©2026 Chenxk Software Studio. All rights reserved.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.primaryColorDark,
                                    fontSize: 16.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPasswordToggleIcon() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          setState(() {
            _isPasswordVisible = true;
          });
        },
        onTapUp: (details) {
          setState(() {
            _isPasswordVisible = false;
          });
        },
        onTapCancel: () {
          setState(() {
            _isPasswordVisible = false;
          });
        },
        child: Icon(
          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
        ),
      ),
    );
  }
}
