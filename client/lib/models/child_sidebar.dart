import 'package:client/models/current_child.dart';
import 'package:client/utils/age_util.dart';
import 'package:common/model.dart';

/// 五色高危分级（《高危新生儿分类分级管理专家共识（2023）》）。
///
/// 绿色-正常、黄色-低危、橙色-中危、红色-高危；紫色为传染病专项
/// 标识，可与其它任意颜色叠加（多因素同时符合时以最高级别为准）。
enum HighRiskLevel { green, yellow, orange, red, purple }

extension HighRiskLevelX on HighRiskLevel {
  /// 分级中文名称。
  String get label => switch (this) {
    HighRiskLevel.green => '绿色',
    HighRiskLevel.yellow => '黄色',
    HighRiskLevel.orange => '橙色',
    HighRiskLevel.red => '红色',
    HighRiskLevel.purple => '紫色',
  };

  /// 分级含义（图例 Tooltip 文案）。
  String get description => switch (this) {
    HighRiskLevel.green => '绿色：正常新生儿，无高危因素',
    HighRiskLevel.yellow => '黄色：低危组，母婴同室观察',
    HighRiskLevel.orange => '橙色：中危组，需住院诊治及长期护理',
    HighRiskLevel.red => '红色：高危组，需 NICU 救治及长期随访',
    HighRiskLevel.purple => '紫色：传染病专项管理，可与其它颜色叠加',
  };

  /// 是否参与综合分级（紫色为叠加标识，不单独作为综合分级）。
  bool get isPrimary => this != HighRiskLevel.purple;

  /// 因素列表排序权重（越严重的越靠前，未设置颜色最后）。
  int get severityOrder => switch (this) {
    HighRiskLevel.red => 0,
    HighRiskLevel.orange => 1,
    HighRiskLevel.yellow => 2,
    HighRiskLevel.purple => 3,
    HighRiskLevel.green => 4,
  };
}

/// 单条高危因素（来源 CHILD_HIGH_RISK_FACTOR，名称与颜色为保存当时的
/// 字典值快照）。
class HighRiskFactor {
  /// 构造函数：注入五色归属、因素名称与备注。
  const HighRiskFactor({
    required this.riskColor,
    required this.title,
    this.remark = '',
  });

  /// 高危颜色（中文五色；null/空串表示字典未设置颜色）。
  final String? riskColor;

  /// 高危因素名称（RISK_FACTOR_NAME）。
  final String title;

  /// 备注（REMARK；空串表示无备注，界面不显示）。
  final String remark;
}

/// 单条检查记录（历次检查时间轴项，来源 CHILD_CHECK_RECORD）。
class ChildExamRecord {
  /// 构造函数：注入检查日期、检查名称与检查结果。
  const ChildExamRecord({
    required this.date,
    required this.name,
    required this.result,
  });

  /// 检查日期（CHECK_DATE，yyyy-MM-dd）。
  final String date;

  /// 检查名称（CHECK_TYPE，如「孤独症初筛」）。
  final String name;

  /// 检查结果（CHECK_RESULT；空串表示未填写，界面不显示结果行）。
  final String result;
}

/// 右侧儿童信息侧边栏的展示数据。
///
/// 由 [MainViewModel.setCurrentChild] 以当前儿童基础档案构建（先出基础
/// 信息），随后并行载入扩展档案、最近一次拍照头像与
/// CHILD_HIGH_RISK_FACTOR 高危因素记录后重建：五色分级取高危因素颜色
/// 的最高级别（紫色叠加），高危因素列表展示名称与备注（REMARK）。
/// 检查记录暂无后端表，固定为演示时间轴。实足年龄按日历计算；出生
/// 孕周 <37 周的早产儿在矫正窗口内同时给出矫正年龄（40 周基准，见
/// AgeUtil）。
class ChildSidebarData {
  /// 构造函数：注入侧边栏各展示字段。
  const ChildSidebarData({
    required this.name,
    required this.gender,
    required this.ageText,
    required this.correctedAgeText,
    required this.birthDateText,
    required this.avatarBase64,
    required this.gravidityParity,
    required this.gestationalAge,
    required this.birthWeight,
    required this.phone,
    required this.riskLevel,
    required this.purpleOverlay,
    required this.factors,
    required this.factorsLoaded,
    required this.factorsLoadFailed,
    required this.exams,
    required this.examsLoaded,
    required this.examsLoadFailed,
  });

  /// 姓名。
  final String name;

  /// 性别（中文「男」/「女」，空串表示未填写）。
  final String gender;

  /// 实足年龄（岁/月/天）。
  final String ageText;

