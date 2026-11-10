import 'dart:convert';
import 'dart:typed_data';

import 'package:client/utils/image_helper.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/view_models/system/user_management_view_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 用户信息表单（用户管理页右侧面板）
//
// 编辑模式（回填选中用户，登录账号只读）与新增模式（表单清空待录，
// 挂载科室为左侧树发起新增的节点）。以模式+目标为 ValueKey 由页面在
// 切换时重建，实现清空/回填。含角色多选（FilterChip，全量随保存提交）
// 与手写签名上传（分辨率校验后 base64 存库）。
// =====================================================================
class UserInfoForm extends StatefulWidget {
  final UserManagementViewModel viewModel;

  const UserInfoForm({
    super.key,
    required this.viewModel,
  });

  @override
  State<UserInfoForm> createState() => _UserInfoFormState();
}

class _UserInfoFormState extends State<UserInfoForm> {
  /// 各字段长度上限（与表列宽对齐，超长前后端一致拦截）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 30;
  static const int _phoneMaxLength = 20;
  static const int _idCardNoMaxLength = 20;
  static const int _extCodeMaxLength = 20;
  static const int _passwordMaxLength = 32;
  static const int _passwordMinLength = 6;

  /// 用户类别标准值域（显示标签）；编辑存量 TEACHER/PARENT 等非标准
  /// 值时动态补入选项原样显示，保存不强制订正。
  static const Map<String, String> _userTypes = {
    'ADMIN': '管理员',
    'DOCTOR': '医生',
    'NURSE': '护士',
    'TECHNICIAN': '技师',
  };

  /// 权限级别值域。
  static const Map<String, String> _permissionLevels = {
    '0': '个人级',
    '1': '机构级',
    '2': '跨机构级',
  };

  /// 状态值域。
  static const Map<String, String> _statusValues = {
    '1': '启用',
    '0': '停用',
  };

  /// 签名图片分辨率上限（横幅比例，base64 后远小于服务端 1MB 上限）。
  static const int _signatureMaxWidth = 640;
  static const int _signatureMaxHeight = 320;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userCodeCtrl;
  late final TextEditingController _userNameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _idCardNoCtrl;
  late final TextEditingController _hisUserCodeCtrl;
  late final TextEditingController _mchisUserCodeCtrl;
  late final TextEditingController _certIdCtrl;

