import 'dart:convert';
import 'package:aicmhcs_client/models/basic/city.dart';
import 'package:aicmhcs_client/models/basic/county.dart';
import 'package:aicmhcs_client/models/basic/province.dart';
import 'package:aicmhcs_client/models/basic/town.dart';
import 'package:aicmhcs_client/models/hospital_info.dart';
import 'package:aicmhcs_client/models/hospital_tree_node.dart';
import 'package:aicmhcs_client/utils/image_util.dart';
import 'package:aicmhcs_client/view_models/system/hospital_management_view_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// =====================================================================
// 医院信息设置表单
// =====================================================================
class HospitalInfoForm extends StatefulWidget {
  final HospitalTreeNode node;
  final HospitalInfo info;
  final Future<void> Function(HospitalInfo info) onSave;

  const HospitalInfoForm({super.key, required this.node, required this.info, required this.onSave});

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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final info = widget.info;
    _orgCodeCtrl = TextEditingController(text: info.orgCode);
    _nameCtrl = TextEditingController(text: info.name);
    _nameEnCtrl = TextEditingController(text: info.nameEn);
    _addressCtrl = TextEditingController(text: info.address);
    _phoneCtrl = TextEditingController(text: info.phone);
    _logoBase64 = info.logoBase64;
    _sealBase64 = info.sealBase64;

    _initAdminDivisions();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _pickImage({required bool isLogo}) async {
    final maxSize = isLogo ? OrganImageLimit.logoMaxSize : OrganImageLimit.sealMaxSize;
    final base64Str = await ImageUtil.pickAndConvert(
      maxSize: maxSize,
      onError: _showError,
    );
    if (base64Str != null) {
      setState(() {
        if (isLogo) {
          _logoBase64 = base64Str;
        } else {
          _sealBase64 = base64Str;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final viewModel = context.read<HospitalManagementViewModel>();
    final info = widget.info
      ..orgCode = _orgCodeCtrl.text.trim()
      ..name = _nameCtrl.text.trim()
      ..nameEn = _nameEnCtrl.text.trim()
      ..province = viewModel.selectedProvince?.name ?? ''
      ..city = viewModel.selectedCity?.name ?? ''
      ..county = viewModel.selectedCounty?.name ?? ''
      ..town = viewModel.selectedTown?.name ?? ''
      ..address = _addressCtrl.text.trim()
      ..phone = _phoneCtrl.text.trim()
      ..logoBase64 = _logoBase64
      ..sealBase64 = _sealBase64;
    await widget.onSave(info);

    if (mounted) setState(() => _saving = false);
  }

  /// 加载区划数据，并根据已有 info 回显选中项
  Future<void> _initAdminDivisions() async {
    final viewModel = context.read<HospitalManagementViewModel>();
    viewModel.clearAdminDivisions();

    // 加载省级列表
    final ok = await viewModel.getProvinces();
    if (!mounted || !ok) return;

    // 按已有 info 回显，逐级查找 + 加载
    final provinces = viewModel.provinces;
    if (provinces == null || provinces.isEmpty) return;

    final province = _findByName(provinces, widget.info.province);
    if (province == null) return;
    await viewModel.selectProvince(province);

    final cities = viewModel.cities;
    if (cities == null || cities.isEmpty) return;
    final city = _findByName(cities, widget.info.city);
    if (city == null) return;
    await viewModel.selectCity(city);

    final counties = viewModel.counties;
    if (counties == null || counties.isEmpty) return;
    final county = _findByName(counties, widget.info.county);
    if (county == null) return;
    await viewModel.selectCounty(county);

    final towns = viewModel.towns;
    if (towns == null || towns.isEmpty) return;
    viewModel.selectTown(_findByName(towns, widget.info.town));
  }

  /// 泛型查找：同时适配 ProvinceInfo/CityInfo/CountyInfo/TownInfo
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

    return Card(
      color: theme.colorScheme.surfaceContainer,
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: theme.colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 基本信息
                  _sectionTitle(theme, '基本信息'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _orgCodeCtrl,
                              style: theme.textTheme.bodyMedium,
                              textInputAction: TextInputAction.next, // 回车键显示"下一项"
                              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(), // 回车跳下一个
                              decoration: glassDecoration(theme, '组织机构代码'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入组织机构代码' : null,
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _nameCtrl,
                              style: theme.textTheme.bodyMedium,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                              decoration: glassDecoration(theme, '医院名称', required: true),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 地址信息
                  _sectionTitle(theme, '医院地址'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
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
                              decoration: glassDecoration(theme, '详细地址'),
                            ),
                          ],
                        ),
                      ),
                    ],
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

                  // Logo图片
                  _sectionTitle(theme, '医院Logo和印章图片'),
                  Row(
                    children: [
                      // Logo
                      _imageField(
                        theme,
                        label: '医院Logo',
                        subtitle: '不超过 ${OrganImageLimit.logoMaxSize}x${OrganImageLimit.logoMaxSize}',
                        base64: _logoBase64,
                        onPick: () => _pickImage(isLogo: true),
                        onRemove: () => setState(() => _logoBase64 = null),
                      ),
                      const SizedBox(width: 24),

                      // 印章
                      _imageField(
                        theme,
                        label: '医院印章',
                        subtitle: '不超过 ${OrganImageLimit.sealMaxSize}x${OrganImageLimit.sealMaxSize}',
                        base64: _sealBase64,
                        onPick: () => _pickImage(isLogo: false),
                        onRemove: () => setState(() => _sealBase64 = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // 保存按钮
                  Center(
                    child: _saving
                        ? const CircularProgressIndicator()
                        : FilledButton.icon(
                            icon: const Icon(Icons.save),
                            label: Text(
                              '保 存',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                            onPressed: _submit,
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder glassBorder(Color color) => OutlineInputBorder(
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
                children: const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red), // 红色星号
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
      fillColor: theme.colorScheme.surface,
      border: glassBorder(Colors.white70),
      enabledBorder: glassBorder(Colors.white70),
      focusedBorder: glassBorder(theme.colorScheme.primary.withValues(alpha: 0.8)),
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
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 图片上传字段（预览 + 选择 + 删除）
  Widget _imageField(ThemeData theme, {required String label, required String subtitle, String? base64, required VoidCallback onPick, required VoidCallback onRemove}) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),

        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),

        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: base64 == null
              ? IconButton(
                  icon: const Icon(Icons.add_a_photo, size: 32, color: Colors.grey),
                  onPressed: onPick,
                )
              : GestureDetector(
                  onTap: onPick,
                  child: Image.memory(
                    base64Decode(base64),
                    fit: BoxFit.contain,
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

  /// 级联下拉选择框：T 为 ProvinceInfo/CityInfo/CountyInfo/TownInfo
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
