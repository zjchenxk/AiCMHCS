import 'package:client/view_models/system/campus_management_view_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 院区信息表单（院区管理页右侧面板）
//
// 编辑模式（回填选中院区）与新增模式（表单清空待录，归属固定为登录
// 用户所属医院）。以模式+院区 ID 为 ValueKey 由页面在切换时重建，
// 实现清空/回填。
// =====================================================================
class CampusInfoForm extends StatefulWidget {
  final CampusManagementViewModel viewModel;

  const CampusInfoForm({
    super.key,
    required this.viewModel,
  });

  @override
  State<CampusInfoForm> createState() => _CampusInfoFormState();
}

class _CampusInfoFormState extends State<CampusInfoForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _telCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填选中院区；新增模式全空
    final campus = widget.viewModel.formMode == CampusFormMode.edit ? widget.viewModel.selectedCampus : null;
    _codeCtrl = TextEditingController(text: campus?.code);
    _nameCtrl = TextEditingController(text: campus?.name);
    _addressCtrl = TextEditingController(text: campus?.address);
    _telCtrl = TextEditingController(text: campus?.tel);
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

    final viewModel = context.read<CampusManagementViewModel>();
    final creating = viewModel.formMode == CampusFormMode.create;
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final tel = _telCtrl.text.trim();

    final ok = creating
        ? await viewModel.createCampus(
            code: code,
            name: name,
            address: address,
            tel: tel,
          )
        : await viewModel.updateCampus(viewModel.selectedCampus!.id, {
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
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
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
    final viewModel = context.watch<CampusManagementViewModel>();
    final creating = viewModel.formMode == CampusFormMode.create;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _codeCtrl,
            autofocus: creating,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next, // 回车键显示"下一项"
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
            decoration: glassDecoration(theme, '院区代码', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入院区代码' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameCtrl,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '院区名称', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入院区名称' : null,
          ),
          const SizedBox(height: 24),

          // 联系与地址
          _sectionTitle(theme, '联系与地址'),
          TextFormField(
            controller: _addressCtrl,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '院区地址'),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _telCtrl,
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
  InputDecoration glassDecoration(ThemeData theme, String label, {bool required = false}) {
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
          : Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            color: theme.colorScheme.primary,
          ),
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
