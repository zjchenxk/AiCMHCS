import 'package:client/view_models/system/department_management_view_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 科室信息表单（科室管理页右侧面板）
//
// 编辑模式（回填选中科室，顶部显示归属位置）与新增模式（表单清空待录，
// 顶部显示挂载位置——上级科室 / 所属院区 / 所属医院）。以模式+目标为
// ValueKey 由页面在切换时重建，实现清空/回填。
// =====================================================================
class DepartmentInfoForm extends StatefulWidget {
  final DepartmentManagementViewModel viewModel;

  const DepartmentInfoForm({
    super.key,
    required this.viewModel,
  });

  @override
  State<DepartmentInfoForm> createState() => _DepartmentInfoFormState();
}

class _DepartmentInfoFormState extends State<DepartmentInfoForm> {
  /// 各字段长度上限（与表列宽对齐，超长前后端一致拦截）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 50;
  static const int _addressMaxLength = 100;
  static const int _telMaxLength = 20;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _telCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填选中科室；新增模式全空
    final department = widget.viewModel.formMode == DepartmentFormMode.edit ? widget.viewModel.selectedDepartment : null;
    _codeCtrl = TextEditingController(text: department?.code);
    _nameCtrl = TextEditingController(text: department?.name);
    _addressCtrl = TextEditingController(text: department?.address);
    _telCtrl = TextEditingController(text: department?.tel);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final viewModel = context.read<DepartmentManagementViewModel>();
    final creating = viewModel.formMode == DepartmentFormMode.create;
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final tel = _telCtrl.text.trim();

    final ok = creating
        ? await viewModel.createDepartment(
            code: code,
            name: name,
            address: address,
            tel: tel,
          )
        : await viewModel.updateDepartment(viewModel.selectedDepartment!.id, {
            'code': code,
            'name': name,
            'address': address,
            'tel': tel,
          });

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
    final viewModel = context.watch<DepartmentManagementViewModel>();
    final creating = viewModel.formMode == DepartmentFormMode.create;
    // 顶部位置说明：新增显示挂载目标，编辑显示归属位置
    final locationLabel = creating ? viewModel.createTargetLabel : viewModel.selectedLocationLabel;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 归属位置（只读展示）
          _sectionTitle(theme, '归属位置'),
          Text(
            locationLabel.isEmpty ? '—' : locationLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _codeCtrl,
            autofocus: creating,
            maxLength: _codeMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next, // 回车键显示"下一项"
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
            decoration: glassDecoration(theme, '科室代码', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入科室代码' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameCtrl,
            maxLength: _nameMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '科室名称', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入科室名称' : null,
          ),
          const SizedBox(height: 24),

          // 联系与地址
          _sectionTitle(theme, '联系与地址'),
          TextFormField(
            controller: _addressCtrl,
            maxLength: _addressMaxLength,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '地址'),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _telCtrl,
            maxLength: _telMaxLength,
            keyboardType: TextInputType.phone,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.done, // 最后一个显示"完成"
            onFieldSubmitted: (_) => _submit(), // 回车直接保存
            decoration: glassDecoration(theme, '联系电话'),
          ),
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
                  icon: const Icon(Icons.add_business_outlined, size: 18),
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
