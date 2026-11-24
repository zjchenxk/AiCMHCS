import 'package:client/main.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/system/holiday_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 法定节假日信息表单（法定节假日管理页右侧面板）
//
// 编辑模式（回填选中节假日）与新增模式（表单清空待录）共用；以模式+
// 节假日 ID 为 ValueKey 由页面在切换时重建，实现清空/回填。字段为
// 节假日类型下拉（1-8）与起止日期（只读输入框 + 日期选择器）。无修改
// 权限时表单整体只读；删除独立按删除权限灰化（毛玻璃确认）。
// =====================================================================
class HolidayInfoForm extends StatefulWidget {
  /// 构造函数：注入 ViewModel（表单模式与选中项均由 ViewModel 提供）。
  const HolidayInfoForm({super.key, required this.viewModel});

  final HolidayManagementViewModel viewModel;

  @override
  State<HolidayInfoForm> createState() => _HolidayInfoFormState();
}

class _HolidayInfoFormState extends State<HolidayInfoForm> {
  final _formKey = GlobalKey<FormState>();

  /// 当前选择的节假日类型（null 表示未选择）。
  int? _type;

  /// 起止日期（选择器结果；文本框只读展示 yyyy-MM-dd）。
  DateTime? _start;
  DateTime? _end;

  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final viewModel = widget.viewModel;
    // 编辑模式回填选中节假日；新增模式全空（默认类型不预选）
    final holiday = viewModel.formMode == HolidayFormMode.edit ? viewModel.selected : null;
    _type = holiday?.holidayType;
    _start = DateTime.tryParse(holiday?.startDate ?? '');
    _end = DateTime.tryParse(holiday?.endDate ?? '');
    _startCtrl = TextEditingController(text: holiday?.startDate ?? '');
    _endCtrl = TextEditingController(text: holiday?.endDate ?? '');
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  /// 业务时间口径的日期选择器（默认当前日期）。
  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? getIt<TimeService>().now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: isStart ? '选择起始日期' : '选择截止日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        _startCtrl.text = _fmtDate(picked);
      } else {
        _end = picked;
        _endCtrl.text = _fmtDate(picked);
      }
    });
  }

  String _fmtDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
  }

  Future<void> _submit() async {
    final viewModel = widget.viewModel;
    if (_saving || viewModel.busy) return;
    if (!_formKey.currentState!.validate()) return;

    final creating = viewModel.formMode == HolidayFormMode.create;
    if (creating ? !viewModel.canCreate : !viewModel.canUpdate) return;

    setState(() => _saving = true);
    final ok = creating
        ? await viewModel.createHoliday(startDate: _startCtrl.text, endDate: _endCtrl.text, holidayType: _type!)
        : await viewModel.updateHoliday(viewModel.selected!.id, {
            'startDate': _startCtrl.text,
            'endDate': _endCtrl.text,
            'holidayType': _type,
          });

    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // 失败提示由页面 errorMsg 监听统一弹出
    _showResultSnackBar(creating ? '新增成功' : '保存成功');
  }

  /// 删除选中节假日（毛玻璃确认）；成功后页面回退空态。
  Future<void> _confirmDelete() async {
    final viewModel = widget.viewModel;
    final holiday = viewModel.selected;
    if (holiday == null || viewModel.busy || _saving) return;
    if (!viewModel.canDelete) return;
    final theme = Theme.of(context);
    final desc = '${holiday.holidayTypeLabel}（${holiday.startDate} ~ ${holiday.endDate}）';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        '删除确认',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('确定删除法定节假日「$desc」吗？', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await viewModel.deleteHoliday(holiday);
    if (!mounted) return;
    if (ok) _showResultSnackBar('删除成功');
  }

  void _showResultSnackBar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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
    final theme = Theme.of(context);
    final viewModel = context.watch<HolidayManagementViewModel>();
    final creating = viewModel.formMode == HolidayFormMode.create;
    // 可编辑性：新增看新增权限，编辑看修改权限
    final editable = creating ? viewModel.canCreate : viewModel.canUpdate;
    final canDelete = !creating && viewModel.canDelete;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!editable) ...[
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  creating ? '无新增操作权限' : '无修改操作权限，当前为只读',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 节假日类型（必填）
          DropdownButtonFormField<int>(
            initialValue: _type,
            isExpanded: true,
            items: [
              for (var i = 0; i < BaseHoliday.holidayTypeLabels.length; i++)
                DropdownMenuItem(
                  value: i + 1,
                  child: Text(BaseHoliday.holidayTypeLabels[i], style: theme.textTheme.bodyMedium),
                ),
            ],
            hint: Text('请选择节假日类型', style: theme.textTheme.bodyMedium),
            decoration: glassDecoration(theme, '节假日类型', required: true),
            style: theme.textTheme.bodyMedium,
            onChanged: editable ? (v) => setState(() => _type = v) : null,
            validator: (v) => v == null ? '请选择节假日类型' : null,
          ),
          const SizedBox(height: 12),

          // 起始日期（必填，日期选择器）
          TextFormField(
            controller: _startCtrl,
            readOnly: true,
            style: theme.textTheme.bodyMedium,
            decoration: glassDecoration(theme, '起始日期', required: true),
            onTap: editable ? () => _pickDate(isStart: true) : null,
            validator: (v) => (v == null || v.isEmpty) ? '请选择起始日期' : null,
          ),
          const SizedBox(height: 12),

          // 截止日期（必填，不得早于起始）
          TextFormField(
            controller: _endCtrl,
            readOnly: true,
            style: theme.textTheme.bodyMedium,
            decoration: glassDecoration(theme, '截止日期', required: true),
            onTap: editable ? () => _pickDate(isStart: false) : null,
            validator: (v) {
              if (v == null || v.isEmpty) return '请选择截止日期';
              final start = DateTime.tryParse(_startCtrl.text);
              final end = DateTime.tryParse(v);
              if (start != null && end != null && end.isBefore(start)) return '截止日期不能早于起始日期';
              return null;
            },
          ),
          const SizedBox(height: 32),

          // 操作按钮：删除（编辑态、独立删除权限，灰化带原因）+ 取消（新增）+ 保存
          Row(
            children: [
              if (!creating)
                Tooltip(
                  message: viewModel.canDelete ? '删除选中节假日' : '无删除操作权限',
                  child: TextButton.icon(
                    onPressed: canDelete && !viewModel.busy && !_saving ? _confirmDelete : null,
                    icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                    label: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ),
              const Spacer(),
              if (creating) ...[
                TextButton(
                  onPressed: viewModel.busy || _saving ? null : viewModel.cancelCreate,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                onPressed: editable && !viewModel.busy && !_saving ? _submit : null,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保 存'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  OutlineInputBorder _glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  /// 统一的毛玻璃输入框装饰（与互斥规则/高危因素表单同款）。
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
          : Text(label, style: theme.textTheme.bodyMedium),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: _glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: _glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: _glassBorder(theme, theme.colorScheme.primary),
    );
  }
}
