import 'dart:convert';

import 'package:client/main.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/dict_dropdown_form_field.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 儿童「基本信息」Tab 表单：分「基本信息」（建档/出生/证件/保健号/
/// 居住地址五级级联，编码自动取最深一级行政区划代码）与「拍照」
/// （320×320 头像框，点击打开拍照对话框，移除仅清除当天记录）两小节；
/// 三态共用（浏览只读、新增/修改可编辑）；暴露
/// [ChildBasicInfoFormState.validate] 与 [ChildBasicInfoFormState.collect]
/// 供页面整单保存。
class ChildBasicInfoForm extends StatefulWidget {
  const ChildBasicInfoForm({super.key, required this.viewModel, required this.editable, this.onSubmit, this.onCapturePhoto, this.onRemovePhoto});

  final ChildCreateViewModel viewModel;

  /// 是否可编辑（新增/修改录入态）。
  final bool editable;

  /// 末框回车提交（整单保存）。
  final VoidCallback? onSubmit;

  /// 点击头像打开拍照对话框（浏览态传 null 禁用）。
  final VoidCallback? onCapturePhoto;

  /// 点击移除（浏览态传 null 禁用）。
  final VoidCallback? onRemovePhoto;

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

  /// 居住地址编码（只读回显，随五级地址级联选择实时刷新）。
  final _addressCodeCtrl = TextEditingController();

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
    // 建档时间默认值取全局时间服务（服务端口径，避免终端本地时钟
    // 不一致导致建档时间失真）
    _checkTimeCtrl.text = _dateOnly(child?.checkTime) ?? _formatDateTime(getIt<TimeService>().now()).substring(0, 10);
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
    _addressCodeCtrl.dispose();
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

  /// 取 yyyy-MM-dd 部分（CHECK_TIME 为 DATE 列；兼容存量带时刻的值）。
  String? _dateOnly(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return v.length >= 10 ? v.substring(0, 10) : v;
  }

  /// yyyy-MM-dd HH:mm:ss（本地时间，与服务端 formatTimestamp 同格式）。
  String _formatDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 只读日期框点击弹出日期选择（建档时间与出生日期均为纯日期）。
  Future<void> _pickDate({required TextEditingController controller, required String label}) async {
    if (!widget.editable) return;
    // 已填值（兼容存量带时刻格式）解析失败时回退当天，保证弹窗可用。
    final text = controller.text.trim();
    final initial = DateTime.tryParse(text.length >= 10 ? text.substring(0, 10) : text) ?? getIt<TimeService>().now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '选择$label',
    );
    if (picked == null) return;
    setState(() => controller.text = _formatDateTime(picked).substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = widget.viewModel;
    final editable = widget.editable;
    final base = vm.child;

    // 居住地址编码随五级级联选择实时回填（取最深一级的行政区划编码）；
    // 表单由页面在 VM 变化时重建，此处同步受控控制器即可刷新只读框
    final addressCode = vm.addressCode ?? base?.addressCode ?? '';
    if (_addressCodeCtrl.text != addressCode) {
      _addressCodeCtrl.text = addressCode;
    }

    Widget field(Widget child) => SizedBox(width: 300, child: child);

    return Form(
      key: _formKey,
      // 小屏/低窗口下字段总高可能超过 Tab 视口，整表滚动查看
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            childSectionTitle(theme, '基本信息'),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                field(
                  TextFormField(
                    controller: _checkTimeCtrl,
                    readOnly: true,
                    enabled: editable,
                    onTap: () => _pickDate(controller: _checkTimeCtrl, label: '建档时间'),
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
                    initialValue: base?.patientId,
                    readOnly: true,
                    enabled: editable,
                    decoration: childGlassDecoration(theme, '病人ID'),
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
                    decoration: childGlassDecoration(theme, '联系电话', required: true),
                    style: theme.textTheme.bodyMedium,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return '请输入联系电话';
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
                    controller: _detailsCtrl,
                    enabled: editable,
                    maxLength: 100,
                    focusNode: _detailsFocus,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => widget.onSubmit?.call(),
                    decoration: childGlassDecoration(theme, '详细地址（路/门牌号码）', required: true),
                    style: theme.textTheme.bodyMedium,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '请输入详细地址' : null,
                  ),
                ),
                field(
                  TextFormField(
                    controller: _addressCodeCtrl,
                    readOnly: true,
                    enabled: editable,
                    maxLength: 20,
                    decoration: childGlassDecoration(theme, '居住地址编码（随地址级联自动填入）'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            childSectionTitle(theme, '拍照'),
            _buildPhotoSection(theme),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 拍照小节：320×320 头像框（空白占位/最近拍照头像），点击打开拍照
  /// 对话框；头像下方标注拍摄相对时间与【移除】按钮（样式同
  /// user_info_form）；浏览态点击与移除均禁用（由页面传 null 回调控制）。
  Widget _buildPhotoSection(ThemeData theme) {
    final vm = widget.viewModel;
    final avatarBytes = vm.pendingPhoto?.avatarBytes ?? _safeDecode(vm.displayAvatarBase64);
    final timeLabel = vm.displayPhotoTimeLabel;
    final hasPhoto = vm.pendingPhoto != null || avatarBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: widget.onCapturePhoto,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarBytes != null
                ? Image.memory(
                    avatarBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    Icons.photo_camera_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: widget.onCapturePhoto != null ? 0.7 : 0.35),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.onCapturePhoto != null ? '点击头像拍照（320×320）' : '拍照（320×320）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (timeLabel != null && hasPhoto) ...[
          const SizedBox(height: 2),
          Text(
            '拍摄时间：$timeLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
        if (hasPhoto) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('移除', style: theme.textTheme.bodyMedium),
            onPressed: widget.onRemovePhoto,
          ),
        ],
      ],
    );
  }

  /// 头像 base64 解码（存量脏数据防红屏，解码失败回退 null）。
  Uint8List? _safeDecode(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return base64Decode(base64Str);
    } catch (e, st) {
      LogHelper.error('client:ChildBasicInfoForm._safeDecode', e, st);
      return null;
    }
  }

  /// 级联下拉选择框（T 为 Province/City/County/Town/Village，样式同
  /// hospital_info_form 的 _areaDropdown）；仅在录入态且下级列表已加载
  /// 时可编辑，浏览态灰化禁选（onChanged 置 null 即禁用，选中值仍回显）。
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
    final canEdit = widget.editable && items.isNotEmpty;
    // 初值必须落在 items 内（行政区划对象按实例判等），否则
    // DropdownButtonFormField 断言崩溃；失配时回退 hint（如列表重建后
    // 选中对象尚待级联回显的过渡帧）
    final safeValue = items.contains(value) ? value : null;
    return DropdownButtonFormField<T>(
      key: fieldKey,
      initialValue: safeValue,
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
      onChanged: canEdit ? onChanged : null,
    );
  }
}
