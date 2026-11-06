import 'dart:convert';
import 'dart:typed_data';
import 'package:client/models/hospital_info.dart';
import 'package:client/utils/image_helper.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/view_models/system/hospital_management_view_model.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 医院信息表单（医院管理页右侧面板）
//
// 编辑模式（回填选中医院，基本信息可改、上级只读）与新增模式（表单
// 清空待录，上级医院显示新增目标父级且只读）。以模式+目标 ID 为
// ValueKey 由页面在切换时重建，实现清空/回填。
// =====================================================================
class HospitalInfoForm extends StatefulWidget {
  final HospitalManagementViewModel viewModel;

  const HospitalInfoForm({
    super.key,
    required this.viewModel,
  });

  @override
  State<HospitalInfoForm> createState() => _HospitalInfoFormState();
}

class _HospitalInfoFormState extends State<HospitalInfoForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _orgCodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameEnCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;

  String? _logoBase64;
  String? _sealBase64;
  String? _watermarkBase64;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填选中医院；新增模式全空
    final info = widget.viewModel.formMode == HospitalFormMode.edit ? widget.viewModel.selectedHospitalInfo : null;
    _orgCodeCtrl = TextEditingController(text: info?.code);
    _nameCtrl = TextEditingController(text: info?.name);
    _nameEnCtrl = TextEditingController(text: info?.nameEn);
    _addressCtrl = TextEditingController(text: info?.address);
    _phoneCtrl = TextEditingController(text: info?.tel);
    _logoBase64 = info?.logoImage;
    _sealBase64 = info?.sealImage;
    _watermarkBase64 = info?.watermarkImage;

    // 地址级联初始化会触发 VM notifyListeners，推迟到首帧后执行，
    // 避免表单挂载（build 期间）同步通知 provider 报 markNeedsBuild 异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initAdminDivisions();
    });
  }

  @override
  void dispose() {
    _orgCodeCtrl.dispose();
    _nameCtrl.dispose();
    _nameEnCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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

  /// 按目标图片的分辨率上限选图，校验通过后写回对应状态。
  Future<void> _pickImage({
    required int maxWidth,
    required int maxHeight,
    required void Function(String base64) onPicked,
  }) async {
    final base64Str = await ImageHelper.pickAndConvert(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      onError: _showError,
    );
    if (base64Str != null) {
      setState(() => onPicked(base64Str));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final viewModel = context.read<HospitalManagementViewModel>();
    final creating = viewModel.formMode == HospitalFormMode.create;
    final parent = creating ? viewModel.creatingParentNode : null;
    // 编辑模式以下拉当前选中值为准，未选中（未改动或回显未完成）时回退
    // 既有值；新增模式无既有值可回退。
    final existing = creating ? null : viewModel.selectedHospitalInfo;
    final info = HospitalInfo(id: existing?.id ?? '', parentId: creating ? parent?.id : existing?.parentId)
      ..code = _orgCodeCtrl.text.trim()
      ..name = _nameCtrl.text.trim()
      ..nameEn = _nameEnCtrl.text.trim()
      ..province = viewModel.selectedProvince?.name ?? existing?.province ?? ''
      ..city = viewModel.selectedCity?.name ?? existing?.city ?? ''
      ..county = viewModel.selectedCounty?.name ?? existing?.county
      ..town = viewModel.selectedTown?.name ?? existing?.town
      ..address = _addressCtrl.text.trim()
      ..tel = _phoneCtrl.text.trim()
      ..logoImage = _logoBase64
      ..sealImage = _sealBase64
      ..watermarkImage = _watermarkBase64;

    final ok = creating ? await viewModel.createHospital(info) : await viewModel.updateHospital(info);

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

  /// 加载区划数据，并根据已有 info 回显选中项
  Future<void> _initAdminDivisions() async {
    final viewModel = context.read<HospitalManagementViewModel>();
    viewModel.clearAdminDivisions();

    // 加载省级列表
    final ok = await viewModel.getProvinces();
    if (!mounted || !ok) return;

    // 按已有 info 回显，逐级查找 + 加载
    final info = viewModel.formMode == HospitalFormMode.edit ? viewModel.selectedHospitalInfo : null;
    if (info == null) return;

    final provinces = viewModel.provinces;
    if (provinces == null || provinces.isEmpty) return;

    final province = _findByName(provinces, info.province);
    if (province == null) return;
    await viewModel.selectProvince(province);

    final cities = viewModel.cities;
    if (cities == null || cities.isEmpty) return;
    final city = _findByName(cities, info.city);
    if (city == null) return;
    await viewModel.selectCity(city);

    final counties = viewModel.counties;
    if (counties == null || counties.isEmpty) return;
    final county = _findByName(counties, info.county);
    if (county == null) return;
    await viewModel.selectCounty(county);

    final towns = viewModel.towns;
    if (towns == null || towns.isEmpty) return;
    viewModel.selectTown(_findByName(towns, info.town));
  }

  /// 泛型查找：同时适配 Province/City/County/Town
  T? _findByName<T>(List<T> list, String? name) {
    if (name == null || name.isEmpty) return null;
    for (final e in list) {
      final n = (e as dynamic).name as String;
      if (n == name) return e;
    }
    return null;
  }

  void _onProvinceChanged(Province? value) {
    context.read<HospitalManagementViewModel>().selectProvince(value);
  }

  void _onCityChanged(City? value) {
    context.read<HospitalManagementViewModel>().selectCity(value);
  }

  void _onCountyChanged(County? value) {
    context.read<HospitalManagementViewModel>().selectCounty(value);
  }

  void _onTownChanged(Town? value) {
    context.read<HospitalManagementViewModel>().selectTown(value);
  }

  @override
  Widget build(BuildContext context) {
    //获取当前主题
    final ThemeData theme = Theme.of(context);
    // watch 区划相关状态：加载完成/选择变化时自动刷新下拉
    final viewModel = context.watch<HospitalManagementViewModel>();
    final creating = viewModel.formMode == HospitalFormMode.create;
    final parentName = creating ? viewModel.creatingParentNode?.name : null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 基本信息
          _sectionTitle(theme, '基本信息'),
          TextFormField(
            controller: _orgCodeCtrl,
            autofocus: creating,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next, // 回车键显示"下一项"
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
            decoration: glassDecoration(theme, '组织机构代码', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入组织机构代码' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameCtrl,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(
              theme,
              '医院名称',
              required: true,
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入医院中文名称' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _nameEnCtrl,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '医院英文名称'),
          ),
          const SizedBox(height: 12),

          // 上级医院（只读：新增时为录入目标父级，编辑时为树中父节点）
          TextFormField(
            initialValue: creating ? (parentName ?? '（顶级医院）') : (_parentNameOf(viewModel) ?? '（顶级医院）'),
            readOnly: true,
            style: theme.textTheme.bodyMedium,
            decoration: _readOnlyDecoration(theme, '上级医院'),
          ),
          const SizedBox(height: 24),

          // 地址信息
          _sectionTitle(theme, '医院地址'),
          _areaDropdown<Province>(
            theme: theme,
            label: '省/自治区/直辖市',
            required: true,
            items: viewModel.provinces ?? const [],
            value: viewModel.selectedProvince,
            loading: viewModel.addressLoading && viewModel.cities == null,
            validator: (v) => v == null ? '请选择省份' : null,
            onChanged: _onProvinceChanged,
          ),
          const SizedBox(height: 12),

          _areaDropdown<City>(
            theme: theme,
            label: '市/自治州/地区',
            required: true,
            items: viewModel.cities ?? const [],
            value: viewModel.selectedCity,
            validator: (v) => v == null ? '请选择城市' : null,
            onChanged: _onCityChanged,
          ),
          const SizedBox(height: 12),

          _areaDropdown<County>(
            theme: theme,
            label: '县/区/旗',
            required: true,
            items: viewModel.counties ?? const [],
            value: viewModel.selectedCounty,
            validator: (v) => v == null ? '请选择区县' : null,
            onChanged: _onCountyChanged,
          ),
          const SizedBox(height: 12),

          _areaDropdown<Town>(
            theme: theme,
            label: '乡镇/街道',
            required: false,
            items: viewModel.towns ?? const [],
            value: viewModel.selectedTown,
            validator: null,
            onChanged: _onTownChanged,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _addressCtrl,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: glassDecoration(theme, '详细地址', required: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入详细地址' : null,
          ),
          const SizedBox(height: 24),

          // 联系方式
          _sectionTitle(theme, '联系方式'),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.done, // 最后一个显示"完成"
            onFieldSubmitted: (_) => _submit(), // 回车直接保存
            decoration: glassDecoration(theme, '联系电话', required: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '请输入联系电话';
              final phoneReg = RegExp(r'^[0-9+\-() ]{5,20}$');
              if (!phoneReg.hasMatch(v.trim())) return '联系电话格式不正确';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // 图片：Logo / 印章 / 报告单水印（Wrap 换行布局，窄屏自动折行）
          _sectionTitle(theme, '医院Logo、印章与报告单水印图片'),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              // Logo
              _imageField(
                theme,
                label: '医院Logo',
                subtitle: '不超过 ${OrganImageLimit.logoMaxSize}x${OrganImageLimit.logoMaxSize}',
                base64: _logoBase64,
                onPick: () => _pickImage(
                  maxWidth: OrganImageLimit.logoMaxSize,
                  maxHeight: OrganImageLimit.logoMaxSize,
                  onPicked: (b) => _logoBase64 = b,
                ),
                onRemove: () => setState(() => _logoBase64 = null),
              ),

              // 印章
              _imageField(
                theme,
                label: '医院印章',
                subtitle: '不超过 ${OrganImageLimit.sealMaxSize}x${OrganImageLimit.sealMaxSize}',
                base64: _sealBase64,
                onPick: () => _pickImage(
                  maxWidth: OrganImageLimit.sealMaxSize,
                  maxHeight: OrganImageLimit.sealMaxSize,
                  onPicked: (b) => _sealBase64 = b,
                ),
                onRemove: () => setState(() => _sealBase64 = null),
              ),

              // 报告单水印（A4/A5 纵向等比，同一水印缩放用于两种报告单）
              _imageField(
                theme,
                label: '报告单水印',
                subtitle: '不超过 ${OrganImageLimit.watermarkMaxWidth}x${OrganImageLimit.watermarkMaxHeight}',
                base64: _watermarkBase64,
                onPick: () => _pickImage(
                  maxWidth: OrganImageLimit.watermarkMaxWidth,
                  maxHeight: OrganImageLimit.watermarkMaxHeight,
                  onPicked: (b) => _watermarkBase64 = b,
                ),
                onRemove: () => setState(() => _watermarkBase64 = null),
              ),
            ],
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
                  icon: const Icon(Icons.add_home_work_outlined, size: 18),
                  label: const Text('添加'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: viewModel.busy || _saving ? null : _submit,
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

  /// 编辑模式下取选中医院在树中的父节点名（顶级为 null）。
  String? _parentNameOf(HospitalManagementViewModel viewModel) {
    final parentId = viewModel.selectedNode?.parentId;
    if (parentId == null) return null;
    for (final root in viewModel.hospitalTree) {
      final parent = root.find(parentId);
      if (parent != null) return parent.name;
    }
    return null;
  }

  OutlineInputBorder glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  // 统一的毛玻璃输入框装饰
  InputDecoration glassDecoration(ThemeData theme, String label, {String? helper, bool required = false}) {
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
      helperText: helper,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
    );
  }

  /// 只读字段装饰（上级医院）：更淡的填充与边框，视觉上与可录入区分
  InputDecoration _readOnlyDecoration(ThemeData theme, String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
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

  /// 安全解码图片 base64：空值或存量脏数据解码失败时记日志并返回
  /// null（界面退回上传占位），避免 build 期间抛异常导致整个表单红屏。
  Uint8List? _safeDecode(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return base64Decode(base64Str);
    } catch (e, st) {
      LogHelper.error('client:HospitalInfoForm._safeDecode', e, st);
      return null;
    }
  }

  /// 图片上传字段（预览 + 选择 + 删除）
  Widget _imageField(ThemeData theme, {required String label, required String subtitle, String? base64, required VoidCallback onPick, required VoidCallback onRemove}) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),

        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 6),

        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          // 解码失败（存量脏数据等）退回上传占位，不让整块表单红屏
          child: _safeDecode(base64) == null
              ? IconButton(
                  icon: Icon(
                    Icons.add_a_photo_outlined,
                    size: 32,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onPick,
                )
              : GestureDetector(
                  onTap: onPick,
                  child: Image.memory(
                    _safeDecode(base64)!,
                    fit: BoxFit.contain,
                    // 字节合法但不是有效图片时显示占位图标
                    errorBuilder: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),

        if (base64 != null)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('移除', style: theme.textTheme.bodyMedium),
            onPressed: onRemove,
          ),
      ],
    );
  }

  /// 级联下拉选择框：T 为 Province/City/County/Town
  Widget _areaDropdown<T>({
    required ThemeData theme,
    required String label,
    required bool required,
    required List<T> items,
    required T? value,
    bool loading = false,
    required String? Function(T?)? validator,
    required ValueChanged<T?> onChanged,
    String emptyHint = '请先选择上一级',
  }) {
    return DropdownButtonFormField<T>(
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
        loading ? '加载中...' : (items.isEmpty ? emptyHint : '请选择$label'),
        style: theme.textTheme.bodyMedium,
      ),
      decoration: glassDecoration(theme, label, required: required),
      style: theme.textTheme.bodyMedium,
      validator: validator,
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}
