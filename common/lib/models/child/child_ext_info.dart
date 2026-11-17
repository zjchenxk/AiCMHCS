/// 儿童扩展信息（对应 CHILD_EXT_INFO 表，经 childId 一对一挂儿童
/// CHILD_INFO；出生孕产/母亲孕产史/母亲孕期情况/家族史等扩展档案）。
///
/// 除 childId 外业务列均可空；0/1 布尔列取值 '0'-'无/否'、'1'-'有/是'
/// （hasAllergyHistory 另有 '2'-'不详'，anemiaSeverity 取 '1'/'2'/'3'
/// 或 null-不详），数值列为字符串形式，日期列 yyyy-MM-dd。
class ChildExtInfo {
  /// 构造函数：注入儿童扩展信息各字段。
  const ChildExtInfo({
    required this.childId,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.gestationalWeek,
    this.gestationalDay,
    this.birthWeight,
    this.birthLength,
    this.birthHeadCirc,
    this.gravidity,
    this.parity,
    this.fetusCount,
    this.birthOrder,
    this.deliveryMethod,
    this.birthHospital,
    this.birthCertificateNo,
    this.apgar1,
    this.apgar5,
    this.apgar10,
    this.hasBirthAsphyxia,
    this.birthAsphyxiaSeverity,
    this.hasInjury,
    this.hasIntracranialHemorrhage,
    this.intracranialHemorrhageLevel,
    this.hasBirthDefect06d,
    this.birthDefect06d,
    this.otherBirthDefect06d,
    this.hasBirthDefect728d,
    this.birthDefect728d,
    this.otherBirthDefect728d,
    this.hasAllergyHistory,
    this.allergen,
    this.otherAllergen,
    this.isSga,
    this.sgaType,
    this.isDead,
    this.deathDate,
    this.deathCause,
    this.hasSpontaneousAbortionHistory,
    this.spontaneousAbortionCount,
    this.hasInducedAbortionHistory,
    this.inducedAbortionCount,
    this.hasRecurrentAbortionHistory,
    this.recurrentAbortionCount,
    this.hasPretermBirthHistory,
    this.pretermBirthCount,
    this.hasFetalDeadHistory,
    this.fetalDeadCount,
    this.hasStillbirthHistory,
    this.stillbirthCount,
    this.hasFetalMalformationHistory,
    this.fetalMalformationCount,
    this.fetalMalformationInfo,
    this.otherPregnancyHistory,
    this.conceptionMethod,
    this.expectedDeliveryDate,
    this.hasAbnormalHba1c,
    this.hasHba1cGe55,
    this.hasHba1cGe65,
    this.hasDiabetes,
    this.hasDiabetesMedication,
    this.hasGestationalHypertension,
    this.hasAnemia,
    this.anemiaSeverity,
    this.hasCmvInfection,
    this.hasRubellaInfection,
    this.hasMacrosomia,
    this.hasPolyhydramnios,
    this.hasOligohydramnios,
    this.hasHyperthyroidismInPregnancy,
    this.hasHypothyroidismInPregnancy,
    this.hasPreeclampsia,
    this.hasEclampsia,
    this.hasHivInfection,
    this.hasSyphilisInfection,
    this.otherDiseasesInPregnancy,
    this.hasParentalMentalIllnessHistory,
    this.hasParentalDrugAbuseHistory,
    this.hasFamilyHearingLossHistory,
    this.hasParentalConsanguineousMarriage,
    this.otherFamilyHistory,
    this.maternalInpatientNo,
    this.maternalAgeAtDelivery,
    this.createTime,
    this.updateTime,
  });

  /// 儿童 ID（主键，CHILD_INFO.ID 的字符串形式）。
  final String childId;

  /// 出生孕周。
  final String? gestationalWeek;

  /// 出生孕天。
  final String? gestationalDay;

  /// 出生体重（g）。
  final String? birthWeight;

  /// 出生身长（cm）。
  final String? birthLength;

  /// 出生头围（cm）。
  final String? birthHeadCirc;

  /// 孕次。
  final String? gravidity;

  /// 产次。
  final String? parity;

  /// 胎数（1-单胎，2-双胎，3-三胞胎……）。
  final String? fetusCount;

  /// 出生顺序（1-第一个，2-第二个……）。
  final String? birthOrder;

  /// 分娩方式（存数据字典项目值）。
  final String? deliveryMethod;

  /// 出生医院。
  final String? birthHospital;

  /// 出生证号（服务端加密存储）。
  final String? birthCertificateNo;

