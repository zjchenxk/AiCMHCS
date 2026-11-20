import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/system/high_risk_factor_exclusion_management_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 高危因素互斥规则信息表单（互斥规则管理页右侧面板）
//
// 编辑模式（回填选中规则）与新增模式（表单清空待录）共用；以模式+规则
// ID 为 ValueKey 由页面在切换时重建，实现清空/回填。三个下拉依次选择
// 互斥的高危因素（前两项必填、第三项可选），候选取本院高危因素字典；
// 三项不得重复。无修改权限时表单整体只读。
// =====================================================================
class HighRiskFactorExclusionInfoForm extends StatefulWidget {
  /// 构造函数：注入 ViewModel（表单模式与选中项均由 ViewModel 提供）。
  const HighRiskFactorExclusionInfoForm({super.key, required this.viewModel});

  final HighRiskFactorExclusionManagementViewModel viewModel;

  @override
  State<HighRiskFactorExclusionInfoForm> createState() => _HighRiskFactorExclusionInfoFormState();
}

class _HighRiskFactorExclusionInfoFormState extends State<HighRiskFactorExclusionInfoForm> {
  final _formKey = GlobalKey<FormState>();

  /// 当前选择的三项高危因素 ID（第三项 null 表示未设置）。
  String? _firstId;
  String? _secondId;
  String? _thirdId;

  /// 原规则引用了本院已不存在的高危因素（需重新选择后才能保存）。
  bool _missingFactors = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final viewModel = widget.viewModel;
    // 编辑模式回填选中规则（已删除的高危因素不回填，强制重新选择）；
    // 新增模式全空
    final rule = viewModel.formMode == HighRiskFactorExclusionFormMode.edit ? viewModel.selected : null;
    bool known(String? id) => id != null && viewModel.factorById(id) != null;
    _firstId = known(rule?.firstRiskFactorId) ? rule?.firstRiskFactorId : null;
    _secondId = known(rule?.secondRiskFactorId) ? rule?.secondRiskFactorId : null;
    _thirdId = known(rule?.thirdRiskFactorId) ? rule?.thirdRiskFactorId : null;
    _missingFactors = rule != null && viewModel.hasMissingFactors(rule);
  }

  Future<void> _submit() async {
    final viewModel = widget.viewModel;
    if (_saving || viewModel.busy) return;
    if (!_formKey.currentState!.validate()) return;

    final creating = viewModel.formMode == HighRiskFactorExclusionFormMode.create;
    if (creating ? !viewModel.canCreate : !viewModel.canUpdate) return;

    setState(() => _saving = true);
    final ok = creating
        ? await viewModel.createExclusion(
            firstRiskFactorId: _firstId!,
            secondRiskFactorId: _secondId!,
            thirdRiskFactorId: _thirdId,
          )
        : await viewModel.updateExclusion(viewModel.selected!.id, {
            'firstRiskFactorId': _firstId,
            'secondRiskFactorId': _secondId,
            'thirdRiskFactorId': _thirdId,
          });

    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // 失败提示由页面 errorMsg 监听统一弹出
    _showResultSnackBar(creating ? '新增成功' : '保存成功');
  }

  /// 删除选中互斥规则（毛玻璃确认）；成功后页面回退空态。
  Future<void> _confirmDelete() async {
    final viewModel = widget.viewModel;
    final rule = viewModel.selected;
    if (rule == null || viewModel.busy || _saving) return;
    final theme = Theme.of(context);
    final names = rule.riskFactorIds.map(viewModel.factorNameOf).join(' × ');
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
                  Text('确定删除互斥规则「$names」吗？', style: theme.textTheme.bodyMedium),
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
    final ok = await viewModel.deleteExclusion(rule);
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
    final viewModel = context.watch<HighRiskFactorExclusionManagementViewModel>();
    final creating = viewModel.formMode == HighRiskFactorExclusionFormMode.create;
    // 可编辑性：新增看新增权限，编辑看修改权限
    final editable = creating ? viewModel.canCreate : viewModel.canUpdate;
    final factorItems = _factorItems(theme, viewModel);

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
          if (viewModel.hasNoFactors) ...[
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '本院暂无高危因素，请先在「高危因素管理」中维护后再配置互斥规则',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_missingFactors) ...[
            Row(
              children: [
                Icon(Icons.warning_amber_outlined, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '原规则引用的高危因素已不存在，请重新选择后再保存',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 规则说明
          _sectionTitle(theme, '互斥因素'),
          Text(
            '所选高危因素互斥，儿童建档时只能选择其中一项（前两项必填，第三项可选）。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),

          // 第一个高危因素（必填）
          DropdownButtonFormField<String>(
            initialValue: _firstId,
            isExpanded: true,
            items: factorItems,
            hint: Text('请选择第一个高危因素', style: theme.textTheme.bodyMedium),
            decoration: glassDecoration(theme, '第一个高危因素', required: true),
            style: theme.textTheme.bodyMedium,
            onChanged: editable ? (v) => setState(() => _firstId = v) : null,
            validator: (v) {
              if (v == null || v.isEmpty) return '请选择第一个高危因素';
              if (v == _secondId) return '第一个与第二个高危因素不能相同';
              if (v == _thirdId) return '第一个与第三个高危因素不能相同';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // 第二个高危因素（必填）
          DropdownButtonFormField<String>(
            initialValue: _secondId,
            isExpanded: true,
            items: factorItems,
            hint: Text('请选择第二个高危因素', style: theme.textTheme.bodyMedium),
            decoration: glassDecoration(theme, '第二个高危因素', required: true),
            style: theme.textTheme.bodyMedium,
            onChanged: editable ? (v) => setState(() => _secondId = v) : null,
            validator: (v) {
              if (v == null || v.isEmpty) return '请选择第二个高危因素';
              if (v == _firstId) return '第二个与第一个高危因素不能相同';
              if (v == _thirdId) return '第二个与第三个高危因素不能相同';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // 第三个高危因素（可选；空串为「不设置」哨兵，提交时归一为 null）
          DropdownButtonFormField<String>(
            initialValue: _thirdId ?? '',
            isExpanded: true,
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('（不设置第三项）', style: theme.textTheme.bodyMedium),
              ),
              ...factorItems,
            ],
            decoration: glassDecoration(theme, '第三个高危因素（可选）'),
            style: theme.textTheme.bodyMedium,
            onChanged: editable ? (v) => setState(() => _thirdId = (v == null || v.isEmpty) ? null : v) : null,
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              if (v == _firstId) return '第三个与第一个高危因素不能相同';
              if (v == _secondId) return '第三个与第二个高危因素不能相同';
              return null;
            },
          ),
          const SizedBox(height: 32),

          // 操作按钮：删除（编辑态、独立删除权限）+ 取消（新增）+ 保存
          Row(
            children: [
              if (!creating && viewModel.canDelete)
                TextButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _confirmDelete,
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  label: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
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

  /// 下拉候选：高危颜色圆点 + 名称（编码），按颜色分组顺序排列。
  List<DropdownMenuItem<String>> _factorItems(
    ThemeData theme,
    HighRiskFactorExclusionManagementViewModel viewModel,
  ) {
    return viewModel.sortedFactors
        .map(
          (factor) => DropdownMenuItem(
            value: factor.id,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: RiskColorPalette.colorOf(factor.riskColor, theme),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${factor.riskFactorName}（${factor.riskFactorCode}）',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  OutlineInputBorder _glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  /// 统一的毛玻璃输入框装饰（与高危因素/科室表单同款）。
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

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
