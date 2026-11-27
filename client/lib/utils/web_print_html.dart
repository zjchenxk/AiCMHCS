import 'dart:async';
// 本文件为 Web 平台实现（经条件导入仅在选择 dart:html 的平台编译）：
// dart:html 已被官方标记废弃（推荐 package:web），此处沿用以零依赖落地
// 浏览器打印（隐藏 iframe 装载打印 HTML，文档 onload 后由内嵌脚本自动
// window.print()），升级路径可替换为 package:web（与 web_download_html.
// dart 同款取舍）。
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// 把打印页 HTML（真文本矢量渲染）送入浏览器打印。
///
/// 实现要点：
/// - **先注册 load 监听、再设置 srcdoc 并挂载**——srcdoc 文档极小，若先
///   挂载后监听，load 事件可能在监听前已触发完导致永久挂起；
/// - 打印由 **srcdoc 内嵌脚本在 iframe 自身上下文**调用 window.print()
///   （跨帧 Dart 侧 contentWindow 是 _DOMWindowCrossFrame，无法转换为
///   html.Window 调 print，会抛 TypeError）；
/// - iframe 挂载后不移除——打印对话框为模态，中途移除会取消打印；
/// - 8 秒兜底超时解除 Dart 侧挂起，个别环境不触发 load 时不再卡界面。
Future<void> printHtml(String htmlDocument) async {
  final completer = Completer<void>();
  final iframe = html.IFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';

  // 1. 先挂 load 监听（必须在设置 srcdoc 之前）
  iframe.onLoad.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  // 2. 再设置内容并挂载：文档 onload 后延时触发打印（focus 保证打印
  //    目标为 iframe 文档而非主页面）
  iframe.srcdoc =
      '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<script>
window.onload = function () {
  setTimeout(function () { window.focus(); window.print(); }, 300);
};
</script>
</head>
<body>
$htmlDocument
</body>
</html>''';
  html.document.body?.append(iframe);

  // 3. 兜底超时：load 未触发（个别浏览器/扩展拦截）时解除挂起
  Timer(const Duration(seconds: 8), () {
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
}