  /// Apgar评分-1分钟。
  final String? apgar1;

  /// Apgar评分-5分钟。
  final String? apgar5;

  /// Apgar评分-10分钟。
  final String? apgar10;

  /// 有无出生窒息（0-无，1-有；按 Apgar 评分自动判定）。
  final String? hasBirthAsphyxia;

  /// 出生窒息程度（存数据字典项目值）。
  final String? birthAsphyxiaSeverity;

  /// 有无产伤（0-无，1-有）。
  final String? hasInjury;

  /// 有无颅内出血（0-无，1-有）。
  final String? hasIntracranialHemorrhage;

  /// 颅内出血级别（存数据字典项目值）。
  final String? intracranialHemorrhageLevel;

  /// 0-6天内是否有出生缺陷（0-无，1-有）。
  final String? hasBirthDefect06d;

  /// 0-6天内出生缺陷（存数据字典项目值）。
  final String? birthDefect06d;

  /// 0-6天内其他出生缺陷。
  final String? otherBirthDefect06d;

  /// 7-28天内是否有出生缺陷（0-无，1-有）。
  final String? hasBirthDefect728d;

  /// 7-28天内出生缺陷（存数据字典项目值）。
  final String? birthDefect728d;

  /// 7-28天内其他出生缺陷。
  final String? otherBirthDefect728d;

  /// 有无过敏史（0-无，1-有，2-不详）。
  final String? hasAllergyHistory;

  /// 过敏原（存数据字典项目值）。
  final String? allergen;

  /// 其他过敏原。
  final String? otherAllergen;

  /// 是否小于胎龄儿（0-否，1-是）。
  final String? isSga;

  /// SGA分型（轻度SGA/重度SGA）。
  final String? sgaType;

  /// 是否死亡（0-否，1-是）。
  final String? isDead;

  /// 儿童死亡日期（yyyy-MM-dd）。
  final String? deathDate;

  /// 儿童死亡原因（存数据字典项目值）。
  final String? deathCause;

  /// 母亲孕产史-有无自然流产（0-无，1-有）。
  final String? hasSpontaneousAbortionHistory;

  /// 母亲孕产史-自然流产次数。
  final String? spontaneousAbortionCount;

  /// 母亲孕产史-有无人工流产（0-无，1-有）。
  final String? hasInducedAbortionHistory;

  /// 母亲孕产史-人工流产次数。
  final String? inducedAbortionCount;

  /// 母亲孕产史-有无习惯性流产（0-无，1-有）。
  final String? hasRecurrentAbortionHistory;

  /// 母亲孕产史-习惯性流产次数。
  final String? recurrentAbortionCount;

  /// 母亲孕产史-有无早产（0-无，1-有）。
  final String? hasPretermBirthHistory;

  /// 母亲孕产史-早产次数。
  final String? pretermBirthCount;

  /// 母亲孕产史-有无死胎（0-无，1-有）。
  final String? hasFetalDeadHistory;

  /// 母亲孕产史-死胎次数。
  final String? fetalDeadCount;

  /// 母亲孕产史-有无死产（0-无，1-有）。
  final String? hasStillbirthHistory;

  /// 母亲孕产史-死产次数。
  final String? stillbirthCount;

  /// 母亲孕产史-有无胎儿畸形（0-无，1-有）。
  final String? hasFetalMalformationHistory;

  /// 母亲孕产史-胎儿畸形次数。
  final String? fetalMalformationCount;

  /// 母亲孕产史-胎儿畸形情况。
  final String? fetalMalformationInfo;

  /// 母亲孕产史-其他情况。
  final String? otherPregnancyHistory;

  /// 母亲妊娠情况-受孕方式（存数据字典项目值）。
  final String? conceptionMethod;

  /// 母亲妊娠情况-预产期（yyyy-MM-dd）。
  final String? expectedDeliveryDate;

  /// 母亲孕期情况-糖化血红蛋白有无异常（0-无，1-有）。
  final String? hasAbnormalHba1c;

  /// 母亲孕期情况-糖化血红蛋白有无＞5.5%（0-无，1-有）。
  final String? hasHba1cGe55;

  /// 母亲孕期情况-糖化血红蛋白有无＞6.5%（0-无，1-有）。
  final String? hasHba1cGe65;

  /// 母亲孕期情况-有无糖尿病（0-无，1-有）。
  final String? hasDiabetes;

  /// 母亲孕期情况-糖尿病是否需要药物治疗（0-无需，1-需要）。
  final String? hasDiabetesMedication;

