/// 非 Web 平台桩实现：浏览器打印不可用（系统当前仅交付 Chrome Web 端）。
///throws: UnsupportedError（非 Web 平台）
Future<void> printHtml(String htmlDocument) async {
  throw UnsupportedError('浏览器打印仅支持 Web 平台');
}
