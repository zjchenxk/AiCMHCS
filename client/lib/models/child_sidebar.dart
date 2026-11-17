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

  /// 因素列表排序权重（越严重的越靠前，绿色兜底最后）。
  int get severityOrder => switch (this) {
    HighRiskLevel.red => 0,
    HighRiskLevel.orange => 1,
    HighRiskLevel.yellow => 2,
    HighRiskLevel.purple => 3,
    HighRiskLevel.green => 4,
  };
}

/// 单条高危因素（按五色归属）。
class HighRiskFactor {
  /// 构造函数：注入级别、因素名称与说明。
  const HighRiskFactor({
    required this.level,
    required this.title,
    required this.detail,
  });

  /// 所属五色级别。
  final HighRiskLevel level;

  /// 因素名称（如「早产（32~33⁺⁶周）」）。
  final String title;

  /// 因素说明（测量值/管理建议）。
  final String detail;
}

/// 单条检查记录（历次检查时间轴项）。
class ChildExamRecord {
  /// 构造函数：注入检查日期、检查名称与检查结果。
  const ChildExamRecord({
    required this.date,
    required this.name,
    required this.result,
  });

  /// 检查日期。
  final DateTime date;

  /// 检查名称（如「发育筛查（ASQ-3）」）。
  final String name;

  /// 检查结果。
  final String result;
}