  /// 母亲孕期情况-有无妊娠期高血压（0-无，1-有）。
  final String? hasGestationalHypertension;

  /// 母亲孕期情况-有无贫血（0-无，1-有）。
  final String? hasAnemia;

  /// 母亲孕期情况-贫血程度（1-60-110g/L，2-40-60g/L，3-≤40g/L，null-不详）。
  final String? anemiaSeverity;

  /// 母亲孕期情况-有无巨细胞病毒感染（0-无，1-有）。
  final String? hasCmvInfection;

  /// 母亲孕期情况-有无风疹病毒感染（0-无，1-有）。
  final String? hasRubellaInfection;

  /// 母亲孕期情况-有无巨大儿（0-无，1-有）。
  final String? hasMacrosomia;

  /// 母亲孕期情况-有无羊水过多（0-无，1-有）。
  final String? hasPolyhydramnios;

  /// 母亲孕期情况-有无羊水过少（0-无，1-有）。
  final String? hasOligohydramnios;

  /// 母亲孕期情况-有无妊娠合并甲亢（0-无，1-有）。
  final String? hasHyperthyroidismInPregnancy;

  /// 母亲孕期情况-有无妊娠合并甲减（0-无，1-有）。
  final String? hasHypothyroidismInPregnancy;

  /// 母亲孕期情况-有无子痫前期（0-无，1-有）。
  final String? hasPreeclampsia;

  /// 母亲孕期情况-有无子痫（0-无，1-有）。
  final String? hasEclampsia;

  /// 母亲孕期情况-有无HIV感染（0-无，1-有）。
  final String? hasHivInfection;

  /// 母亲孕期情况-有无梅毒感染（0-无，1-有）。
  final String? hasSyphilisInfection;

  /// 母亲孕期情况-其他疾病。
  final String? otherDiseasesInPregnancy;

  /// 家族史-父母亲有无精神病史（0-无，1-有）。
  final String? hasParentalMentalIllnessHistory;

  /// 家族史-父母亲有无吸毒史（0-无，1-有）。
  final String? hasParentalDrugAbuseHistory;

  /// 家族史-父母及同胞有无耳聋及听力损失史（0-无，1-有）。
  final String? hasFamilyHearingLossHistory;

  /// 家族史-父母亲是否近亲结婚（0-无，1-有）。
  final String? hasParentalConsanguineousMarriage;

  /// 家族史-其他情况。
  final String? otherFamilyHistory;

  /// 母亲住院号。
  final String? maternalInpatientNo;

  /// 母亲生育年龄。
  final String? maternalAgeAtDelivery;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 归属科室 ID（建档人所属科室，建档时随会话写入、不可修改）。
  final String? deptId;

  /// 归属科室名称。
  final String? deptName;

  /// 归属院区 ID（建档人所属院区，建档时随会话写入、不可修改）。
  final String? campusId;

