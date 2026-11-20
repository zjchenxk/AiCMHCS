import 'package:common/model.dart';

/// 儿童扩展信息 → 高危因素自动筛查（纯映射，无界面副作用）。
///
/// 依据【扩展信息】TAB 各触发字段的当前取值，推导应自动勾选的高危因素
/// 名称集合（调用方按名称在高危因素字典中精确匹配为 ID 后勾选/清除）：
/// - 出生孕周/出生体重/Apgar5 分钟按数值区间唯一命中，>=37 周、2501-4000g
///   （含端点 >2500 且 <=4000）、>7 分及未填时该组不命中；
/// - 颅内出血级别/受孕方式按数据字典项目值（即下拉显示文本）命中；
/// - SGA 分型按表单枚举值（匀称型/非匀称型）命中；
/// - 0-6 天与 7-28 天出生缺陷两字段各自映射黄色卡片缺陷项后取并集；
/// - 孕产史七项「有无」、甲亢/甲减、HIV/梅毒按「任一为有」命中；
/// - 产次+母亲生育年龄按高龄/低龄规则命中（年龄<18 不依赖产次）。
/// 名称均为本院高危因素字典（BASE_HIGH_RISK_FACTOR.RISK_FACTOR_NAME）
/// 的原文，新增/改名字典项时需同步本文件。自动筛查只做勾选/清除映射，
/// **不含互斥逻辑**——同组只能选其一（如早产三个胎龄段三选一）由
/// 互斥规则表（BASE_HIGH_RISK_FACTOR_EXCLUSION）统一生效：勾选任一项
/// 时 ViewModel 按互斥映射自动清除同组已勾选项。
class HighRiskAutoScreening {
  HighRiskAutoScreening._();

  /// 高危因素名称：早产三个胎龄段（黄/橙/红三选一）。
  static const String preterm3437 = '早产(出生胎龄34-37周)';
  static const String preterm3234 = '早产(出生胎龄32-34周)';
  static const String pretermLt32 = '早产(出生胎龄<32周，尤其<28周早产儿)';

  /// 高危因素名称：出生体重三档（黄/橙/红三选一）。
  static const String weightGt4000 = '出生体重>4000g';
  static const String weight20002500 = '出生体重2000-2500g';
  static const String weightLt2000 = '出生体重<2000g(尤其是极低和超低出生体重儿)';

  /// 高危因素名称：新生儿窒息两档（橙/红二选一；橙色项字典原文即
  /// 「室息」，与红色项「窒息」用字不同，匹配时须保持原文）。
  static const String asphyxia47 = '新生儿室息(宫内窒息、5min Apgar评分4-7分)';
  static const String asphyxiaLe3 = '新生儿窒息(宫内窒息，5min Apgar评分≤3分)';

  /// 高危因素名称：新生儿颅内出血两档（橙/红二选一）。
  static const String hemorrhage12 = '新生儿颅内出血(Ⅰ、Ⅱ级)';
  static const String hemorrhage3 = '新生儿颅内出血(Ⅲ级及以上)';

  /// 高危因素名称：小于胎龄儿两档（橙/红二选一）。
  static const String sgaAsymmetric = '小于胎龄儿(非匀称型)';
  static const String sgaSymmetric = '小于胎龄儿(匀称型)';

