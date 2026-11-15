import 'package:client/utils/dict_options.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/dict_dropdown_form_field.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 儿童「扩展信息」Tab 表单：出生情况/母亲孕产史/母亲妊娠情况/母亲
/// 孕期情况/家族史/母亲住院信息六组字段。0/1 布尔列统一无/有下拉；
/// 条件灰化联动（灰化即清空对应值，随整单保存不落脏数据）：
/// - Apgar 三项评分自动判定有无出生窒息（任一 ≤6 置有、全部 ≥7 置无、
///   均未填不变），无窒息时灰化出生窒息程度；
/// - 无颅内出血灰化级别；无出生缺陷灰化缺陷下拉与「其他」框（选中含
///   「其他」字样激活）；无过敏史/不详同理；无死亡灰化死亡日期与原因；
/// - 孕产史各次数/畸形情况随对应有无联动；糖化血红蛋白无异常灰化两级
///   阈值；无糖尿病灰化用药；无贫血灰化程度。
class ChildExtInfoForm extends StatefulWidget {
  const ChildExtInfoForm({super.key, required this.viewModel, required this.editable});

  final ChildCreateViewModel viewModel;

  /// 是否可编辑（新增/修改录入态）。
  final bool editable;

  @override
  State<ChildExtInfoForm> createState() => ChildExtInfoFormState();
}

