/// 初筛界面级联规则（纯函数，供页面与单元测试共用）。
///
/// 规则（2026-11-25 需求）：
/// - 预警征象筛查与语言功能/社会交往能力询问**均为〔未见异常〕** →
///   初筛结果＝未见异常；任一项存在非〔未见异常〕的选中项 →
///   初筛结果＝异常；
/// - 初筛结果＝未见异常 → 指导建议＝默认文本、有无转诊＝无；
/// - 初筛结果＝异常 → 指导建议＝空、有无转诊＝有。
class AsdCheckFlow {
  AsdCheckFlow._();

  /// 未见异常文案（与初筛记录协议值一致）。
  static const String noneAbnormal = '未见异常';

  /// 异常文案（与初筛记录协议值一致）。
  static const String abnormal = '异常';

  /// 初筛未见异常时的默认指导建议文本。
  static const String normalGuidance = '请定期带儿童接受心理行为发育评估';

  /// 推导初筛结果：两项询问结果均为〔未见异常〕才返回未见异常，否则异常
  /// （含空集合等非法中间态，按异常处理，交由保存校验拦截）。
  static String deriveResult({required Set<String> warningSigns, required Set<String> languageSocial}) {
    final warningNormal = warningSigns.length == 1 && warningSigns.contains(noneAbnormal);
    final languageNormal = languageSocial.length == 1 && languageSocial.contains(noneAbnormal);
    return (warningNormal && languageNormal) ? noneAbnormal : abnormal;
  }

  /// 初筛结果对应的指导建议：未见异常＝默认文本，异常＝空串。
  static String guidanceFor(String checkResult) => checkResult == abnormal ? '' : normalGuidance;

  /// 初筛结果对应的有无转诊码值：未见异常＝0（无），异常＝1（有）。
  static String referralFlagFor(String checkResult) => checkResult == abnormal ? '1' : '0';
}
