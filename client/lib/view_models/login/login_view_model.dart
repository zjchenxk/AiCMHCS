import 'dart:async';

import 'package:client/main.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

class LoginViewModel extends ChangeNotifier {
  /// 可选注入认证服务（便于测试替换）；为空时运行期经 getIt 解析。
  LoginViewModel({AuthService? authService}) : _authService = authService {
    _userCodeFocusNode.addListener(() {
      if (!_userCodeFocusNode.hasFocus) {
        _validateUserCode();
        //用户名框失焦（回车跳格/点击别处）即刷新该用户名拥有的角色列表
        unawaited(loadRoles());
      }
    });

    _passwordFocusNode.addListener(() {
      if (!_passwordFocusNode.hasFocus) {
        _validatePassword();
      }
    });
  }

  final AuthService? _authService;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _userCodeController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedRole;

  ///该用户名拥有的角色列表（用户名回车/失焦后从后端加载，绑定角色下拉框）
  List<Map<String, String>> _roles = const [];
  bool _isLoadingRoles = false;

  ///已成功加载角色列表对应的用户名（同一用户名不重复请求）
  String? _rolesLoadedUser;

  final FocusNode _userCodeFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  String? _userCodeError;
  String? _passwordError;
  String? _roleError;

  GlobalKey<FormState> get formKey => _formKey;

  TextEditingController get userCodeController => _userCodeController;
  TextEditingController get passwordController => _passwordController;

  String? get selectedRole => _selectedRole;

  List<Map<String, String>> get roles => _roles;
  bool get isLoadingRoles => _isLoadingRoles;

  FocusNode get userCodeFocusNode => _userCodeFocusNode;
  FocusNode get passwordFocusNode => _passwordFocusNode;

  String? get userCodeError => _userCodeError;
  String? get passwordError => _passwordError;
  String? get roleError => _roleError;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void selectRole(String? role) {
    _selectedRole = role;
    _validateRole(); //选择后立即重新验证
  }

  /// 按当前用户名从后端加载其拥有的角色列表并绑定角色下拉框。
  /// 同一用户名不重复请求；用户名变更后原选中角色不在新列表中时清空选择。
  ///return 加载后的角色列表是否可用（非空）
  Future<bool> loadRoles() async {
    final userCode = _userCodeController.text.trim();
    if (userCode.isEmpty) {
      //用户名为空时无可查角色，清空下拉框回到初始状态
      _clearRoles();
      notifyListeners();
      return false;
    }
    if (_isLoadingRoles || _rolesLoadedUser == userCode) {
      return _roles.isNotEmpty;
    }

    _isLoadingRoles = true;
    notifyListeners();

    try {
      final service = _authService ?? getIt<AuthService>();
      final roles = await service.fetchUserRoles(userCode);
      _roles = roles;
      _rolesLoadedUser = userCode;
      if (_selectedRole != null && !_roles.any((r) => r['id'] == _selectedRole)) {
        _selectedRole = null; //原选中角色不属于当前用户名，清空选择
      }
      _roleError = roles.isEmpty ? '该用户名暂无可选角色' : null;
      return roles.isNotEmpty;
    } catch (e, st) {
      //加载失败时清空角色与选择，错误提示挂在角色下拉框下
      LogHelper.error('client:LoginViewModel.loadRoles', e, st);
      _clearRoles();
      _roleError = '加载角色列表失败，请稍后重试';
      return false;
    } finally {
      _isLoadingRoles = false;
      notifyListeners();
    }
  }

  /// 清空角色列表、加载标记与已选角色（不清理校验错误，由调用方决定）。
  void _clearRoles() {
    _roles = const [];
    _rolesLoadedUser = null;
    _selectedRole = null;
  }

  @override
  void dispose() {
    _userCodeController.dispose();
    _passwordController.dispose();

    _userCodeFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  void _validateUserCode() {
    if (_userCodeController.text.isEmpty) {
      _userCodeError = '用户名不能为空！';
    } else {
      _userCodeError = null;
    }
    notifyListeners();
  }

  void _validatePassword() {
    if (_passwordController.text.isEmpty) {
      _passwordError = '密码不能为空！';
    } else {
      _passwordError = null;
    }
    notifyListeners();
  }

  void _validateRole() {
    if (_selectedRole == null || _selectedRole!.isEmpty) {
      _roleError = "角色不能为空！";
    } else {
      _roleError = null;
    }
    notifyListeners();
  }

  /// 登录方法
  /// return 返回登录结果
  Future<bool> login() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      if (_formKey.currentState?.validate() ?? false) {
        _validateUserCode();
        _validatePassword();

        if (_userCodeError == null && _passwordError == null) {
          final userCode = _userCodeController.text;
          //用户名改动后未失焦直接点登录时，角色列表可能尚未刷新，登录前兜底补加载
          if (_rolesLoadedUser != userCode.trim()) {
            await loadRoles();
          }
          if (_roleError == null) {
            _validateRole();
          }

          if (_userCodeError == null && _passwordError == null && _roleError == null) {
            final password = _passwordController.text;
            final role = _selectedRole;

            //登录系统
            final service = _authService ?? getIt<AuthService>();
            final data = await service.login(userCode, password, role!);

            token = data['token'] as String;
            sessionKey = data['sessionKey'] as String;

            //解析后端下发的用户信息写入全局（供主界面经 MainViewModel 同步展示）
            loginUser = LoginUser.fromJson(data['user'] as Map<String, dynamic>);

            _isLoading = false;
            notifyListeners();

            return true;
          }
        }
      }

      _isLoading = false;
      notifyListeners();

      return false;
    } catch (e, st) {
      // 登录失败时通常尚未建立会话，LogHelper 会自行丢弃（无通道可上报）
      LogHelper.error('client:LoginViewModel.login', e, st);
      _isLoading = false;
      _errorMessage = e.toString().replaceFirst(
        RegExp(r'^\w*(Exception|Error):\s*'),
        '',
      );
      notifyListeners();

      return false;
    }
  }

  /// 重置所有输入状态（重新登录进入登录页时调用）
  void reset() {
    _userCodeController.clear();
    _passwordController.clear();
    _clearRoles();
    _isLoadingRoles = false;
    _userCodeError = null;
    _passwordError = null;
    _roleError = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