  String? _userType;
  String? _permissionLevel;
  late String _status;
  String? _signatureBase64;
  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填选中用户；新增模式全空（状态默认启用）
    final user = widget.viewModel.formMode == UserFormMode.edit ? widget.viewModel.selectedUser : null;
    _userCodeCtrl = TextEditingController(text: user?.userCode);
    _userNameCtrl = TextEditingController(text: user?.userName);
    _passwordCtrl = TextEditingController();
    _phoneCtrl = TextEditingController(text: user?.phone);
    _idCardNoCtrl = TextEditingController(text: user?.idCardNo);
    _hisUserCodeCtrl = TextEditingController(text: user?.hisUserCode);
    _mchisUserCodeCtrl = TextEditingController(text: user?.mchisUserCode);
    _certIdCtrl = TextEditingController(text: user?.certId);
    _userType = user?.userType;
    _permissionLevel = user?.permissionLevel;
    _status = user?.status ?? '1';
    _signatureBase64 = user?.signatureImage;
  }

  @override
  void dispose() {
    _userCodeCtrl.dispose();
    _userNameCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _idCardNoCtrl.dispose();
    _hisUserCodeCtrl.dispose();
    _mchisUserCodeCtrl.dispose();
    _certIdCtrl.dispose();
    super.dispose();
  }

  /// 空白字符串归一为 null（与后端「值 null 表示清空该列」契约一致）。
  String? _nullIfEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final viewModel = context.read<UserManagementViewModel>();
    final creating = viewModel.formMode == UserFormMode.create;

    final ok = creating
        ? await viewModel.createUser(
            userCode: _userCodeCtrl.text.trim(),
            userName: _userNameCtrl.text.trim(),
            password: _passwordCtrl.text,
            userType: _nullIfEmpty(_userType),
            permissionLevel: _nullIfEmpty(_permissionLevel),
            phone: _nullIfEmpty(_phoneCtrl.text),
            idCardNo: _nullIfEmpty(_idCardNoCtrl.text),
            hisUserCode: _nullIfEmpty(_hisUserCodeCtrl.text),
            mchisUserCode: _nullIfEmpty(_mchisUserCodeCtrl.text),
            certId: _nullIfEmpty(_certIdCtrl.text),
            signatureImage: _signatureBase64,
            status: _status,
          )
        : await viewModel.updateUser(viewModel.selectedUser!.id, {
            'userName': _userNameCtrl.text.trim(),
            'userType': _nullIfEmpty(_userType),
            'permissionLevel': _nullIfEmpty(_permissionLevel),
            'phone': _nullIfEmpty(_phoneCtrl.text),
            'idCardNo': _nullIfEmpty(_idCardNoCtrl.text),
            'hisUserCode': _nullIfEmpty(_hisUserCodeCtrl.text),
            'mchisUserCode': _nullIfEmpty(_mchisUserCodeCtrl.text),
            'certId': _nullIfEmpty(_certIdCtrl.text),
            'signatureImage': _signatureBase64,
            'status': _status,
          }, password: _passwordCtrl.text);

    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // 失败提示由页面 errorMsg 监听统一弹出
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          creating ? '新增成功' : '保存成功',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);
    final viewModel = context.watch<UserManagementViewModel>();
    final creating = viewModel.formMode == UserFormMode.create;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _userCodeCtrl,
            autofocus: creating,
            maxLength: _codeMaxLength,
            // 登录账号全局唯一且为回读自然键，创建后不可改
            readOnly: !creating,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next, // 回车键显示"下一项"
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
            decoration: glassDecoration(theme, '登录账号', required: creating),
            validator: creating ? (v) => (v == null || v.trim().isEmpty) ? '请输入登录账号' : null : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _userNameCtrl,
            maxLength: _nameMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '姓名', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _passwordCtrl,
            maxLength: _passwordMaxLength,
            obscureText: _obscurePassword,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration:
                glassDecoration(
                  theme,
                  creating ? '密码' : '密码（留空不修改）',
                  required: creating,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
            validator: creating
                ? (v) {
                    final t = v ?? '';
                    if (t.isEmpty) return '请输入密码';
                    if (t.length < _passwordMinLength) return '密码长度不能少于 $_passwordMinLength 位';
                    return null;
                  }
                : null,
          ),
          const SizedBox(height: 12),

          _buildDropdown(
            theme: theme,
            label: '用户类别',
            value: _userType,
            entries: _userTypeEntries(),
            onChanged: (v) => setState(() => _userType = v),
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDropdown(
                  theme: theme,
                  label: '权限级别',
                  value: _permissionLevel,
                  entries: _permissionLevels,
                  onChanged: (v) => setState(() => _permissionLevel = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  theme: theme,
                  label: '状态',
                  value: _status,
                  entries: _statusValues,
                  required: true,
                  onChanged: (v) {
                    if (v != null) setState(() => _status = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 联系与身份
          _sectionTitle(theme, '联系与身份'),
          TextFormField(
            controller: _phoneCtrl,
            maxLength: _phoneMaxLength,
            keyboardType: TextInputType.phone,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '手机号'),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _idCardNoCtrl,
            maxLength: _idCardNoMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '身份证号'),
          ),
          const SizedBox(height: 24),

          // 扩展信息
          _sectionTitle(theme, '扩展信息'),
          TextFormField(
            controller: _hisUserCodeCtrl,
            maxLength: _extCodeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, 'HIS用户代码'),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _mchisUserCodeCtrl,
            maxLength: _extCodeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '妇幼保健系统用户代码'),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _certIdCtrl,
            maxLength: _extCodeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.done, // 最后一个输入框显示"完成"
            onFieldSubmitted: (_) => _submit(), // 回车直接保存
            decoration: glassDecoration(theme, 'CA证书ID'),
          ),
          const SizedBox(height: 24),

          // 手写签名
          _sectionTitle(theme, '手写签名'),
          _buildSignatureField(theme, viewModel),
          const SizedBox(height: 24),

          // 角色授权
          _sectionTitle(theme, '角色授权'),
          _buildRoleChips(theme, viewModel),
          const SizedBox(height: 32),

          // 操作按钮：新增模式可取消，编辑模式仅保存
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (creating) ...[
                TextButton(
                  onPressed: viewModel.busy || _saving ? null : viewModel.cancelCreate,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _submit,
                  icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                  label: const Text('添加'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保 存'),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 用户类别下拉选项：标准值域 + 编辑存量非标准值动态补入（原样显示）。
  Map<String, String> _userTypeEntries() {
    final entries = Map<String, String>.of(_userTypes);
    final current = _userType;
    if (current != null && current.isNotEmpty && !entries.containsKey(current)) {
      entries[current] = current;
    }
    return entries;
  }

  /// 简单字符串下拉（值与显示标签经 entries 映射，可空值显示 hint）。
  Widget _buildDropdown({
    required ThemeData theme,
    required String label,
    required String? value,
    required Map<String, String> entries,
    required ValueChanged<String?> onChanged,
    bool required = false,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: entries.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: theme.textTheme.bodyMedium),
            ),
          )
          .toList(),
      hint: Text('请选择$label', style: theme.textTheme.bodyMedium),
      decoration: glassDecoration(theme, label, required: required),
      style: theme.textTheme.bodyMedium,
      onChanged: onChanged,
    );
  }

  /// 手写签名字段：横幅预览框（点击重新选择）+ 选择/移除。
  Widget _buildSignatureField(ThemeData theme, UserManagementViewModel viewModel) {
    final bytes = _safeDecode(_signatureBase64);
    return Row(
      children: [
        Container(
          width: 240,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          // 解码失败（存量脏数据等）退回上传占位，不让整块表单红屏
          child: bytes == null
              ? IconButton(
                  tooltip: '选择签名图片',
                  icon: Icon(
                    Icons.add_a_photo_outlined,
                    size: 28,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: viewModel.busy || _saving ? null : _pickSignature,
                )
              : GestureDetector(
                  onTap: viewModel.busy || _saving ? null : _pickSignature,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    // 字节合法但不是有效图片时显示占位图标
                    errorBuilder: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      size: 28,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: viewModel.busy || _saving ? null : _pickSignature,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('选择图片'),
            ),
            if (_signatureBase64 != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('移除'),
                onPressed: viewModel.busy || _saving ? null : () => setState(() => _signatureBase64 = null),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 选择签名图片（分辨率校验后 base64 存入待保存状态）。
  Future<void> _pickSignature() async {
    final base64Str = await ImageHelper.pickAndConvert(
      maxWidth: _signatureMaxWidth,
      maxHeight: _signatureMaxHeight,
      onError: _showError,
    );
    if (base64Str != null) {
      setState(() => _signatureBase64 = base64Str);
    }
  }

  /// 角色多选：本医院角色 FilterChip 全量列表（无角色库时给引导提示）。
  Widget _buildRoleChips(ThemeData theme, UserManagementViewModel viewModel) {
    if (viewModel.roles.isEmpty) {
      return Text(
        '暂无角色，请先在「系统管理 → 角色管理」中创建',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final role in viewModel.roles)
          FilterChip(
            label: Text(
              role.roleName,
              style: theme.textTheme.bodyMedium,
            ),
            selected: viewModel.checkedRoleIds.contains(role.id),
            onSelected: viewModel.busy || _saving ? null : (_) => viewModel.toggleRole(role.id),
          ),
      ],
    );
  }

  /// 安全解码图片 base64：空值或存量脏数据解码失败时记日志并返回
  /// null（界面退回上传占位），避免 build 期间抛异常导致整个表单红屏。
  Uint8List? _safeDecode(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return base64Decode(base64Str);
    } catch (e, st) {
      LogHelper.error('client:UserInfoForm._safeDecode', e, st);
      return null;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError),
        ),
        backgroundColor: theme.colorScheme.error,
      ),
    );
  }

  OutlineInputBorder glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  // 统一的毛玻璃输入框装饰
  InputDecoration glassDecoration(
    ThemeData theme,
    String label, {
    bool required = false,
  }) {
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error), // 红色星号
                  ),
                ],
              ),
            )
          : Text(label, style: theme.textTheme.bodyMedium),
      counterText: '', // 隐藏 maxLength 计数器（保留输入截断）
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      enabledBorder: glassBorder(
        theme,
        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
