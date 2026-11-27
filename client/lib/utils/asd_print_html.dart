import 'dart:convert';

import 'package:common/model.dart';

import 'package:client/utils/asd_printing.dart';

/// 孤独症初筛打印 HTML 生成器：把打印数据包渲染为打印用 HTML 文本
/// （真文本矢量渲染——打印清晰、「另存为 PDF」后文字可复制）。
///
/// 两类单据：
/// - [buildRecordSheetHtml]：初筛记录表（国家规范表 2 婴儿期 3/6/8/12、
///   表 3 幼儿期 18/24/30/36、表 4 学龄前期 48/60/72，黑边框表格）；
/// - [buildReferralNoteHtml]：初筛转诊单（附件 3，上下两联 + 中间虚线
///   裁切线）。
///
/// 数据口径见需求 3.6~3.16 / 4.4~4.16：编号 17 格 ← HEALTH_NO（逐字符
/// 分格，空则空框）；姓名/性别（码值转汉字）/出生日期 ← CHILD_INFO；
/// 身份证 18 格 ← CERTIFICATE_NO（服务端解密下发）；家长姓名/电话 ←
/// 监护人（ORDER=1 或关系母亲/父亲优先，电话回退儿童本人）；各栏勾选
/// ← ASD_INITIAL_SCREENING 对应字段；医生签名 = 姓名 + SIGNATURE_IMAGE
/// （base64 图片，高度约 10mm）；医疗机构 ← HOSP_NAME。
class AsdPrintHtml {
  AsdPrintHtml._();

  /// HTML 转义（儿童姓名/保健号等用户数据防注入）。
  static String _esc(String value) => HtmlEscape().convert(value);

  /// 打印页公共样式：A4 纵向、宋体/雅黑矢量文本、黑边框。表格经
  /// `.fill` 撑到固定高（Chromium 把多余高度按行分摊），使整表充满 A4。
  static const String _commonStyle = '''
  @page { size: A4 portrait; margin: 10mm; }
  * { box-sizing: border-box; }
  body { font-family: SimSun, "Microsoft YaHei", serif; font-size: 10.5pt;
         color: #000; margin: 0; }
  h1, h2 { text-align: center; margin: 0 0 3mm 0; font-weight: bold; }
  h1 { font-size: 14pt; }
  h2 { font-size: 12pt; }
  .sheet { width: 100%; }
  .boxes span { display: inline-block; width: 4mm; height: 4.6mm;
                border: 1px solid #000; margin-right: 0.8mm;
                text-align: center; font-size: 8pt; line-height: 4.6mm; }
  .u { display: inline-block; border-bottom: 1px solid #000;
       text-align: center; font-weight: bold; }
  .row { margin: 3mm 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  /* 外框 3px：表格右缘落在小数像素位置（内容宽 190mm≈718.11px），1px
     细线会被拆分抗锯齿成淡发丝线；加粗后拆分仍有实心深色核心，同时
     「粗外框 + 细内格」也更贴近国标样表的原有风格。 */
  table.fill { height: 222mm; border: 3px solid #000; }
  td, th { border: 1px solid #000; padding: 2mm 1.6mm; vertical-align: top;
           font-size: 10.5pt; text-align: left; }
  th { text-align: center; font-size: 12pt; font-weight: bold; height: 9mm; }
  .lbl { text-align: center; vertical-align: middle; }
  .opt { display: block; position: relative; padding: 1mm 0 1mm 6mm; }
  .opt .mark { position: absolute; left: 0; top: 1.3mm; width: 6mm; }
  .note { font-size: 8.5pt; margin-top: 3mm; line-height: 1.6; }
  .divider { border-top: 1px dashed #000; margin: 5mm 0; }
  .bold { font-weight: bold; }
''';