class ChildExtInfoFormState extends State<ChildExtInfoForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// 下拉类字段值镜像（程序化清空后界面经 KeyedSubtree 重建键刷新）。
  final Map<String, String?> _v = {};

  /// 文本/数字/日期类字段控制器。
  final Map<String, TextEditingController> _ctrls = {};

  /// 字典编码常量。
  static const String _dictDelivery = '0101003'; // 分娩方式
  static const String _dictAsphyxia = '0101009'; // 出生窒息程度
  static const String _dictHemorrhage = '0101010'; // 颅内出血级别
  static const String _dictDefect = '0101011'; // 出生缺陷
  static const String _dictAllergen = '0101012'; // 过敏原
  static const String _dictDeathCause = '0101013'; // 儿童死亡原因
  static const String _dictConception = '0101008'; // 受孕方式

  @override
  void initState() {
    super.initState();
    final ext = widget.viewModel.ext;
    void ctrl(String key, String? value) => _ctrls[key] = TextEditingController(text: value ?? '');
    void val(String key, String? value) => _v[key] = value;

    ctrl('gestationalWeek', ext?.gestationalWeek);
    ctrl('gestationalDay', ext?.gestationalDay);
    ctrl('birthWeight', ext?.birthWeight);
    ctrl('birthLength', ext?.birthLength);
    ctrl('birthHeadCirc', ext?.birthHeadCirc);
    ctrl('gravidity', ext?.gravidity);
    ctrl('parity', ext?.parity);
    ctrl('fetusCount', ext?.fetusCount);
    ctrl('birthOrder', ext?.birthOrder);
    val('deliveryMethod', ext?.deliveryMethod);
    ctrl('birthHospital', ext?.birthHospital);
    ctrl('birthCertificateNo', ext?.birthCertificateNo);
    ctrl('apgar1', ext?.apgar1);
    ctrl('apgar5', ext?.apgar5);
    ctrl('apgar10', ext?.apgar10);
    val('hasBirthAsphyxia', ext?.hasBirthAsphyxia);
    val('birthAsphyxiaSeverity', ext?.birthAsphyxiaSeverity);
    val('hasInjury', ext?.hasInjury);
    val('hasIntracranialHemorrhage', ext?.hasIntracranialHemorrhage);
    val('intracranialHemorrhageLevel', ext?.intracranialHemorrhageLevel);
    val('hasBirthDefect06d', ext?.hasBirthDefect06d);
    val('birthDefect06d', ext?.birthDefect06d);
    ctrl('otherBirthDefect06d', ext?.otherBirthDefect06d);
    val('hasBirthDefect728d', ext?.hasBirthDefect728d);
    val('birthDefect728d', ext?.birthDefect728d);
    ctrl('otherBirthDefect728d', ext?.otherBirthDefect728d);
    val('hasAllergyHistory', ext?.hasAllergyHistory);
    val('allergen', ext?.allergen);
    ctrl('otherAllergen', ext?.otherAllergen);
    val('isSga', ext?.isSga);
    val('sgaType', ext?.sgaType);
    val('isDead', ext?.isDead);
    ctrl('deathDate', ext?.deathDate);
    val('deathCause', ext?.deathCause);
    val('hasSpontaneousAbortionHistory', ext?.hasSpontaneousAbortionHistory);
    ctrl('spontaneousAbortionCount', ext?.spontaneousAbortionCount);
    val('hasInducedAbortionHistory', ext?.hasInducedAbortionHistory);
    ctrl('inducedAbortionCount', ext?.inducedAbortionCount);
    val('hasRecurrentAbortionHistory', ext?.hasRecurrentAbortionHistory);
    ctrl('recurrentAbortionCount', ext?.recurrentAbortionCount);
    val('hasPretermBirthHistory', ext?.hasPretermBirthHistory);
    ctrl('pretermBirthCount', ext?.pretermBirthCount);
    val('hasFetalDeadHistory', ext?.hasFetalDeadHistory);
    ctrl('fetalDeadCount', ext?.fetalDeadCount);
    val('hasStillbirthHistory', ext?.hasStillbirthHistory);
    ctrl('stillbirthCount', ext?.stillbirthCount);
    val('hasFetalMalformationHistory', ext?.hasFetalMalformationHistory);
    ctrl('fetalMalformationCount', ext?.fetalMalformationCount);
    ctrl('fetalMalformationInfo', ext?.fetalMalformationInfo);
    ctrl('otherPregnancyHistory', ext?.otherPregnancyHistory);
    val('conceptionMethod', ext?.conceptionMethod);
    ctrl('expectedDeliveryDate', ext?.expectedDeliveryDate);
    val('hasAbnormalHba1c', ext?.hasAbnormalHba1c);
    val('hasHba1cGe55', ext?.hasHba1cGe55);
    val('hasHba1cGe65', ext?.hasHba1cGe65);
    val('hasDiabetes', ext?.hasDiabetes);
    val('hasDiabetesMedication', ext?.hasDiabetesMedication);
    val('hasGestationalHypertension', ext?.hasGestationalHypertension);
    val('hasAnemia', ext?.hasAnemia);
    val('anemiaSeverity', ext?.anemiaSeverity);
    val('hasCmvInfection', ext?.hasCmvInfection);
    val('hasRubellaInfection', ext?.hasRubellaInfection);
    val('hasMacrosomia', ext?.hasMacrosomia);
    val('hasPolyhydramnios', ext?.hasPolyhydramnios);
    val('hasOligohydramnios', ext?.hasOligohydramnios);
    val('hasHyperthyroidismInPregnancy', ext?.hasHyperthyroidismInPregnancy);
    val('hasHypothyroidismInPregnancy', ext?.hasHypothyroidismInPregnancy);
    val('hasPreeclampsia', ext?.hasPreeclampsia);
    val('hasEclampsia', ext?.hasEclampsia);
    val('hasHivInfection', ext?.hasHivInfection);
    val('hasSyphilisInfection', ext?.hasSyphilisInfection);
    ctrl('otherDiseasesInPregnancy', ext?.otherDiseasesInPregnancy);
    val('hasParentalMentalIllnessHistory', ext?.hasParentalMentalIllnessHistory);
    val('hasParentalDrugAbuseHistory', ext?.hasParentalDrugAbuseHistory);
    val('hasFamilyHearingLossHistory', ext?.hasFamilyHearingLossHistory);
    val('hasParentalConsanguineousMarriage', ext?.hasParentalConsanguineousMarriage);
    ctrl('otherFamilyHistory', ext?.otherFamilyHistory);
    ctrl('maternalInpatientNo', ext?.maternalInpatientNo);
    ctrl('maternalAgeAtDelivery', ext?.maternalAgeAtDelivery);
  }

  @override
  void dispose() {
    for (final ctrl in _ctrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// 校验整表（数值范围校验，失败滚动定位到表单区）。
  bool validate() {
    final ok = _formKey.currentState!.validate();
    if (!ok) {
      final context = _formKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    }
    return ok;
  }

  /// 收集扩展信息（业务列全空时返回 null，表示无扩展信息）。
  ChildExtInfo? collectOrNull() {
    final ext = _collect();
    final json = ext.toJson();
    // childId 与审计字段为服务端管理列，不参与「是否有内容」判断
    const serverKeys = ['childId', 'creatorId', 'creatorName', 'hospId', 'hospName', 'createTime', 'updateTime'];
    final hasContent = json.entries.any((e) => !serverKeys.contains(e.key) && e.value != null && e.value!.toString().trim().isNotEmpty);
    if (!hasContent) {
      return null;
    }
    return ext;
  }

  ChildExtInfo _collect() {
    final vm = widget.viewModel;
    final base = vm.ext;
    String? c(String key) {
      final t = _ctrls[key]?.text.trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return ChildExtInfo(
      childId: vm.currentChildId,
      gestationalWeek: c('gestationalWeek'),
      gestationalDay: c('gestationalDay'),
      birthWeight: c('birthWeight'),
      birthLength: c('birthLength'),
      birthHeadCirc: c('birthHeadCirc'),
      gravidity: c('gravidity'),
      parity: c('parity'),
      fetusCount: c('fetusCount'),
      birthOrder: c('birthOrder'),
      deliveryMethod: _v['deliveryMethod'] ?? DictOptions.instance.cachedDefaultOf(_dictDelivery)?.itemValue ?? base?.deliveryMethod,
      birthHospital: c('birthHospital'),
      birthCertificateNo: c('birthCertificateNo'),
      apgar1: c('apgar1'),
      apgar5: c('apgar5'),
      apgar10: c('apgar10'),
      hasBirthAsphyxia: _v['hasBirthAsphyxia'],
      birthAsphyxiaSeverity: _v['birthAsphyxiaSeverity'],
      hasInjury: _v['hasInjury'],
      hasIntracranialHemorrhage: _v['hasIntracranialHemorrhage'],
      intracranialHemorrhageLevel: _v['intracranialHemorrhageLevel'],
      hasBirthDefect06d: _v['hasBirthDefect06d'],
      birthDefect06d: _v['birthDefect06d'],
      otherBirthDefect06d: c('otherBirthDefect06d'),
      hasBirthDefect728d: _v['hasBirthDefect728d'],
      birthDefect728d: _v['birthDefect728d'],
      otherBirthDefect728d: c('otherBirthDefect728d'),
      hasAllergyHistory: _v['hasAllergyHistory'],
      allergen: _v['allergen'],
      otherAllergen: c('otherAllergen'),
      isSga: _v['isSga'],
      sgaType: _v['sgaType'],
      isDead: _v['isDead'],
      deathDate: c('deathDate'),
      deathCause: _v['deathCause'],
      hasSpontaneousAbortionHistory: _v['hasSpontaneousAbortionHistory'],
      spontaneousAbortionCount: c('spontaneousAbortionCount'),
      hasInducedAbortionHistory: _v['hasInducedAbortionHistory'],
      inducedAbortionCount: c('inducedAbortionCount'),
      hasRecurrentAbortionHistory: _v['hasRecurrentAbortionHistory'],
      recurrentAbortionCount: c('recurrentAbortionCount'),
      hasPretermBirthHistory: _v['hasPretermBirthHistory'],
      pretermBirthCount: c('pretermBirthCount'),
      hasFetalDeadHistory: _v['hasFetalDeadHistory'],
      fetalDeadCount: c('fetalDeadCount'),
      hasStillbirthHistory: _v['hasStillbirthHistory'],
      stillbirthCount: c('stillbirthCount'),
      hasFetalMalformationHistory: _v['hasFetalMalformationHistory'],
      fetalMalformationCount: c('fetalMalformationCount'),
      fetalMalformationInfo: c('fetalMalformationInfo'),
      otherPregnancyHistory: c('otherPregnancyHistory'),
      conceptionMethod: _v['conceptionMethod'] ?? DictOptions.instance.cachedDefaultOf(_dictConception)?.itemValue ?? base?.conceptionMethod,
      expectedDeliveryDate: c('expectedDeliveryDate'),
      hasAbnormalHba1c: _v['hasAbnormalHba1c'],
      hasHba1cGe55: _v['hasHba1cGe55'],
      hasHba1cGe65: _v['hasHba1cGe65'],
      hasDiabetes: _v['hasDiabetes'],
      hasDiabetesMedication: _v['hasDiabetesMedication'],
      hasGestationalHypertension: _v['hasGestationalHypertension'],
      hasAnemia: _v['hasAnemia'],
      anemiaSeverity: _v['anemiaSeverity'],
      hasCmvInfection: _v['hasCmvInfection'],
      hasRubellaInfection: _v['hasRubellaInfection'],
      hasMacrosomia: _v['hasMacrosomia'],
      hasPolyhydramnios: _v['hasPolyhydramnios'],
      hasOligohydramnios: _v['hasOligohydramnios'],
      hasHyperthyroidismInPregnancy: _v['hasHyperthyroidismInPregnancy'],
      hasHypothyroidismInPregnancy: _v['hasHypothyroidismInPregnancy'],
      hasPreeclampsia: _v['hasPreeclampsia'],
      hasEclampsia: _v['hasEclampsia'],
      hasHivInfection: _v['hasHivInfection'],
      hasSyphilisInfection: _v['hasSyphilisInfection'],
      otherDiseasesInPregnancy: c('otherDiseasesInPregnancy'),
      hasParentalMentalIllnessHistory: _v['hasParentalMentalIllnessHistory'],
      hasParentalDrugAbuseHistory: _v['hasParentalDrugAbuseHistory'],
      hasFamilyHearingLossHistory: _v['hasFamilyHearingLossHistory'],
      hasParentalConsanguineousMarriage: _v['hasParentalConsanguineousMarriage'],
      otherFamilyHistory: c('otherFamilyHistory'),
      maternalInpatientNo: c('maternalInpatientNo'),
      maternalAgeAtDelivery: c('maternalAgeAtDelivery'),
      creatorId: base?.creatorId ?? '',
      creatorName: base?.creatorName ?? '',
      hospId: base?.hospId ?? '',
      hospName: base?.hospName ?? '',
      createTime: base?.createTime,
      updateTime: base?.updateTime,
    );
  }

  // ---------------- 字段值联动 ----------------

  /// 条件灰化判定：has 类字段是否为「有」（'1'）。
  bool _gate(String key) => _v[key] == '1';

  /// 下拉类字段设置值 + 联动清空被灰化字段（KeyedSubtree 重建键随值
  /// 变化，程序化清空即时生效）。
  void _setValue(String key, String? value) {
    setState(() {
      _v[key] = value;
      _normalize();
    });
  }

  /// Apgar 评分变更后自动判定有无出生窒息（任一 ≤6 → 有；全部 ≥7 →
  /// 无；均未填不变），随后联动清空被灰化字段。
  void _onApgarChanged() {
    setState(() {
      final scores = ['apgar1', 'apgar5', 'apgar10'].map((k) => int.tryParse(_ctrls[k]?.text.trim() ?? '')).toList();
      final filled = scores.whereType<int>().length;
      if (filled > 0) {
        final anyLow = scores.whereType<int>().any((s) => s <= 6);
        _v['hasBirthAsphyxia'] = anyLow ? '1' : (filled == 3 ? '0' : _v['hasBirthAsphyxia']);
      }
      _normalize();
    });
  }

  /// 联动清空被灰化字段（值镜像层；界面经重建键刷新）。
  void _normalize() {
    if (!_gate('hasBirthAsphyxia')) _v['birthAsphyxiaSeverity'] = null;
    if (!_gate('hasIntracranialHemorrhage')) _v['intracranialHemorrhageLevel'] = null;
    if (!_gate('hasBirthDefect06d')) {
      _v['birthDefect06d'] = null;
      _clearCtrl('otherBirthDefect06d');
    } else if (!DictOptions.isOther(_v['birthDefect06d'])) {
      _clearCtrl('otherBirthDefect06d');
    }
    if (!_gate('hasBirthDefect728d')) {
      _v['birthDefect728d'] = null;
      _clearCtrl('otherBirthDefect728d');
    } else if (!DictOptions.isOther(_v['birthDefect728d'])) {
      _clearCtrl('otherBirthDefect728d');
    }
    if (!_gate('hasAllergyHistory')) {
      _v['allergen'] = null;
      _clearCtrl('otherAllergen');
    } else if (!DictOptions.isOther(_v['allergen'])) {
      _clearCtrl('otherAllergen');
    }
    if (!_gate('isDead')) {
      _clearCtrl('deathDate');
      _v['deathCause'] = null;
    }
    if (!_gate('hasSpontaneousAbortionHistory')) _clearCtrl('spontaneousAbortionCount');
    if (!_gate('hasInducedAbortionHistory')) _clearCtrl('inducedAbortionCount');
    if (!_gate('hasRecurrentAbortionHistory')) _clearCtrl('recurrentAbortionCount');
    if (!_gate('hasPretermBirthHistory')) _clearCtrl('pretermBirthCount');
    if (!_gate('hasFetalDeadHistory')) _clearCtrl('fetalDeadCount');
    if (!_gate('hasStillbirthHistory')) _clearCtrl('stillbirthCount');
    if (!_gate('hasFetalMalformationHistory')) {
      _clearCtrl('fetalMalformationCount');
      _clearCtrl('fetalMalformationInfo');
    }
    if (!_gate('hasAbnormalHba1c')) {
      _v['hasHba1cGe55'] = null;
      _v['hasHba1cGe65'] = null;
    }
    if (!_gate('hasDiabetes')) _v['hasDiabetesMedication'] = null;
    if (!_gate('hasAnemia')) _v['anemiaSeverity'] = null;
    if (!_gate('isSga')) _v['sgaType'] = null;
  }

  void _clearCtrl(String key) {
    _ctrls[key]?.clear();
  }

  // ---------------- 构建辅助 ----------------

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        childSectionTitle(theme, title),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final c in children) SizedBox(width: 300, child: c)],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 数字输入（decimal 允许一位小数；Apgar 三键触发窒息自动判定）。
  Widget _num(String key, String label, {bool decimal = false, String? unit, bool enabled = true, String? Function(String?)? validator}) {
    final isApgar = key == 'apgar1' || key == 'apgar5' || key == 'apgar10';
    return TextFormField(
      controller: _ctrls[key]!,
      enabled: widget.editable && enabled,
      maxLength: 8,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        decimal ? FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]?$')) : FilteringTextInputFormatter.digitsOnly,
      ],
      autovalidateMode: AutovalidateMode.disabled,
      decoration: childGlassDecoration(Theme.of(context), unit == null ? label : '$label（$unit）'),
      style: Theme.of(context).textTheme.bodyMedium,
      onChanged: isApgar ? (_) => _onApgarChanged() : null,
      validator: validator,
    );
  }

  Widget _text(String key, String label, {int maxLength = 50, bool enabled = true}) {
    return TextFormField(
      controller: _ctrls[key]!,
      enabled: widget.editable && enabled,
      maxLength: maxLength,
      autovalidateMode: AutovalidateMode.disabled,
      decoration: childGlassDecoration(Theme.of(context), label),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  /// 布尔/枚举下拉：程序化清空后经 KeyedSubtree 重建键恢复 hint。
  Widget _flag(String key, String label, {Map<String, String> entries = const {'0': '无', '1': '有'}, bool enabled = true}) {
    return KeyedSubtree(
      key: ValueKey('flag-$key-${_v[key]}'),
      child: childFlagDropdown(
        theme: Theme.of(context),
        label: label,
        value: _v[key],
        enabled: widget.editable && enabled,
        entries: entries,
        onChanged: (v) => _setValue(key, v),
      ),
    );
  }

  Widget _dict(String key, String label, String dictCode, {bool autoSelectDefault = false, bool enabled = true}) {
    return DictDropdownFormField(
      key: ValueKey('dict-$key-${_v[key]}'),
      dictCode: dictCode,
      label: label,
      initialValue: _v[key],
      enabled: widget.editable && enabled,
      autoSelectDefault: autoSelectDefault,
      onChanged: (v) => _setValue(key, v),
    );
  }

  Widget _date(String key, String label, {bool enabled = true}) {
    final controller = _ctrls[key]!;
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: widget.editable && enabled,
      onTap: () async {
        final current = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(1900), lastDate: DateTime(2100), helpText: '选择$label');
        if (picked == null) return;
        setState(() {
          controller.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        });
      },
      decoration: childGlassDecoration(Theme.of(context), label),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable = widget.editable;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.disabled,
      // 六组字段总高远超 Tab 视口，整列滚动查看
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(theme, '出生情况', [
              _num('gestationalWeek', '出生孕周（周）'),
              _num('gestationalDay', '出生孕天（天）'),
              _num('birthWeight', '出生体重', unit: 'g'),
              _num('birthLength', '出生身长', unit: 'cm', decimal: true),
              _num('birthHeadCirc', '出生头围', unit: 'cm', decimal: true),
              _num('gravidity', '孕次'),
              _num('parity', '产次'),
              _num('fetusCount', '胎数'),
              _num('birthOrder', '出生顺序'),
              _dict('deliveryMethod', '分娩方式', _dictDelivery, autoSelectDefault: true),
              _text('birthHospital', '出生医院', maxLength: 50),
              _text('birthCertificateNo', '出生证号', maxLength: 24),
              _num('apgar1', 'Apgar评分-1分钟'),
              _num('apgar5', 'Apgar评分-5分钟'),
              _num('apgar10', 'Apgar评分-10分钟'),
              _flag('hasBirthAsphyxia', '有无出生窒息'),
              _dict('birthAsphyxiaSeverity', '出生窒息程度', _dictAsphyxia, enabled: _gate('hasBirthAsphyxia')),
              _flag('hasInjury', '有无产伤'),
              _flag('hasIntracranialHemorrhage', '有无颅内出血'),
              _dict('intracranialHemorrhageLevel', '颅内出血级别', _dictHemorrhage, enabled: _gate('hasIntracranialHemorrhage')),
              _flag('hasBirthDefect06d', '0-6天内出生缺陷'),
              _dict('birthDefect06d', '0-6天内出生缺陷', _dictDefect, enabled: _gate('hasBirthDefect06d')),
              _text('otherBirthDefect06d', '0-6天内其他出生缺陷', enabled: _gate('hasBirthDefect06d') && DictOptions.isOther(_v['birthDefect06d'])),
              _flag('hasBirthDefect728d', '7-28天内出生缺陷'),
              _dict('birthDefect728d', '7-28天内出生缺陷', _dictDefect, enabled: _gate('hasBirthDefect728d')),
              _text('otherBirthDefect728d', '7-28天内其他出生缺陷', enabled: _gate('hasBirthDefect728d') && DictOptions.isOther(_v['birthDefect728d'])),
              _flag('hasAllergyHistory', '有无过敏史', entries: const {'0': '无', '1': '有', '2': '不详'}),
              _dict('allergen', '过敏原', _dictAllergen, enabled: _gate('hasAllergyHistory')),
              _text('otherAllergen', '其他过敏原', enabled: _gate('hasAllergyHistory') && DictOptions.isOther(_v['allergen'])),
              _flag('isSga', '是否小于胎龄儿', entries: const {'0': '否', '1': '是'}),
              _flag('sgaType', 'SGA分型', entries: const {'轻度SGA': '轻度SGA', '重度SGA': '重度SGA'}, enabled: _gate('isSga')),
              _flag('isDead', '是否死亡', entries: const {'0': '否', '1': '是'}),
              _date('deathDate', '儿童死亡日期', enabled: _gate('isDead')),
              _dict('deathCause', '儿童死亡原因', _dictDeathCause, enabled: _gate('isDead')),
            ]),
            _section(theme, '母亲孕产史', [
              _flag('hasSpontaneousAbortionHistory', '有无自然流产'),
              _num('spontaneousAbortionCount', '自然流产次数', enabled: _gate('hasSpontaneousAbortionHistory')),
              _flag('hasInducedAbortionHistory', '有无人工流产'),
              _num('inducedAbortionCount', '人工流产次数', enabled: _gate('hasInducedAbortionHistory')),
              _flag('hasRecurrentAbortionHistory', '有无习惯性流产'),
              _num('recurrentAbortionCount', '习惯性流产次数', enabled: _gate('hasRecurrentAbortionHistory')),
              _flag('hasPretermBirthHistory', '有无早产'),
              _num('pretermBirthCount', '早产次数', enabled: _gate('hasPretermBirthHistory')),
              _flag('hasFetalDeadHistory', '有无死胎'),
              _num('fetalDeadCount', '死胎次数', enabled: _gate('hasFetalDeadHistory')),
              _flag('hasStillbirthHistory', '有无死产'),
              _num('stillbirthCount', '死产次数', enabled: _gate('hasStillbirthHistory')),
              _flag('hasFetalMalformationHistory', '有无胎儿畸形'),
              _num('fetalMalformationCount', '胎儿畸形次数', enabled: _gate('hasFetalMalformationHistory')),
              _text('fetalMalformationInfo', '胎儿畸形情况', enabled: _gate('hasFetalMalformationHistory')),
              _text('otherPregnancyHistory', '其他孕产史', maxLength: 250),
            ]),
            _section(theme, '母亲妊娠情况', [
              _dict('conceptionMethod', '受孕方式', _dictConception, autoSelectDefault: true),
              _date('expectedDeliveryDate', '预产期'),
            ]),
            _section(theme, '母亲孕期情况', [
              _flag('hasAbnormalHba1c', '糖化血红蛋白有无异常'),
              _flag('hasHba1cGe55', '糖化血红蛋白有无＞5.5%', enabled: _gate('hasAbnormalHba1c')),
              _flag('hasHba1cGe65', '糖化血红蛋白有无＞6.5%', enabled: _gate('hasAbnormalHba1c')),
              _flag('hasDiabetes', '有无糖尿病'),
              _flag('hasDiabetesMedication', '糖尿病是否需要药物治疗', entries: const {'0': '无需', '1': '需要'}, enabled: _gate('hasDiabetes')),
              _flag('hasGestationalHypertension', '有无妊娠期高血压'),
              _flag('hasAnemia', '有无贫血'),
              _flag('anemiaSeverity', '贫血程度', entries: const {'1': '60-110g/L', '2': '40-60g/L', '3': '≤40g/L'}, enabled: _gate('hasAnemia')),
              _flag('hasCmvInfection', '有无巨细胞病毒感染'),
              _flag('hasRubellaInfection', '有无风疹病毒感染'),
              _flag('hasMacrosomia', '有无巨大儿'),
              _flag('hasPolyhydramnios', '有无羊水过多'),
              _flag('hasOligohydramnios', '有无羊水过少'),
              _flag('hasHyperthyroidismInPregnancy', '有无妊娠合并甲亢'),
              _flag('hasHypothyroidismInPregnancy', '有无妊娠合并甲减'),
              _flag('hasPreeclampsia', '有无子痫前期'),
              _flag('hasEclampsia', '有无子痫'),
              _flag('hasHivInfection', '有无HIV感染'),
              _flag('hasSyphilisInfection', '有无梅毒感染'),
              _text('otherDiseasesInPregnancy', '其他孕期疾病', maxLength: 250),
            ]),
            _section(theme, '家族史', [
              _flag('hasParentalMentalIllnessHistory', '父母亲有无精神病史'),
              _flag('hasParentalDrugAbuseHistory', '父母亲有无吸毒史'),
              _flag('hasFamilyHearingLossHistory', '父母及同胞有无耳聋及听力损失史'),
              _flag('hasParentalConsanguineousMarriage', '父母亲是否近亲结婚'),
              _text('otherFamilyHistory', '家族史-其他情况', maxLength: 250),
            ]),
            _section(theme, '母亲住院信息', [
              _text('maternalInpatientNo', '母亲住院号', maxLength: 20),
              _num('maternalAgeAtDelivery', '母亲生育年龄'),
            ]),
            if (!editable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '浏览模式下扩展信息只读，点击【修改】后可编辑',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