  /// 早产儿矫正年龄（岁/月/天；非早产、未到预产期或已超出矫正窗口
  /// 为 null，界面不展示）。
  final String? correctedAgeText;

  /// 出生日期（yyyy-MM-dd；缺失时为 null，界面不展示）。
  final String? birthDateText;

  /// 头像 base64（CHILD_PHOTO.AVATAR_IMAGE，无记录时为 null）。
  final String? avatarBase64;

  /// 孕次/产次（如「G2 P1」）。
  final String? gravidityParity;

  /// 出生孕周（如「38周+2天」）。
  final String? gestationalAge;

  /// 出生体重（如「3250 g」）。
  final String? birthWeight;

  /// 联系电话。
  final String? phone;

  /// 综合分级（红色/橙色/黄色/绿色，取高危因素中的最高级别）。
  final HighRiskLevel riskLevel;

  /// 是否为传染病（紫色）叠加标识。
  final bool purpleOverlay;

  /// 高危因素列表（按五色严重程度 + 名称排序）。
  final List<HighRiskFactor> factors;

  /// 高危因素是否已从 CHILD_HIGH_RISK_FACTOR 加载完成（false 时界面
  /// 显示加载状态，避免把「未加载」误显示为「无高危因素」）。
  final bool factorsLoaded;

  /// 高危因素加载是否失败（失败时界面提供重试）。
  final bool factorsLoadFailed;

  /// 历次检查记录（新→旧，来源 CHILD_CHECK_RECORD）。
  final List<ChildExamRecord> exams;

  /// 检查记录是否已从 CHILD_CHECK_RECORD 加载完成（false 时界面显示
  /// 加载状态，避免把「未加载」误显示为「暂无检查记录」）。
  final bool examsLoaded;

  /// 检查记录加载是否失败（失败时界面提供重试）。
  final bool examsLoadFailed;

  /// 五色分级中需要高亮的项（综合分级 + 紫色叠加）。
  Set<HighRiskLevel> get activeLevels => {
    riskLevel,
    if (purpleOverlay) HighRiskLevel.purple,
  };

  /// 由当前儿童基础档案 + 扩展档案（可空）+ 头像 + 已保存高危因素 +
  /// 已汇总检查记录构建侧边栏数据。
  ///param child: 当前儿童上下文（姓名/性别/年龄/电话/出生日期）
  ///param ext: 儿童扩展档案（可空；用于 G/P、出生孕周/体重与矫正年龄）
  ///param avatarBase64: 最近一次拍照头像（无记录传 null）
  ///param highRiskFactors: CHILD_HIGH_RISK_FACTOR 已保存记录（可为空）
  ///param factorsLoaded: 高危因素是否加载完成（成功后置 true）
  ///param factorsLoadFailed: 高危因素加载是否失败（失败时界面提供重试）
  ///param checkRecords: CHILD_CHECK_RECORD 检查记录（可为空）
  ///param checkRecordsLoaded: 检查记录是否加载完成（成功后置 true）
  ///param checkRecordsLoadFailed: 检查记录加载是否失败（失败时界面提供重试）
  ///param now: 业务当前时间（全局时间服务口径，年龄计算用）
  factory ChildSidebarData.build({
    required CurrentChild child,
    required ChildExtInfo? ext,
    required String? avatarBase64,
    required List<ChildHighRiskFactor> highRiskFactors,
    required bool factorsLoaded,
    required bool factorsLoadFailed,
    required List<ChildCheckRecord> checkRecords,
    required bool checkRecordsLoaded,
    required bool checkRecordsLoadFailed,
    required DateTime now,
  }) {
    final risk = _classifyRisk(highRiskFactors);
    final ageText = AgeUtil.formatAgeYmd(child.birthDate, now);
    // 检查记录 → 时间轴展示项（日期/类型/结果取自 CHECK_DATE/CHECK_TYPE/
    // CHECK_RESULT；顺序沿用服务端 CHECK_DATE DESC, ID DESC）
    final exams = [
      for (final record in checkRecords)
        ChildExamRecord(
          date: record.checkDate.trim(),
          name: _blankToNull(record.checkType) ?? '检查记录',
          result: _blankToNull(record.checkResult) ?? '',
        ),
    ];
    return ChildSidebarData(
      name: child.name,
      gender: child.gender,
      ageText: ageText.isNotEmpty ? ageText : child.actualAge,
      // 早产儿在矫正窗口内额外展示矫正年龄（40 周基准，见 AgeUtil）
      correctedAgeText: AgeUtil.formatCorrectedAge(
        birthDate: child.birthDate,
        now: now,
        gestationalWeek: ext?.gestationalWeek,
        gestationalDay: ext?.gestationalDay,
      ),
      birthDateText: _formatDate(child.birthDate),
      avatarBase64: _blankToNull(avatarBase64),
      gravidityParity: _formatGravidityParity(ext),
      gestationalAge: _formatGestationalAge(ext) ?? _blankToNull(child.gestationalWeek),
      birthWeight: _formatBirthWeight(ext),
      phone: _blankToNull(child.phone),
      riskLevel: risk.level,
      purpleOverlay: risk.purple,
      factors: risk.factors,
      factorsLoaded: factorsLoaded,
      factorsLoadFailed: factorsLoadFailed,
      exams: exams,
      examsLoaded: checkRecordsLoaded,
      examsLoadFailed: checkRecordsLoadFailed,
    );
  }