  /// 包装为完整打印 HTML 文档：head 内含公共样式与自动打印脚本
  /// （文档 onload 延时 300ms 后 focus + print，由浏览器矢量渲染，
  /// 「另存为 PDF」导出的文字可复制）。
  static String _wrap(String body) =>
      '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>$_commonStyle</style>
<script>
window.onload = function () {
  setTimeout(function () { window.focus(); window.print(); }, 300);
};
</script>
</head>
<body>
$body
</body>
</html>''';

  /// 勾选标记：checked 为真显示 ☑（方框内勾），否则 □；order 非空时显示
  /// 「序号 名称」，为空仅显示名称（转诊单选项无序号）。
  static String _opt(String order, String label, bool checked, {bool withOrder = true}) {
    final mark = checked ? '☑' : '□';
    final num = (withOrder && order.isNotEmpty) ? '$order ' : '';
    return '<span class="opt"><span class="mark">$mark</span>$num$label</span>';
  }

  /// 无序号勾选（转诊单选项）。
  static String _optPlain(String label, bool checked) => _opt('', label, checked, withOrder: false);

  /// 下划线字段：标签 + 值（下划线上方居中加粗，与原件手写感一致）。
  static String _uField(String label, String value, String width, {bool bold = false}) {
    final labelHtml = bold ? '<b>$label</b>' : label;
    return '<span style="margin-right:3mm">$labelHtml　<span class="u" '
        'style="min-width:$width">$value</span></span>';
  }

  /// 下划线值（无标签）。
  static String _uText(String value, String width) {
    return '<span class="u" style="min-width:$width">$value</span>';
  }

  /// 编号行（17 格：HEALTH_NO 逐字符分格，空则空框；center 为真时整行
  /// 居中——初筛记录表表头两行按国家样表居中排布）。
  static String _noRow(String label, String healthNo, {bool center = false}) {
    final cells = StringBuffer();
    for (var i = 0; i < 17; i++) {
      final ch = i < healthNo.length ? _esc(healthNo[i]) : '';
      cells.write('<span>$ch</span>');
    }
    return '<div class="row"${center ? ' style="text-align:center"' : ''}>'
        '<b>$label</b>　<span class="boxes">$cells</span></div>';
  }

  /// 检查/填写日期：___年___月___日（数字与年月日间不留空格、下划线按
  /// 表格列宽收敛，保证单行不换行）。
  static String _dateLine(String? date) {
    final d = DateTime.tryParse(date ?? '');
    return '${_uText(d == null ? '' : '${d.year}', '10mm')}年'
        '${_uText(d == null ? '' : '${d.month}', '6mm')}月'
        '${_uText(d == null ? '' : '${d.day}', '6mm')}日';
  }

  /// ===== 初筛记录表（表 2/3/4） =====

  /// 月龄表头（48/60/72 → 4/5/6 岁）。
  static String _monthHeader(int month) => switch (month) {
    48 => '4 岁',
    60 => '5 岁',
    72 => '6 岁',
    _ => '$month 月龄',
  };

  /// 初筛记录表打印 HTML。
  ///param months: 本表覆盖的月龄组（[3,6,8,12] / [18,24,30,36] / [48,60,72]）
  ///param stageTitle: 阶段标题（婴儿期（0～1岁）等）
  static String buildRecordSheetHtml({
    required PrintBundle bundle,
    required List<int> months,
    required String stageTitle,
  }) {
    final child = bundle.child;
    final birth = DateTime.tryParse(child.birthDate);
    final headers = months.map((m) => '<th>${_monthHeader(m)}</th>').join();

    // 各月龄列的四个栏目
    final warningCells = months.map((m) => '<td>${_warningOptions(bundle, m)}</td>').join();
    final languageCells = months.map((m) => '<td>${_languageOptions(bundle, m)}</td>').join();
    final resultCells = months.map((m) {
      final value = bundle.recordOf(m)?.checkResult ?? '';
      return '<td>${_opt('1', '未见异常', value == '未见异常')}${_opt('2', '异常', value == '异常')}</td>';
    }).join();
    final referralCells = months.map((m) => '<td>${_referralBlock(bundle, m)}</td>').join();
    final dateCells = months.map((m) {
      final date = bundle.recordOf(m)?.checkDate ?? '';
      return '<td>${_dateLine(date)}</td>';
    }).join();
    final signatureCells = months.map((m) {
      final r = bundle.recordOf(m);
      final sig = r == null ? null : bundle.doctorSignatures[r.doctorId];
      final sigImg = (sig == null || sig.isEmpty) ? '' : '<img src="data:image/jpeg;base64,$sig" style="height:10mm;vertical-align:middle;margin-left:2mm">';
      return '<td style="height:12mm">${r == null ? '' : '${_esc(r.doctorName)}$sigImg'}</td>';
    }).join();
    final hospitalCells = months.map((m) {
      final r = bundle.recordOf(m);
      return '<td>${r == null ? '' : _esc(r.hospName)}</td>';
    }).join();

    return _wrap('''
<div class="sheet">
  <h1>0～6岁儿童心理行为发育初筛记录表</h1>
  <h2>$stageTitle</h2>
  ${_noRow('编号', child.healthNo ?? '', center: true)}
  <div class="row" style="text-align:center">
    ${_uField('儿童姓名', _esc(child.name), '30mm', bold: true)}
    ${_uField('性别', _sexLabel(child.sex), '18mm', bold: true)}
    <span><b>出生日期</b>　${_uText(birth == null ? '' : '${birth.year}', '12mm')} 年 ${_uText(birth == null ? '' : '${birth.month}', '8mm')} 月 ${_uText(birth == null ? '' : '${birth.day}', '8mm')} 日</span>
  </div>
  <table class="fill">
    <colgroup><col style="width:8mm"><col style="width:17mm">${months.map((_) => '<col>').join()}</colgroup>
    <tr><th colspan="2">项目</th>$headers</tr>
    <tr>
      <td rowspan="2" style="text-align:center;vertical-align:middle"><b>心<br>理<br>行<br>为<br>发<br>育<br>初<br>筛</b></td>
      <td class="lbl"><b>预警征象筛查</b></td>
      $warningCells
    </tr>
    <tr><td class="lbl"><b>语言功能和社会交往能力询问</b></td>$languageCells</tr>
    <tr><td colspan="2" class="lbl"><b>初筛结果</b></td>$resultCells</tr>
    <tr><td colspan="2" class="lbl"><b>转诊建议</b></td>$referralCells</tr>
    <tr><td colspan="2" class="lbl"><b>检查日期</b></td>$dateCells</tr>
    <tr><td colspan="2" class="lbl"><b>医生签名</b></td>$signatureCells</tr>
    <tr><td colspan="2" class="lbl"><b>医疗机构<br>名称</b></td>$hospitalCells</tr>
  </table>
  <div class="note">注：心理行为发育初筛“预警征象筛查”、“语言功能和社会交往能力询问”、“初筛结果”以及“转诊建议”部分，检查时发现相应情况在“□”内打“√”。检查日期介于两个月龄段之间的按最近的小月龄内容进行测查和记录。</div>
</div>''');
  }

  /// 预警征象选项（需求 3.10）：第一项【0 未见异常】；其余取 SCALE_WSCMBD
  /// 条目（序号 ITEM_ORDER、名称 ITEM_NAME）；按 WARNING_SIGN_RESULT 勾选。
  static String _warningOptions(PrintBundle bundle, int month) {
    final warning = bundle.recordOf(month)?.warningSignResult.trim() ?? '';
    final normal = warning == '未见异常';
    final items = bundle.scaleByMonth[month] ?? const <WscmbdItem>[];
    return [
      _opt('0', '未见异常', normal),
      for (final item in items) _opt('${item.itemOrder}', _esc(item.itemName), warning.contains(item.itemName)),
    ].join();
  }

  /// 语言功能和社会交往能力询问选项（需求 3.11）。
  static String _languageOptions(PrintBundle bundle, int month) {
    final value = bundle.recordOf(month)?.languageSocialCommunicationResult.trim() ?? '';
    String item(int order, String label) => _opt('$order', label, value.contains(label));
    return [
      item(1, '未见异常'),
      item(2, '语言功能障碍或倒退'),
      item(3, '社会交往能力障碍或倒退'),
    ].join();
  }

  /// 转诊建议块（需求 3.13）：无 / 有 + 机构名下划线（下划线为样表常显
  /// 栏——未转诊时留空待手写；协议中无转诊时 referralHospName 存「无」，
  /// 不回显到下划线上）。未录入的时段整栏留空，不勾选任何项。
  static String _referralBlock(PrintBundle bundle, int month) {
    final record = bundle.recordOf(month);
    if (record == null) {
      return '${_opt('1', '无', false)}${_opt('2', '有，上转接诊医疗机构名称', false)}'
          '<div style="margin:2mm 0 0 6mm">${_uText('', '30mm')}</div>';
    }
    final has = record.hasReferral == '1';
    final hosp = has ? record.referralHospName : '';
    return '${_opt('1', '无', !has)}${_opt('2', '有，上转接诊医疗机构名称', has)}'
        '<div style="margin:2mm 0 0 6mm">${_uText(_esc(hosp), '30mm')}</div>';
  }

  /// ===== 初筛转诊单（附件 3，上下两联） =====

  /// 初筛转诊单打印 HTML（两联，中间虚线裁切线）。
  static String buildReferralNoteHtml({required PrintBundle bundle}) {
    final slip1 = _slip(bundle, '（第一联 乡镇卫生院或社区卫生服务中心留存）');
    final slip2 = _slip(
      bundle,
      '（第二联 由家长携带至县级接诊机构）',
      extraNote: '备注：就诊时须携带本转诊单',
    );
    return _wrap('$slip1<div class="divider"></div>$slip2');
  }

  /// 单联转诊单。
  static String _slip(PrintBundle bundle, String subtitle, {String? extraNote}) {
    final child = bundle.child;
    final guardian = bundle.preferredGuardian;
    final guardianPhone = guardian?.phone ?? '';
    final phone = guardianPhone.isNotEmpty ? guardianPhone : (child.phone ?? '');
    final record = bundle.records.isNotEmpty ? bundle.records.first : null;
    final birth = DateTime.tryParse(child.birthDate);
    final cert = child.certificateNo?.trim() ?? '';

    // 转诊原因：预警征象筛查结果（未见异常勾首项，否则勾「异常」并注明全部异常项）
    final warning = record?.warningSignResult.trim() ?? '';
    final warningNormal = warning == '未见异常';
    // 语言功能及社会交往功能询问三项
    final language = record?.languageSocialCommunicationResult.trim() ?? '';

    return '''
<div class="sheet">
  <h1>0～6岁儿童心理行为发育初筛转诊单</h1>
  <h2>$subtitle</h2>
  ${extraNote == null ? '' : '<div style="text-align:center">$extraNote</div>'}
  ${_noRow('编　　号', child.healthNo ?? '')}
  <div class="row">
    ${_uField('儿童姓名', _esc(child.name), '28mm')}
    ${_uField('性别', _sexLabel(child.sex), '24mm')}
    <span>出生日期　${_uText(birth == null ? '' : '${birth.year}', '12mm')} 年 ${_uText(birth == null ? '' : '${birth.month}', '8mm')} 月 ${_uText(birth == null ? '' : '${birth.day}', '8mm')} 日</span>
  </div>
  <div class="row">身份证号<span class="boxes">${[
      for (var i = 0; i < 18; i++) '<span>${i < cert.length ? _esc(cert[i]) : ''}</span>',
    ].join()}</span></div>
  <div class="row">
    ${_uField('家长姓名', _esc(guardian?.name ?? ''), '26mm')}
    ${_uField('联系电话', _esc(phone), '34mm')}
  </div>
  <div class="row">
    转诊原因　<div style="margin-left:12mm">
      1 预警征象筛查结果<br>
      <span style="margin-left:6mm">${_optPlain('未见异常', warningNormal)}</span><br>
      <span style="margin-left:6mm">${_optPlain('异常，具体注明未通过项目', !warningNormal)}${warningNormal ? '' : _uText(_esc(warning), '52mm')}</span><br>
      <span style="margin-left:6mm">2 语言功能及社会交往功能询问</span><br>
      <span style="margin-left:6mm">${_optPlain('未见异常', language.contains('未见异常'))}　${_optPlain('语言功能障碍或倒退', language.contains('语言功能障碍或倒退'))}　${_optPlain('社会交往能力障碍或倒退', language.contains('社会交往能力障碍或倒退'))}</span>
    </div>
  </div>
  <div class="row bold">儿童存在以上情况，建议转诊到<span class="u" style="min-width:44mm">${_esc(record?.referralHospName ?? '')}</span>医疗机构进一步接受复筛。</div>
  <div class="row">
    ${_uField('医疗机构', _esc(record?.hospName ?? ''), '34mm')}
    医生签字　<span class="u" style="min-width:26mm">${_esc(record?.doctorName ?? '')}</span>${_signatureImg(record, bundle)}
    <span>填写日期　${_dateLine(record?.checkDate)}</span>
  </div>
</div>''';
  }

  /// 签名图（内联 base64 图片）。
  static String _signatureImg(InitialScreening? record, PrintBundle bundle) {
    if (record == null) return '';
    final base64 = bundle.doctorSignatures[record.doctorId];
    if (base64 == null || base64.isEmpty) return '';
    return '<img src="data:image/jpeg;base64,$base64" style="height:10mm;vertical-align:middle;margin-left:2mm">';
  }

  /// 性别码值转汉字（1-男，2-女）。
  static String _sexLabel(String sex) => switch (sex.trim()) {
    '1' => '男',
    '2' => '女',
    _ => '',
  };
}
