import 'package:client/main.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/dict_options.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/dict_dropdown_form_field.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童「监护人」Tab 面板：左侧监护人工作列表（随整单保存、行的增删
/// 改不做权限控制），右侧监护人信息新增/修改表单。选中行回填表单，
/// 「加入列表」落本地工作列表，【保存】整单时一并入库（监护人表全量
/// 覆盖）。字段：姓名/关系必填，证件/国籍/民族/文化程度/职业走数据
/// 字典（0101001/0101002/0101004/0101005/0101006/0101007）。
class ChildGuardianPanel extends StatefulWidget {
  const ChildGuardianPanel({super.key, required this.viewModel});

  final ChildCreateViewModel viewModel;

  @override
  State<ChildGuardianPanel> createState() => ChildGuardianPanelState();
}

class ChildGuardianPanelState extends State<ChildGuardianPanel> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// 当前是否可编辑（build 时由 VM 计算；回调方法据此门控——页面缓存
  /// 子树后不再传入 editable，切修改态仅本面板随 watch 重建）。
  bool _editable = false;

  /// 正在编辑的工作列表行下标（null = 新增行）。
  int? _editingIndex;

  final _nameCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _certNoCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();

  /// 下拉类字段镜像（经 onChanged 维护，收集时直接取用）。
  String? _certType;
  String? _country;
  String? _nation;
  String? _education;
  String? _occupation;
  String? _relationship;
  String? _order;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _birthDateCtrl.dispose();
    _certNoCtrl.dispose();
    _phoneCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _employerCtrl.dispose();
    super.dispose();
  }

  /// 回填指定行到右侧表单。
  void _loadRow(int index) {
    final vm = widget.viewModel;
    final guardians = vm.guardians;
    if (index < 0 || index >= guardians.length) return;
    final g = guardians[index];
    setState(() {
      _editingIndex = index;
      _nameCtrl.text = g.name;
      _birthDateCtrl.text = g.birthDate ?? '';
      _certNoCtrl.text = g.certificateNo ?? '';
      _phoneCtrl.text = g.phone ?? '';
      _heightCtrl.text = g.height ?? '';
      _weightCtrl.text = g.weight ?? '';
      _employerCtrl.text = g.employer ?? '';
      _certType = g.certificateType;
      _country = g.country;
      _nation = g.nation;
      _education = g.educationLevel;
      _occupation = g.occupation;
      _relationship = g.guardianRelationship;
      _order = g.guardianOrder;
    });
  }

  /// 清空右侧表单回到新增行状态。
  void _resetForm() {
    setState(() {
      _editingIndex = null;
      _nameCtrl.clear();
      _birthDateCtrl.clear();
      _certNoCtrl.clear();
      _phoneCtrl.clear();
      _heightCtrl.clear();
      _weightCtrl.clear();
      _employerCtrl.clear();
      _certType = null;
      _country = null;
      _nation = null;
      _education = null;
      _occupation = null;
      _relationship = null;
      _order = null;
    });
  }

  /// 校验并把右侧表单加入/更新到监护人工作列表。
  void _submitRow() {
    if (!_editable) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final vm = widget.viewModel;
    final existing = _editingIndex != null && _editingIndex! < vm.guardians.length ? vm.guardians[_editingIndex!] : null;
    final guardian = ChildGuardianInfo(
      id: existing?.id,
      childId: vm.currentChildId,
      name: _nameCtrl.text.trim(),
      birthDate: _birthDateCtrl.text.trim().isEmpty ? null : _birthDateCtrl.text.trim(),
      // 证件类型/国籍/民族在新增行自动选中字典默认项（autoSelectDefault
      // 只设下拉初值、不触发 onChanged），镜像未变时从字典缓存兜底
      certificateType: _certType ?? DictOptions.instance.cachedDefaultOf('0101004')?.itemValue,
      certificateNo: _certNoCtrl.text.trim().isEmpty ? null : _certNoCtrl.text.trim(),
      country: _country ?? DictOptions.instance.cachedDefaultOf('0101001')?.itemValue,
      nation: _nation ?? DictOptions.instance.cachedDefaultOf('0101002')?.itemValue,
      educationLevel: _education,
      occupation: _occupation,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      height: _heightCtrl.text.trim().isEmpty ? null : _heightCtrl.text.trim(),
      weight: _weightCtrl.text.trim().isEmpty ? null : _weightCtrl.text.trim(),
      employer: _employerCtrl.text.trim().isEmpty ? null : _employerCtrl.text.trim(),
      guardianRelationship: _relationship ?? '',
      guardianOrder: _order,
      creatorId: existing?.creatorId ?? '',
      creatorName: existing?.creatorName ?? '',
      hospId: existing?.hospId ?? '',
      hospName: existing?.hospName ?? '',
    );
    vm.addOrUpdateGuardian(guardian, index: _editingIndex);
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<ChildCreateViewModel>();
    // 可编辑性经 VM 自行计算（页面缓存子树后不再传入）
    _editable = vm.creating || vm.editing;
    final editable = _editable;
    final guardians = vm.guardians;

    // 纵向滚动容器：右侧表单字段较多，低窗口下可能超过 Tab 视口高度
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左：监护人列表
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                childSectionTitle(theme, '监护人列表（${guardians.length}）'),
                if (guardians.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      editable ? '暂无监护人，请在右侧录入后加入列表' : '暂无监护人',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: guardians.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final g = guardians[index];
                        final selected = _editingIndex == index;
                        return GlassPanel(
                          blur: 12,
                          borderRadius: 12,
                          color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.8) : null,
                          child: ListTile(
                            dense: true,
                            onTap: editable ? () => _loadRow(index) : null,
                            title: Text(
                              '${g.name}（${g.guardianRelationship}）',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              [
                                if (g.phone != null && g.phone!.isNotEmpty) g.phone!,
                                if (g.guardianOrder != null && g.guardianOrder!.isNotEmpty) g.guardianOrder == '1' ? '第一监护人' : '第二监护人',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: editable ? '编辑' : '浏览模式下不可维护，请先【新增】或【修改】儿童档案',
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: editable ? () => _loadRow(index) : null,
                                ),
                                IconButton(
                                  tooltip: editable ? '移除' : '浏览模式下不可维护，请先【新增】或【修改】儿童档案',
                                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                                  onPressed: editable
                                      ? () {
                                          vm.removeGuardianAt(index);
                                          if (_editingIndex == index) {
                                            _resetForm();
                                          }
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 右：监护人表单
          Expanded(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  childSectionTitle(theme, !editable ? '监护人信息（浏览只读）' : (_editingIndex == null ? '新增监护人' : '修改监护人')),
                  if (!editable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '浏览模式下监护人只读：点击顶部【新增】或【修改】进入录入态后，在此维护监护人并【加入列表】，最后点【保存】一并入库',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _field(
                        TextFormField(
                          controller: _nameCtrl,
                          enabled: editable,
                          maxLength: 19,
                          decoration: childGlassDecoration(theme, '姓名', required: true),
                          style: theme.textTheme.bodyMedium,
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入监护人姓名' : null,
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-relation-$_relationship'),
                          dictCode: '0101007',
                          label: '监护人与儿童关系',
                          initialValue: _relationship,
                          enabled: editable,
                          required: true,
                          onChanged: (v) => setState(() => _relationship = v),
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _birthDateCtrl,
                          readOnly: true,
                          enabled: editable,
                          onTap: () => _pickDate(_birthDateCtrl, '出生日期'),
                          decoration: childGlassDecoration(theme, '出生日期'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-certtype-$_certType'),
                          dictCode: '0101004',
                          label: '证件类型',
                          initialValue: _certType,
                          enabled: editable,
                          autoSelectDefault: true,
                          onChanged: (v) => setState(() => _certType = v),
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _certNoCtrl,
                          enabled: editable,
                          maxLength: 24,
                          decoration: childGlassDecoration(theme, '证件号码'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-country-$_country'),
                          dictCode: '0101001',
                          label: '国籍',
                          initialValue: _country,
                          enabled: editable,
                          autoSelectDefault: true,
                          onChanged: (v) => setState(() => _country = v),
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-nation-$_nation'),
                          dictCode: '0101002',
                          label: '民族',
                          initialValue: _nation,
                          enabled: editable,
                          autoSelectDefault: true,
                          onChanged: (v) => setState(() => _nation = v),
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-edu-$_education'),
                          dictCode: '0101005',
                          label: '文化程度',
                          initialValue: _education,
                          enabled: editable,
                          onChanged: (v) => setState(() => _education = v),
                        ),
                      ),
                      _field(
                        DictDropdownFormField(
                          key: ValueKey('guardian-occupation-$_occupation'),
                          dictCode: '0101006',
                          label: '职业',
                          initialValue: _occupation,
                          enabled: editable,
                          onChanged: (v) => setState(() => _occupation = v),
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _phoneCtrl,
                          enabled: editable,
                          maxLength: 20,
                          keyboardType: TextInputType.phone,
                          decoration: childGlassDecoration(theme, '联系电话'),
                          style: theme.textTheme.bodyMedium,
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            return RegExp(r'^[0-9+\-() ]{5,20}$').hasMatch(t) ? null : '联系电话格式不正确';
                          },
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _heightCtrl,
                          enabled: editable,
                          maxLength: 6,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]?$'))],
                          decoration: childGlassDecoration(theme, '身高（cm）'),
                          style: theme.textTheme.bodyMedium,
                          validator: _decimalValidator,
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _weightCtrl,
                          enabled: editable,
                          maxLength: 6,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]?$'))],
                          decoration: childGlassDecoration(theme, '体重（kg）'),
                          style: theme.textTheme.bodyMedium,
                          validator: _decimalValidator,
                        ),
                      ),
                      _field(
                        TextFormField(
                          controller: _employerCtrl,
                          enabled: editable,
                          maxLength: 50,
                          decoration: childGlassDecoration(theme, '工作单位'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      _field(
                        DropdownButtonFormField<String>(
                          initialValue: _order,
                          isExpanded: true,
                          items: const {'1': '第一监护人', '2': '第二监护人'}.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value, style: theme.textTheme.bodyMedium),
                                ),
                              )
                              .toList(),
                          hint: Text('请选择监护人顺序', style: theme.textTheme.bodyMedium),
                          decoration: childGlassDecoration(theme, '监护人顺序'),
                          style: theme.textTheme.bodyMedium,
                          onChanged: editable ? (v) => setState(() => _order = v) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 操作按钮常驻：录入态激活、浏览态灰化（与顶部按钮同风格）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: editable ? (_editingIndex == null ? '填完表单后加入监护人列表' : '更新监护人到列表') : '浏览模式下不可维护，请先【新增】或【修改】儿童档案',
                        child: FilledButton.icon(
                          onPressed: editable ? _submitRow : null,
                          icon: Icon(_editingIndex == null ? Icons.add_outlined : Icons.edit_outlined, size: 18),
                          label: Text(_editingIndex == null ? '添加' : '修改'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: editable ? '清空表单' : '浏览模式下不可维护，请先【新增】或【修改】儿童档案',
                        child: OutlinedButton.icon(
                          onPressed: editable ? _resetForm : null,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('取消'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(Widget child) => SizedBox(width: 280, child: child);

  String? _decimalValidator(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null || n < 0 || n > 999.9) {
      return '应为 0-999.9 的数值';
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller, String label) async {
    if (!_editable) return;
    final current = DateTime.tryParse(controller.text.trim()) ?? getIt<TimeService>().now();
    final picked = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(1900), lastDate: DateTime(2100), helpText: '选择$label');
    if (picked == null) return;
    setState(() {
      controller.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }
}
