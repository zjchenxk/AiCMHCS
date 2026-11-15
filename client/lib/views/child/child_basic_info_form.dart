import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/dict_dropdown_form_field.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 儿童「基本信息」Tab 表单：建档/出生/证件/保健号/居住地址（五级级联，
/// 编码自动取最深一级行政区划代码）等字段，三态共用（浏览只读、新增/
/// 修改可编辑）；暴露 [ChildBasicInfoFormState.validate] 与
/// [ChildBasicInfoFormState.collect] 供页面整单保存。
class ChildBasicInfoForm extends StatefulWidget {
  const ChildBasicInfoForm({super.key, required this.viewModel, required this.editable, this.onSubmit});

  final ChildCreateViewModel viewModel;

  /// 是否可编辑（新增/修改录入态）。
  final bool editable;

  /// 末框回车提交（整单保存）。
  final VoidCallback? onSubmit;

  @override
  State<ChildBasicInfoForm> createState() => ChildBasicInfoFormState();
}

class ChildBasicInfoFormState extends State<ChildBasicInfoForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // 字段登记（按表单顺序，校验失败滚动定位 + 输入框聚焦）
  final Map<GlobalKey<FormFieldState<String>>, FocusNode?> _fields = {};

  final GlobalKey<FormFieldState<String>> _sexKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _countryKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _nationKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _certTypeKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _provinceKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _cityKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _countyKey = GlobalKey<FormFieldState<String>>();

  final _checkTimeCtrl = TextEditingController();
  final _visitCardCtrl = TextEditingController();
  final _ecardCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _certNoCtrl = TextEditingController();
  final _healthCtrl = TextEditingController();
  final _mchisHealthCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _birthTimeCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  final _checkTimeFocus = FocusNode();
  final _visitCardFocus = FocusNode();
  final _ecardFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _certNoFocus = FocusNode();
  final _healthFocus = FocusNode();
  final _mchisHealthFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _detailsFocus = FocusNode();
  final _birthTimeFocus = FocusNode();

  /// 性别（1-男，2-女）。
  String? _sex;

  @override
  void initState() {
    super.initState();
    final child = widget.viewModel.child;
    _checkTimeCtrl.text = child?.checkTime ?? _formatDateTime(DateTime.now());
    _visitCardCtrl.text = child?.visitCardNo ?? '';
    _ecardCtrl.text = child?.ecardId ?? '';
    _nameCtrl.text = child?.name ?? '';
    _sex = child?.sex;
    _certNoCtrl.text = child?.certificateNo ?? '';
    _healthCtrl.text = child?.healthNo ?? '';
    _mchisHealthCtrl.text = child?.mchisHealthNo ?? '';
    _phoneCtrl.text = child?.phone ?? '';
    _birthDateCtrl.text = child?.birthDate ?? '';
    _birthTimeCtrl.text = child?.birthTime ?? '';
    _detailsCtrl.text = child?.addressDetails ?? '';

    // 按表单顺序登记参与校验的字段（下拉框不参与回车链，焦点为 null）
    void reg(GlobalKey<FormFieldState<String>> key, [FocusNode? fn]) => _fields[key] = fn;
    reg(_sexKey);
    reg(_provinceKey);
    reg(_cityKey);
    reg(_countyKey);
  }

  @override
  void dispose() {
    _checkTimeCtrl.dispose();
    _visitCardCtrl.dispose();
    _ecardCtrl.dispose();
    _nameCtrl.dispose();
    _certNoCtrl.dispose();
    _healthCtrl.dispose();
    _mchisHealthCtrl.dispose();
    _phoneCtrl.dispose();
    _birthDateCtrl.dispose();
    _birthTimeCtrl.dispose();
    _detailsCtrl.dispose();
    _checkTimeFocus.dispose();
    _visitCardFocus.dispose();
    _ecardFocus.dispose();
    _nameFocus.dispose();
    _certNoFocus.dispose();
    _healthFocus.dispose();
    _mchisHealthFocus.dispose();
    _phoneFocus.dispose();
    _detailsFocus.dispose();
    _birthTimeFocus.dispose();
    super.dispose();
  }

  /// 校验整表；失败时滚动定位到首个报错字段并聚焦。
  bool validate() {
    final ok = _formKey.currentState!.validate();
    if (!ok) {
      _scrollToFirstError();
    }
    return ok;
  }

  /// 收集基本信息（服务端管理字段保留自当前档案）。
  ChildInfo collect() {
    final vm = widget.viewModel;
    final base = vm.child;
    return ChildInfo(
      id: base?.id ?? '',
      checkTime: _checkTimeCtrl.text.trim(),
      visitCardNo: _nullIfEmpty(_visitCardCtrl.text),
      patientId: base?.patientId,
      ecardId: _nullIfEmpty(_ecardCtrl.text),
      name: _nameCtrl.text.trim(),
      sex: _sexKey.currentState?.value ?? _sex ?? '',
      birthDate: _birthDateCtrl.text.trim(),
      birthTime: _nullIfEmpty(_birthTimeCtrl.text),
      country: _countryKey.currentState?.value,
      nation: _nationKey.currentState?.value,
      certificateType: _certTypeKey.currentState?.value,
      certificateNo: _nullIfEmpty(_certNoCtrl.text),
      healthNo: _nullIfEmpty(_healthCtrl.text),
      mchisHealthNo: _nullIfEmpty(_mchisHealthCtrl.text),
      addressProvince: vm.selectedProvince?.name ?? base?.addressProvince ?? '',
      addressCity: vm.selectedCity?.name ?? base?.addressCity ?? '',
      addressCounty: vm.selectedCounty?.name ?? base?.addressCounty ?? '',
      addressTown: vm.selectedTown?.name ?? base?.addressTown,
      addressVillage: vm.selectedVillage?.name ?? base?.addressVillage,
      addressDetails: _detailsCtrl.text.trim(),
      addressCode: vm.addressCode ?? base?.addressCode,
      phone: _nullIfEmpty(_phoneCtrl.text),
      creatorId: base?.creatorId ?? '',
      creatorName: base?.creatorName ?? '',
      hospId: base?.hospId ?? '',
      hospName: base?.hospName ?? '',
      createTime: base?.createTime,
      updateTime: base?.updateTime,
    );
  }

  String? _nullIfEmpty(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  void _scrollToFirstError() {
    for (final entry in _fields.entries) {
      final state = entry.key.currentState;
      if (state == null || state.errorText == null) continue;
      Scrollable.ensureVisible(state.context, duration: const Duration(milliseconds: 300), alignment: 0.15);
      entry.value?.requestFocus();
      return;
    }
  }

  /// yyyy-MM-dd HH:mm:ss（本地时间，与服务端 formatTimestamp 同格式）。
  String _formatDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 只读日期框点击弹出日期选择（建档时间保留时分秒、出生日期纯日期）。
  Future<void> _pickDate({required TextEditingController controller, required String label, bool keepTime = false}) async {
    if (!widget.editable) return;
    final current = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '选择$label',
    );
    if (picked == null) return;
    final base = picked;
    final text = keepTime ? _formatDateTime(DateTime(base.year, base.month, base.day, current.hour, current.minute, current.second)) : _formatDateTime(DateTime(base.year, base.month, base.day)).substring(0, 10);
    setState(() => controller.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = widget.viewModel;
    final editable = widget.editable;
    final base = vm.child;

    Widget field(Widget child) => SizedBox(width: 300, child: child);

    return Form(
      key: _formKey,
      // 小屏/低窗口下字段总高可能超过 Tab 视口，整表滚动查看
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            field(
              TextFormField(
                controller: _checkTimeCtrl,
                readOnly: true,
                enabled: editable,
                onTap: () => _pickDate(controller: _checkTimeCtrl, label: '建档时间', keepTime: true),
                focusNode: _checkTimeFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _visitCardFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '建档时间', required: true),
                style: theme.textTheme.bodyMedium,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请选择建档时间' : null,
              ),
            ),
            field(
              TextFormField(
                initialValue: base?.patientId,
                readOnly: true,
                decoration: childGlassDecoration(theme, '病人ID（HIS回写）'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _visitCardCtrl,
                enabled: editable,
                maxLength: 100,
                focusNode: _visitCardFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _ecardFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '就诊号/就诊卡号'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _ecardCtrl,
                enabled: editable,
                maxLength: 100,
                focusNode: _ecardFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _nameFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '电子健康卡ID'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _nameCtrl,
                enabled: editable,
                maxLength: 19,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _certNoFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '姓名', required: true),
                style: theme.textTheme.bodyMedium,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
              ),
            ),
            field(
              DropdownButtonFormField<String>(
                key: _sexKey,
                initialValue: _sex,
                isExpanded: true,
                items: const {'1': '男', '2': '女'}.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: theme.textTheme.bodyMedium),
                      ),
                    )
                    .toList(),
                hint: Text('请选择性别', style: theme.textTheme.bodyMedium),
                decoration: childGlassDecoration(theme, '性别', required: true),
                style: theme.textTheme.bodyMedium,
                validator: (v) => (v == null || v.isEmpty) ? '请选择性别' : null,
                onChanged: editable ? (v) => setState(() => _sex = v) : null,
              ),
            ),
            field(
              TextFormField(
                controller: _birthDateCtrl,
                readOnly: true,
                enabled: editable,
                onTap: () => _pickDate(controller: _birthDateCtrl, label: '出生日期'),
                decoration: childGlassDecoration(theme, '出生日期', required: true),
                style: theme.textTheme.bodyMedium,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请选择出生日期' : null,
              ),
            ),
            field(
              TextFormField(
                controller: _birthTimeCtrl,
                enabled: editable,
                maxLength: 8,
                focusNode: _birthTimeFocus,
                keyboardType: TextInputType.datetime,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))],
                decoration: childGlassDecoration(theme, '出生时间（HH:mm）'),
                style: theme.textTheme.bodyMedium,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t) ? null : '出生时间格式应为 HH:mm';
                },
              ),
            ),
            field(
              DictDropdownFormField(
                dictCode: '0101001',
                label: '国籍',
                enabled: editable,
                autoSelectDefault: true,
                initialValue: base?.country,
                formFieldKey: _countryKey,
              ),
            ),
            field(
              DictDropdownFormField(
                dictCode: '0101002',
                label: '民族',
                enabled: editable,
                autoSelectDefault: true,
                initialValue: base?.nation,
                formFieldKey: _nationKey,
              ),
            ),
            field(
              DictDropdownFormField(
                dictCode: '0101004',
                label: '证件类型',
                enabled: editable,
                autoSelectDefault: true,
                initialValue: base?.certificateType,
                formFieldKey: _certTypeKey,
              ),
            ),
            field(
              TextFormField(
                controller: _certNoCtrl,
                enabled: editable,
                maxLength: 24,
                focusNode: _certNoFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _healthFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '证件号码'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _healthCtrl,
                enabled: editable,
                maxLength: 20,
                focusNode: _healthFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _mchisHealthFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '保健号'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _mchisHealthCtrl,
                enabled: editable,
                maxLength: 20,
                focusNode: _mchisHealthFocus,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '区域妇幼保健号'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _phoneCtrl,
                enabled: editable,
                maxLength: 20,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _detailsFocus.requestFocus(),
                decoration: childGlassDecoration(theme, '联系电话'),
                style: theme.textTheme.bodyMedium,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return RegExp(r'^[0-9+\-() ]{5,20}$').hasMatch(t) ? null : '联系电话格式不正确';
                },
              ),
            ),
            field(
              _areaDropdown<Province>(
                theme: theme,
                label: '省/直辖市/自治区',
                required: true,
                items: vm.provinces ?? const [],
                value: vm.selectedProvince,
                loading: vm.addressLoading,
                fieldKey: _provinceKey,
                validator: (v) => v == null ? '请选择省/直辖市/自治区' : null,
                onChanged: (v) => vm.selectProvince(v),
              ),
            ),
            field(
              _areaDropdown<City>(
                theme: theme,
                label: '市/自治州/地区',
                required: true,
                items: vm.cities ?? const [],
                value: vm.selectedCity,
                loading: vm.addressLoading,
                fieldKey: _cityKey,
                validator: (v) => v == null ? '请选择市/自治州/地区' : null,
                onChanged: (v) => vm.selectCity(v),
              ),
            ),
            field(
              _areaDropdown<County>(
                theme: theme,
                label: '县/区/旗',
                required: true,
                items: vm.counties ?? const [],
                value: vm.selectedCounty,
                loading: vm.addressLoading,
                fieldKey: _countyKey,
                validator: (v) => v == null ? '请选择县/区/旗' : null,
                onChanged: (v) => vm.selectCounty(v),
              ),
            ),
            field(
              _areaDropdown<Town>(
                theme: theme,
                label: '乡/镇/街道',
                items: vm.towns ?? const [],
                value: vm.selectedTown,
                loading: vm.addressLoading,
                onChanged: (v) => vm.selectTown(v),
              ),
            ),
            field(
              _areaDropdown<Village>(
                theme: theme,
                label: '村/居委会',
                items: vm.villages ?? const [],
                value: vm.selectedVillage,
                loading: vm.addressLoading,
                onChanged: (v) => vm.selectVillage(v),
              ),
            ),
            field(
              TextFormField(
                initialValue: vm.addressCode ?? base?.addressCode,
                readOnly: true,
                enabled: editable,
                maxLength: 20,
                decoration: childGlassDecoration(theme, '居住地址编码'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            field(
              TextFormField(
                controller: _detailsCtrl,
                enabled: editable,
                maxLength: 24,
                focusNode: _detailsFocus,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => widget.onSubmit?.call(),
                decoration: childGlassDecoration(theme, '详细地址（路/门牌号码）', required: true),
                style: theme.textTheme.bodyMedium,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入详细地址' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 级联下拉选择框（T 为 Province/City/County/Town/Village，样式同
  /// hospital_info_form 的 _areaDropdown）。
  Widget _areaDropdown<T>({
    required ThemeData theme,
    required String label,
    required List<T> items,
    required T? value,
    bool loading = false,
    bool required = false,
    GlobalKey<FormFieldState<String>>? fieldKey,
    String? Function(T?)? validator,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: fieldKey,
      initialValue: value,
      isExpanded: true,
      items: items.isEmpty
          ? null
          : items
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      (e as dynamic).name as String,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
                .toList(),
      hint: Text(
        loading ? '加载中...' : (items.isEmpty ? '请先选择上一级' : '请选择$label'),
        style: theme.textTheme.bodyMedium,
      ),
      decoration: childGlassDecoration(theme, label, required: required),
      style: theme.textTheme.bodyMedium,
      validator: validator,
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}
