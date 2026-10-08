import 'package:client/main.dart';
import 'package:material_ui/material_ui.dart';

class LoginViewModel extends ChangeNotifier {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _userCodeController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedDept;

  final FocusNode _userCodeFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  String? _userCodeError;
  String? _passwordError;
  String? _deptError;

  GlobalKey<FormState> get formKey => _formKey;

  TextEditingController get userCodeController => _userCodeController;
  TextEditingController get passwordController => _passwordController;

  String? get selectedDept => _selectedDept;

  FocusNode get userCodeFocusNode => _userCodeFocusNode;
  FocusNode get passwordFocusNode => _passwordFocusNode;

  String? get userCodeError => _userCodeError;
  String? get passwordError => _passwordError;
  String? get deptError => _deptError;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  LoginViewModel() {
    _userCodeFocusNode.addListener(() {
      if (!_userCodeFocusNode.hasFocus) {
        _validateUserCode();
      }
    });

    _passwordFocusNode.addListener(() {
      if (!_passwordFocusNode.hasFocus) {
        _validatePassword();
      }
    });
  }

  void selectDept(String? dept) {
    _selectedDept = dept;
    _validateDept(); //选择后立即重新验证
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

  void _validateDept() {
    if (_selectedDept == null || _selectedDept!.isEmpty) {
      _deptError = "科室不能为空！";
    } else {
      _deptError = null;
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
        _validateDept();

        if (_userCodeError == null && _passwordError == null && _deptError == null) {
          // final userCode = _userCodeController.text;
          // final password = _passwordController.text;
          // final dept = _selectedDept;

          //登录系统
          // final AuthenticationService service = getIt<AuthenticationService>();
          // token = await service.login(userRole, userCode, password);

          token = "aicmhcs";

          _isLoading = false;
          notifyListeners();

          return true;
        }
      }

      _isLoading = false;
      notifyListeners();

      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      notifyListeners();

      return false;
    }
  }

  /// 重置所有输入状态（重新登录进入登录页时调用）
  void reset() {
    _userCodeController.clear();
    _passwordController.clear();
    _selectedDept = null;
    _userCodeError = null;
    _passwordError = null;
    _deptError = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