  /// 出生缺陷字典（0101011）项目值 → 黄色卡片高危因素名称（字典项
  /// 目值即下拉显示文本；两字段任一时段选中即命中对应缺陷项）。
  static const Map<String, String> birthDefectFactorByName = {
    '脊柱裂': '脊柱裂(隐性)',
    '先天性脑积水': '先天性脑积水，尚不需要特殊护理和治疗',
    '左腭裂': '腭裂，尚不需要特殊护理和治疗',
    '中腭裂': '腭裂，尚不需要特殊护理和治疗',
    '右腭裂': '腭裂，尚不需要特殊护理和治疗',
    '左唇裂': '唇裂',
    '中唇裂': '唇裂',
    '右唇裂': '唇裂',
    '左唇裂合并腭裂': '唇裂合并腭裂，尚不需要特殊护理和治疗',
    '中唇裂合并腭裂': '唇裂合并腭裂，尚不需要特殊护理和治疗',
    '右唇裂合并腭裂': '唇裂合并腭裂，尚不需要特殊护理和治疗',
    '左小耳（无耳）': '小耳(包括无耳)',
    '右小耳（无耳）': '小耳(包括无耳)',
    '左外耳其他畸形': '外耳其他畸形(小耳、无耳除外)',
    '右外耳其他畸形': '外耳其他畸形(小耳、无耳除外)',
    '食道闭锁或狭窄': '食管闭锁或狭窄，尚不需要特殊护理和治疗',
    '直肠肛门闭锁或狭窄（包括无肛）': '肠道或肛门闭锁或狭窄(包括无肛)，尚不需要特殊护理和治疗',
    '尿道下裂': '尿道下裂，尚不需要特殊护理和治疗',
    '膀胱外翻': '膀胱或尿道畸形，尚不需要特殊护理和治疗',
    '马蹄内翻左足': '马蹄内翻足，尚不需要特殊护理和治疗',
    '马蹄内翻右足': '马蹄内翻足，尚不需要特殊护理和治疗',
    '左侧多指': '多指(趾)',
    '右侧多指': '多指(趾)',
    '左侧多趾': '多指(趾)',
    '右侧多趾': '多指(趾)',
    '左侧并指': '并指(趾)',
    '右侧并指': '并指(趾)',
    '左侧并趾': '并指(趾)',
    '右侧并趾': '并指(趾)',
    '左上肢体短缩': '肢体短缩',
    '右上肢体短缩': '肢体短缩',
    '左下肢体短缩': '肢体短缩',
    '右下肢体短缩': '肢体短缩',
    '先天性膈疝': '先天性膈疝，尚不需要特殊护理和治疗',
    '脐膨出': '脐膨出，尚不需要特殊护理和治疗',
    '腹裂': '腹壁裂，尚不需要特殊护理和治疗',
    '唐氏综合征': '遗传病或遗传代谢性疾病等，尚不需要特殊护理和治疗',
    '先天性心脏病': '先天性心脏病，尚不需要特殊护理和治疗',
  };

  /// 自动筛查管理全集：所有可能被本类命中/清除的高危因素名称（映射
  /// 目标并集）。ViewModel 重算时对集合内未命中的项一律取消勾选——
  /// 需求口径为「条件不成立应清除其选择」，不区分当初勾选来源。
  static final Set<String> managedFactorNames = {
    preterm3437,
    preterm3234,
    pretermLt32,
    weightGt4000,
    weight20002500,
    weightLt2000,
    asphyxia47,
    asphyxiaLe3,
    hemorrhage12,
    hemorrhage3,
    sgaAsymmetric,
    sgaSymmetric,
    '有不良妊娠结局及分娩史',
    '因不孕不育行辅助医学技术受孕等',
    '妊娠期糖尿病',
    '妊娠期高血压疾病',
    'TORCH感染',
    '甲状腺疾病',
    '感染人类免疫缺陷病毒、梅毒螺旋体及乙肝病毒',
    '高龄(初产>35岁，经产>40岁)或年龄<18岁',
    '未婚先孕或受虐、吸毒等',
    ...birthDefectFactorByName.values,
  };