/// 右侧儿童信息侧边栏的展示数据。
///
/// 由 [MainViewModel.setCurrentChild] 以当前儿童基础档案构建（先出基础
/// 信息 + 演示数据），随后异步载入扩展档案与最近一次拍照头像后重建：
/// 扩展档案存在时按五色分级共识评估真实因素；扩展档案缺失时回退到
/// 内置演示数据（界面标注「演示数据」）。检查记录暂无后端表，固定为
/// 演示时间轴。实足年龄按日历计算；出生孕周 <37 周的早产儿在矫正窗口
/// 内同时给出矫正年龄（40 周基准，见 AgeUtil）。
class ChildSidebarData {
  /// 构造函数：注入侧边栏各展示字段。
  const ChildSidebarData({
    required this.name,
    required this.gender,
    required this.ageText,
    required this.correctedAgeText,
    required this.avatarBase64,
    required this.gravidityParity,
    required this.gestationalAge,
    required this.birthWeight,
    required this.phone,
    required this.riskLevel,
    required this.purpleOverlay,
    required this.factors,
    required this.exams,
    required this.riskIsMock,
    required this.examIsMock,
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

  /// 综合分级（红色/橙色/黄色/绿色，按因素最高级别）。
  final HighRiskLevel riskLevel;

  /// 是否为传染病（紫色）叠加标识。
  final bool purpleOverlay;

  /// 高危因素列表（按严重程度排序）。
  final List<HighRiskFactor> factors;

  /// 历次检查记录（新→旧）。
  final List<ChildExamRecord> exams;

  /// 高危分级/因素是否为演示数据。
  final bool riskIsMock;

  /// 检查记录是否为演示数据。
  final bool examIsMock;

  /// 五色分级中需要高亮的项（综合分级 + 紫色叠加）。
  Set<HighRiskLevel> get activeLevels => {
    riskLevel,
    if (purpleOverlay) HighRiskLevel.purple,
  };

  /// 由当前儿童基础档案 + 扩展档案（可空）+ 头像构建侧边栏数据。
  ///param child: 当前儿童上下文（姓名/性别/年龄/电话）
  ///param ext: 儿童扩展档案（为空时高危分级使用演示数据）
  ///param avatarBase64: 最近一次拍照头像（无记录传 null）
  ///param now: 业务当前时间（全局时间服务口径，检查时间轴据此生成）
  factory ChildSidebarData.build({
    required CurrentChild child,
    required ChildExtInfo? ext,
    required String? avatarBase64,
    required DateTime now,
  }) {
    final risk = _evaluateRisk(ext);
    final ageText = AgeUtil.formatAgeYmd(child.birthDate, now);
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
      avatarBase64: _blankToNull(avatarBase64),
      gravidityParity: _formatGravidityParity(ext),
      gestationalAge: _formatGestationalAge(ext) ?? _blankToNull(child.gestationalWeek),
      birthWeight: _formatBirthWeight(ext),
      phone: _blankToNull(child.phone),
      riskLevel: risk.level,
      purpleOverlay: risk.purple,
      factors: risk.factors,
      exams: _mockExams(now),
      riskIsMock: risk.isMock,
      examIsMock: true,
    );
  }

  /// 按扩展档案评估五色高危分级与因素（扩展档案为空时返回演示数据）。
  static _RiskEvaluation _evaluateRisk(ChildExtInfo? ext) {
    if (ext == null) return _mockRisk();

    final factors = <HighRiskFactor>[];
    var purple = false;

    void add(HighRiskLevel level, String title, String detail) {
      factors.add(HighRiskFactor(level: level, title: title, detail: detail));
    }

    void addPurple(String title, String detail) {
      purple = true;
      add(HighRiskLevel.purple, title, detail);
    }

    // 出生孕周：<32 周红色；32~33⁺⁶周橙色；34~36⁺⁶周黄色
    final week = _toInt(ext.gestationalWeek);
    final weekText = _formatGestationalAge(ext);
    if (week != null && weekText != null) {
      if (week < 32) {
        add(HighRiskLevel.red, '超早产（< 32 周）', '出生孕周 $weekText，需 NICU 救治与长期随访');
      } else if (week < 34) {
        add(HighRiskLevel.orange, '早产（32~33⁺⁶周）', '出生孕周 $weekText，属中危组');
      } else if (week < 37) {
        add(HighRiskLevel.yellow, '早产（34~36⁺⁶周）', '出生孕周 $weekText，属低危组');
      }
    }

    // 出生体重：<2000 g 红色；2000~2500 g 橙色；>4000 g 黄色（巨大儿）
    final weight = _toDouble(ext.birthWeight);
    if (weight != null) {
      final weightText = '${weight.round()} g';
      if (weight < 2000) {
        add(HighRiskLevel.red, '低出生体重（< 2000 g）', '出生体重 $weightText，需重点救治与随访');
      } else if (weight < 2500) {
        add(HighRiskLevel.orange, '低出生体重（2000~2500 g）', '出生体重 $weightText，属中危组');
      } else if (weight > 4000) {
        add(HighRiskLevel.yellow, '巨大儿（> 4000 g）', '出生体重 $weightText，属低危组');
      }
    }

    if (ext.hasBirthAsphyxia == '1') {
      final apgar5 = _toInt(ext.apgar5);
      final severe = apgar5 != null && apgar5 <= 3;
      add(
        severe ? HighRiskLevel.red : HighRiskLevel.orange,
        severe ? '重度出生窒息' : '出生窒息（5 min Apgar 4~7 分）',
        apgar5 == null ? '存在出生窒息史，需评估 HIE 风险' : 'Apgar 5 分钟 $apgar5 分，需神经发育随访',
      );
    }

    if (ext.hasIntracranialHemorrhage == '1') {
      add(HighRiskLevel.orange, '颅内出血（Ⅰ~Ⅱ级）', '存在颅内出血史，需神经发育随访');
    }

    if (ext.hasBirthDefect06d == '1' || ext.hasBirthDefect728d == '1') {
      add(HighRiskLevel.orange, '先天性疾病', '存在出生缺陷，需住院观察和/或长期护理治疗');
    }

    if (ext.isSga == '1') {
      add(HighRiskLevel.orange, '小于胎龄儿（SGA）', '按中危组管理，关注体重与追赶生长');
    }

    if (ext.hasDiabetes == '1') {
      add(HighRiskLevel.yellow, '母亲妊娠期糖尿病', '母亲孕期合并妊娠期糖尿病，属低危因素');
    }
    if (ext.hasGestationalHypertension == '1' || ext.hasPreeclampsia == '1' || ext.hasEclampsia == '1') {
      add(HighRiskLevel.yellow, '母亲妊娠期高血压疾病', '含妊娠期高血压/子痫前期，属低危因素');
    }
    if (ext.hasHyperthyroidismInPregnancy == '1' || ext.hasHypothyroidismInPregnancy == '1') {
      add(HighRiskLevel.yellow, '母亲甲状腺疾病', '母亲孕期合并甲状腺疾病，属低危因素');
    }
    if (ext.hasAnemia == '1') {
      final severity = switch (ext.anemiaSeverity) {
        '1' => '（60~110 g/L）',
        '2' => '（40~60 g/L）',
        '3' => '（≤ 40 g/L）',
        _ => '',
      };
      add(HighRiskLevel.yellow, '母亲孕期贫血', '血红蛋白降低$severity，属低危因素');
    }
    if (ext.hasMacrosomia == '1') {
      add(HighRiskLevel.yellow, '母亲孕期巨大儿', '胎儿巨大儿，注意产伤与低血糖监测');
    }

    // 紫色：传染病专项管理，可与其它颜色叠加
    if (ext.hasHivInfection == '1') {
      addPurple('母亲 HIV 感染', '按传染病防治要求专项管理，可与其它颜色叠加');
    }
    if (ext.hasSyphilisInfection == '1') {
      addPurple('母亲梅毒感染', '按传染病防治要求专项管理，可与其它颜色叠加');
    }
    if (ext.hasCmvInfection == '1') {
      addPurple('母亲巨细胞病毒感染', 'TORCH 感染，按传染病专项管理，可与其它颜色叠加');
    }
    if (ext.hasRubellaInfection == '1') {
      addPurple('母亲风疹病毒感染', 'TORCH 感染，按传染病专项管理，可与其它颜色叠加');
    }

    // 没有任何主分级因素时归绿色（仅紫色叠加也属绿色基础分级）
    if (!factors.any((f) => f.level.isPrimary)) {
      factors.add(
        const HighRiskFactor(
          level: HighRiskLevel.green,
          title: '正常新生儿',
          detail: '无母亲及胎儿、新生儿的高危因素',
        ),
      );
    }
    factors.sort((a, b) => a.level.severityOrder.compareTo(b.level.severityOrder));

    return _RiskEvaluation(
      level: _highestPrimary(factors),
      purple: purple,
      factors: factors,
      isMock: false,
    );
  }

  /// 内置演示数据（扩展档案缺失时使用，界面标注「演示数据」）。
  static _RiskEvaluation _mockRisk() {
    const factors = [
      HighRiskFactor(
        level: HighRiskLevel.orange,
        title: '早产（32~33⁺⁶周）',
        detail: '示例：出生孕周 33 周 + 4 天，属中危组',
      ),
      HighRiskFactor(
        level: HighRiskLevel.orange,
        title: '低出生体重（2000~2500 g）',
        detail: '示例：出生体重 2280 g，关注体重增长与追赶生长',
      ),
      HighRiskFactor(
        level: HighRiskLevel.yellow,
        title: '母亲妊娠期高血压疾病',
        detail: '示例：母亲孕期合并妊娠期高血压，属低危因素',
      ),
      HighRiskFactor(
        level: HighRiskLevel.purple,
        title: '母亲梅毒感染',
        detail: '示例：按传染病防治要求专项管理，可与其它颜色叠加',
      ),
    ];
    return _RiskEvaluation(
      level: HighRiskLevel.orange,
      purple: true,
      factors: factors,
      isMock: true,
    );
  }

  /// 取主分级中的最高级别（绿色兜底）。
  static HighRiskLevel _highestPrimary(List<HighRiskFactor> factors) {
    var level = HighRiskLevel.green;
    for (final factor in factors) {
      if (!factor.level.isPrimary) continue;
      if (factor.level.severityOrder < level.severityOrder) level = factor.level;
    }
    return level;
  }

  /// 演示检查记录（新→旧，日期基于业务当前时间倒推）。
  static List<ChildExamRecord> _mockExams(DateTime now) {
    return [
      ChildExamRecord(
        date: now.subtract(const Duration(days: 3)),
        name: '新生儿行为神经测定（NBNA）',
        result: '38 分（满分 40 分），属正常范围',
      ),
      ChildExamRecord(
        date: now.subtract(const Duration(days: 16)),
        name: '听力筛查（DPOAE）',
        result: '双耳通过，建议 1 岁复查',
      ),
      ChildExamRecord(
        date: now.subtract(const Duration(days: 45)),
        name: '体格生长评估',
        result: '体重 4.8 kg（P45），身长 56.2 cm（P50），头围 38.5 cm（P55）',
      ),
      ChildExamRecord(
        date: now.subtract(const Duration(days: 92)),
        name: '发育筛查（ASQ-3）',
        result: '沟通、粗大动作、精细动作、解决问题、个人-社会各能区均正常',
      ),
      ChildExamRecord(
        date: now.subtract(const Duration(days: 150)),
        name: '心脏彩超',
        result: '卵圆孔未闭（约 2.5 mm），建议 6 月龄复查',
      ),
    ];
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

  /// 字符串转小数（空串/非法值返回 null）。
  static double? _toDouble(String? value) => double.tryParse(value?.trim() ?? '');
}

/// 高危评估结果（内部使用）。
class _RiskEvaluation {
  const _RiskEvaluation({
    required this.level,
    required this.purple,
    required this.factors,
    required this.isMock,
  });

  /// 综合分级（红/橙/黄/绿）。
  final HighRiskLevel level;

  /// 是否叠加紫色（传染病）标识。
  final bool purple;

  /// 高危因素列表。
  final List<HighRiskFactor> factors;

  /// 是否为演示数据。
  final bool isMock;
}