  /// 按已保存高危因素计算综合分级与展示列表。
  ///
  /// 综合分级 = 非紫色因素中的最高级别（红 > 橙 > 黄 > 绿）；紫色作为
  /// 叠加标识单独记录。未设置颜色的因素只展示、不参与分级。库内无
  /// 记录时归绿色并给出「无高危因素」占位。
  static ({HighRiskLevel level, bool purple, List<HighRiskFactor> factors}) _classifyRisk(List<ChildHighRiskFactor> rows) {
    var level = HighRiskLevel.green;
    var purple = false;
    final factors = <HighRiskFactor>[];
    for (final row in rows) {
      final color = _blankToNull(row.riskColor);
      final factorLevel = _levelOfColor(color);
      if (factorLevel == HighRiskLevel.purple) purple = true;
      if (factorLevel != null && factorLevel.isPrimary && factorLevel.severityOrder < level.severityOrder) {
        level = factorLevel;
      }
      final name = row.riskFactorName.trim();
      factors.add(
        HighRiskFactor(
          riskColor: color,
          title: name.isEmpty ? '未命名高危因素' : name,
          remark: _blankToNull(row.remark) ?? '',
        ),
      );
    }
    if (factors.isEmpty) {
      factors.add(
        const HighRiskFactor(
          riskColor: '绿色',
          title: '无高危因素',
          remark: '无母亲及胎儿、新生儿的高危因素',
        ),
      );
    }
    factors.sort((a, b) {
      final severityA = _severityOfColor(a.riskColor);
      final severityB = _severityOfColor(b.riskColor);
      if (severityA != severityB) return severityA.compareTo(severityB);
      return a.title.compareTo(b.title);
    });
    return (level: level, purple: purple, factors: factors);
  }

  /// 中文高危颜色转五色级别（未设置/非法值为 null）。
  static HighRiskLevel? _levelOfColor(String? color) => switch (color) {
    '绿色' => HighRiskLevel.green,
    '黄色' => HighRiskLevel.yellow,
    '橙色' => HighRiskLevel.orange,
    '红色' => HighRiskLevel.red,
    '紫色' => HighRiskLevel.purple,
    _ => null,
  };

  /// 因素列表排序权重（未设置颜色排在已知五色之后）。
  static int _severityOfColor(String? color) => _levelOfColor(color)?.severityOrder ?? 5;

  /// 出生日期格式化（yyyy-MM-dd；缺失返回 null）。
  static String? _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch <= 0) return null;
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// 孕次/产次格式化（如「G2 P1」；均未填写返回 null）。
  static String? _formatGravidityParity(ChildExtInfo? ext) {
    final gravidity = _blankToNull(ext?.gravidity);
    final parity = _blankToNull(ext?.parity);
    if (gravidity == null && parity == null) return null;
    return [
      if (gravidity != null) 'G$gravidity',
      if (parity != null) 'P$parity',
    ].join(' ');
  }

  /// 出生孕周格式化（如「38周+2天」；孕周未填写返回 null）。
  static String? _formatGestationalAge(ChildExtInfo? ext) {
    final week = _blankToNull(ext?.gestationalWeek);
    final day = _blankToNull(ext?.gestationalDay);
    if (week == null) return null;
    if (day == null || _toInt(day) == 0) return '$week周';
    return '$week周+$day天';
  }

  /// 出生体重格式化（如「3250 g」；未填写返回 null）。
  static String? _formatBirthWeight(ChildExtInfo? ext) {
    final raw = _blankToNull(ext?.birthWeight);
    if (raw == null) return null;
    final weight = double.tryParse(raw);
    return weight == null ? '$raw g' : '${weight.round()} g';
  }

  /// 去空格转 null（达梦空串入库为 NULL，协议层统一按缺省处理）。
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 字符串转整数（空串/非法值返回 null）。
  static int? _toInt(String? value) => int.tryParse(value?.trim() ?? '');
}