  /// 计算当前扩展信息应自动勾选的高危因素名称集合（未列出的触发条件
  /// 一律不命中，由调用方清除此前自动勾选的项）。
  static Set<String> targetFactorNames(ChildExtInfo ext) {
    final names = <String>{};

    // 出生孕周（周）：>=34 且 <37 黄 / >=32 且 <34 橙 / <32 红 / >=37 或未填不命中
    final week = _num(ext.gestationalWeek);
    if (week != null) {
      if (week >= 34 && week < 37) {
        names.add(preterm3437);
      } else if (week >= 32 && week < 34) {
        names.add(preterm3234);
      } else if (week < 32) {
        names.add(pretermLt32);
      }
    }

    // 出生体重（g）：>4000 黄 / 2000-2500 橙（含端点）/ <2000 红 /
    // 2501-4000（含端点）或未填不命中
    final weight = _num(ext.birthWeight);
    if (weight != null) {
      if (weight > 4000) {
        names.add(weightGt4000);
      } else if (weight >= 2000 && weight <= 2500) {
        names.add(weight20002500);
      } else if (weight < 2000) {
        names.add(weightLt2000);
      }
    }

    // Apgar评分-5分钟：4-7 橙 / <=3 红 / >7 或未填不命中
    final apgar5 = _num(ext.apgar5);
    if (apgar5 != null) {
      if (apgar5 >= 4 && apgar5 <= 7) {
        names.add(asphyxia47);
      } else if (apgar5 <= 3) {
        names.add(asphyxiaLe3);
      }
    }

    // 颅内出血级别（0101010 项目值）：Ⅰ级/Ⅱ级 橙 / Ⅲ级及以上 红 /
    // 不详、无颅内出血或未选不命中
    final hemorrhage = ext.intracranialHemorrhageLevel?.trim() ?? '';
    if (hemorrhage == 'Ⅰ级' || hemorrhage == 'Ⅱ级') {
      names.add(hemorrhage12);
    } else if (hemorrhage == 'Ⅲ级及以上') {
      names.add(hemorrhage3);
    }

    // 出生缺陷（0-6 天与 7-28 天两字段并集；无出生缺陷或未选不命中）
    for (final defect in [ext.birthDefect06d, ext.birthDefect728d]) {
      final factor = birthDefectFactorByName[defect?.trim() ?? ''];
      if (factor != null) {
        names.add(factor);
      }
    }

    // SGA 分型：非匀称型 橙 / 匀称型 红 / 未选或非小于胎龄儿（isSga=否
    // 时表单联动清空分型）不命中
    final sgaType = ext.sgaType?.trim() ?? '';
    if (sgaType == '非匀称型') {
      names.add(sgaAsymmetric);
    } else if (sgaType == '匀称型') {
      names.add(sgaSymmetric);
    }

    // 母亲孕产史七项「有无」任一为有 → 有不良妊娠结局及分娩史
    final badPregnancyHistory =
        ext.hasSpontaneousAbortionHistory == '1' ||
        ext.hasInducedAbortionHistory == '1' ||
        ext.hasRecurrentAbortionHistory == '1' ||
        ext.hasPretermBirthHistory == '1' ||
        ext.hasFetalDeadHistory == '1' ||
        ext.hasStillbirthHistory == '1' ||
        ext.hasFetalMalformationHistory == '1';
    if (badPregnancyHistory) {
      names.add('有不良妊娠结局及分娩史');
    }

    // 受孕方式（0101008 项目值）：人工授精/体外受精胚胎移植命中；
    // 自然受孕或未选不命中
    final conception = ext.conceptionMethod?.trim() ?? '';
    if (conception == '人工授精' || conception == '体外受精胚胎移植') {
      names.add('因不孕不育行辅助医学技术受孕等');
    }

    // 母亲孕期情况：糖尿病 / 妊娠期高血压 / 巨细胞病毒（TORCH）/ 甲亢甲减
    // 任一 / HIV 梅毒任一
    if (ext.hasDiabetes == '1') {
      names.add('妊娠期糖尿病');
    }
    if (ext.hasGestationalHypertension == '1') {
      names.add('妊娠期高血压疾病');
    }
    if (ext.hasCmvInfection == '1') {
      names.add('TORCH感染');
    }
    if (ext.hasHyperthyroidismInPregnancy == '1' || ext.hasHypothyroidismInPregnancy == '1') {
      names.add('甲状腺疾病');
    }
    if (ext.hasHivInfection == '1' || ext.hasSyphilisInfection == '1') {
      names.add('感染人类免疫缺陷病毒、梅毒螺旋体及乙肝病毒');
    }

    // 产次 + 母亲生育年龄：初产（产次=1）>35 / 经产（产次>1）>40 /
    // 年龄<18（不依赖产次）命中；未填或不满足不命中
    final parity = _num(ext.parity);
    final age = _num(ext.maternalAgeAtDelivery);
    final advancedAge = (age != null && age < 18) || (parity != null && age != null && ((parity == 1 && age > 35) || (parity > 1 && age > 40)));
    if (advancedAge) {
      names.add('高龄(初产>35岁，经产>40岁)或年龄<18岁');
    }

    // 家族史：父母亲有吸毒史
    if (ext.hasParentalDrugAbuseHistory == '1') {
      names.add('未婚先孕或受虐、吸毒等');
    }

    return names;
  }

  /// 数值字符串解析（空串/非法格式返回 null）。
  static double? _num(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return null;
    }
    return double.tryParse(v);
  }
}