  /// 归属院区名称。
  final String? campusName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory ChildExtInfo.fromJson(Map<String, dynamic> json) {
    return ChildExtInfo(
      childId: json['childId'] as String? ?? '',
      gestationalWeek: json['gestationalWeek'] as String?,
      gestationalDay: json['gestationalDay'] as String?,
      birthWeight: json['birthWeight'] as String?,
      birthLength: json['birthLength'] as String?,
      birthHeadCirc: json['birthHeadCirc'] as String?,
      gravidity: json['gravidity'] as String?,
      parity: json['parity'] as String?,
      fetusCount: json['fetusCount'] as String?,
      birthOrder: json['birthOrder'] as String?,
      deliveryMethod: json['deliveryMethod'] as String?,
      birthHospital: json['birthHospital'] as String?,
      birthCertificateNo: json['birthCertificateNo'] as String?,
      apgar1: json['apgar1'] as String?,
      apgar5: json['apgar5'] as String?,
      apgar10: json['apgar10'] as String?,
      hasBirthAsphyxia: json['hasBirthAsphyxia'] as String?,
      birthAsphyxiaSeverity: json['birthAsphyxiaSeverity'] as String?,
      hasInjury: json['hasInjury'] as String?,
      hasIntracranialHemorrhage: json['hasIntracranialHemorrhage'] as String?,
      intracranialHemorrhageLevel: json['intracranialHemorrhageLevel'] as String?,
      hasBirthDefect06d: json['hasBirthDefect06d'] as String?,
      birthDefect06d: json['birthDefect06d'] as String?,
      otherBirthDefect06d: json['otherBirthDefect06d'] as String?,
      hasBirthDefect728d: json['hasBirthDefect728d'] as String?,
      birthDefect728d: json['birthDefect728d'] as String?,
      otherBirthDefect728d: json['otherBirthDefect728d'] as String?,
      hasAllergyHistory: json['hasAllergyHistory'] as String?,
      allergen: json['allergen'] as String?,
      otherAllergen: json['otherAllergen'] as String?,
      isSga: json['isSga'] as String?,
      sgaType: json['sgaType'] as String?,
      isDead: json['isDead'] as String?,
      deathDate: json['deathDate'] as String?,
      deathCause: json['deathCause'] as String?,
      hasSpontaneousAbortionHistory: json['hasSpontaneousAbortionHistory'] as String?,
      spontaneousAbortionCount: json['spontaneousAbortionCount'] as String?,
      hasInducedAbortionHistory: json['hasInducedAbortionHistory'] as String?,
      inducedAbortionCount: json['inducedAbortionCount'] as String?,
      hasRecurrentAbortionHistory: json['hasRecurrentAbortionHistory'] as String?,
      recurrentAbortionCount: json['recurrentAbortionCount'] as String?,
      hasPretermBirthHistory: json['hasPretermBirthHistory'] as String?,
      pretermBirthCount: json['pretermBirthCount'] as String?,
      hasFetalDeadHistory: json['hasFetalDeadHistory'] as String?,
      fetalDeadCount: json['fetalDeadCount'] as String?,
      hasStillbirthHistory: json['hasStillbirthHistory'] as String?,
      stillbirthCount: json['stillbirthCount'] as String?,
      hasFetalMalformationHistory: json['hasFetalMalformationHistory'] as String?,
      fetalMalformationCount: json['fetalMalformationCount'] as String?,
      fetalMalformationInfo: json['fetalMalformationInfo'] as String?,
      otherPregnancyHistory: json['otherPregnancyHistory'] as String?,
      conceptionMethod: json['conceptionMethod'] as String?,
      expectedDeliveryDate: json['expectedDeliveryDate'] as String?,
      hasAbnormalHba1c: json['hasAbnormalHba1c'] as String?,
      hasHba1cGe55: json['hasHba1cGe55'] as String?,
      hasHba1cGe65: json['hasHba1cGe65'] as String?,
      hasDiabetes: json['hasDiabetes'] as String?,
      hasDiabetesMedication: json['hasDiabetesMedication'] as String?,
      hasGestationalHypertension: json['hasGestationalHypertension'] as String?,
      hasAnemia: json['hasAnemia'] as String?,
      anemiaSeverity: json['anemiaSeverity'] as String?,
      hasCmvInfection: json['hasCmvInfection'] as String?,
      hasRubellaInfection: json['hasRubellaInfection'] as String?,
      hasMacrosomia: json['hasMacrosomia'] as String?,
      hasPolyhydramnios: json['hasPolyhydramnios'] as String?,
      hasOligohydramnios: json['hasOligohydramnios'] as String?,
      hasHyperthyroidismInPregnancy: json['hasHyperthyroidismInPregnancy'] as String?,
      hasHypothyroidismInPregnancy: json['hasHypothyroidismInPregnancy'] as String?,
      hasPreeclampsia: json['hasPreeclampsia'] as String?,
      hasEclampsia: json['hasEclampsia'] as String?,
      hasHivInfection: json['hasHivInfection'] as String?,
      hasSyphilisInfection: json['hasSyphilisInfection'] as String?,
      otherDiseasesInPregnancy: json['otherDiseasesInPregnancy'] as String?,
      hasParentalMentalIllnessHistory: json['hasParentalMentalIllnessHistory'] as String?,
      hasParentalDrugAbuseHistory: json['hasParentalDrugAbuseHistory'] as String?,
      hasFamilyHearingLossHistory: json['hasFamilyHearingLossHistory'] as String?,
      hasParentalConsanguineousMarriage: json['hasParentalConsanguineousMarriage'] as String?,
      otherFamilyHistory: json['otherFamilyHistory'] as String?,
      maternalInpatientNo: json['maternalInpatientNo'] as String?,
      maternalAgeAtDelivery: json['maternalAgeAtDelivery'] as String?,
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      hospId: json['hospId'] as String? ?? '',
      hospName: json['hospName'] as String? ?? '',
      deptId: json['deptId'] as String?,
      deptName: json['deptName'] as String?,
      campusId: json['campusId'] as String?,
      campusName: json['campusName'] as String?,
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'childId': childId,
      'gestationalWeek': gestationalWeek,
      'gestationalDay': gestationalDay,
      'birthWeight': birthWeight,
      'birthLength': birthLength,
      'birthHeadCirc': birthHeadCirc,
      'gravidity': gravidity,
      'parity': parity,
      'fetusCount': fetusCount,
      'birthOrder': birthOrder,
      'deliveryMethod': deliveryMethod,
      'birthHospital': birthHospital,
      'birthCertificateNo': birthCertificateNo,
      'apgar1': apgar1,
      'apgar5': apgar5,
      'apgar10': apgar10,
      'hasBirthAsphyxia': hasBirthAsphyxia,
      'birthAsphyxiaSeverity': birthAsphyxiaSeverity,
      'hasInjury': hasInjury,
      'hasIntracranialHemorrhage': hasIntracranialHemorrhage,
      'intracranialHemorrhageLevel': intracranialHemorrhageLevel,
      'hasBirthDefect06d': hasBirthDefect06d,
      'birthDefect06d': birthDefect06d,
      'otherBirthDefect06d': otherBirthDefect06d,
      'hasBirthDefect728d': hasBirthDefect728d,
      'birthDefect728d': birthDefect728d,
      'otherBirthDefect728d': otherBirthDefect728d,
      'hasAllergyHistory': hasAllergyHistory,
      'allergen': allergen,
      'otherAllergen': otherAllergen,
      'isSga': isSga,
      'sgaType': sgaType,
      'isDead': isDead,
      'deathDate': deathDate,
      'deathCause': deathCause,
      'hasSpontaneousAbortionHistory': hasSpontaneousAbortionHistory,
      'spontaneousAbortionCount': spontaneousAbortionCount,
      'hasInducedAbortionHistory': hasInducedAbortionHistory,
      'inducedAbortionCount': inducedAbortionCount,
      'hasRecurrentAbortionHistory': hasRecurrentAbortionHistory,
      'recurrentAbortionCount': recurrentAbortionCount,
      'hasPretermBirthHistory': hasPretermBirthHistory,
      'pretermBirthCount': pretermBirthCount,
      'hasFetalDeadHistory': hasFetalDeadHistory,
      'fetalDeadCount': fetalDeadCount,
      'hasStillbirthHistory': hasStillbirthHistory,
      'stillbirthCount': stillbirthCount,
      'hasFetalMalformationHistory': hasFetalMalformationHistory,
      'fetalMalformationCount': fetalMalformationCount,
      'fetalMalformationInfo': fetalMalformationInfo,
      'otherPregnancyHistory': otherPregnancyHistory,
      'conceptionMethod': conceptionMethod,
      'expectedDeliveryDate': expectedDeliveryDate,
      'hasAbnormalHba1c': hasAbnormalHba1c,
      'hasHba1cGe55': hasHba1cGe55,
      'hasHba1cGe65': hasHba1cGe65,
      'hasDiabetes': hasDiabetes,
      'hasDiabetesMedication': hasDiabetesMedication,
      'hasGestationalHypertension': hasGestationalHypertension,
      'hasAnemia': hasAnemia,
      'anemiaSeverity': anemiaSeverity,
      'hasCmvInfection': hasCmvInfection,
      'hasRubellaInfection': hasRubellaInfection,
      'hasMacrosomia': hasMacrosomia,
      'hasPolyhydramnios': hasPolyhydramnios,
      'hasOligohydramnios': hasOligohydramnios,
      'hasHyperthyroidismInPregnancy': hasHyperthyroidismInPregnancy,
      'hasHypothyroidismInPregnancy': hasHypothyroidismInPregnancy,
      'hasPreeclampsia': hasPreeclampsia,
      'hasEclampsia': hasEclampsia,
      'hasHivInfection': hasHivInfection,
      'hasSyphilisInfection': hasSyphilisInfection,
      'otherDiseasesInPregnancy': otherDiseasesInPregnancy,
      'hasParentalMentalIllnessHistory': hasParentalMentalIllnessHistory,
      'hasParentalDrugAbuseHistory': hasParentalDrugAbuseHistory,
      'hasFamilyHearingLossHistory': hasFamilyHearingLossHistory,
      'hasParentalConsanguineousMarriage': hasParentalConsanguineousMarriage,
      'otherFamilyHistory': otherFamilyHistory,
      'maternalInpatientNo': maternalInpatientNo,
      'maternalAgeAtDelivery': maternalAgeAtDelivery,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'deptId': deptId,
      'deptName': deptName,
      'campusId': campusId,
      'campusName': campusName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
