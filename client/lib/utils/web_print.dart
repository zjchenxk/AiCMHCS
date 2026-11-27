/// 把打印页 HTML 送入浏览器打印的条件导入门面：Web 平台经隐藏 iframe
/// 装载打印 HTML（真文本矢量渲染，打印/PDF 导出的文字可复制），文档
/// onload 后由内嵌脚本自动 window.print()；非 Web 平台为不可用桩。
library;

export 'web_print_none.dart' if (dart.library.html) 'web_print_html.dart';
