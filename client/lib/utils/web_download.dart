/// 字节流另存为本地文件的条件导入门面：Web 平台经临时 `<a download>`
/// 触发浏览器下载（地址栏出现/弹出另存对话框由浏览器按用户设置决定，
/// 数据 URL 下载即「另存为」体验）；非 Web 平台为不可用桩。
///
/// 用法：`await saveBytes(bytes, '文件名.jpg');`
library;

export 'web_download_none.dart' if (dart.library.html) 'web_download_html.dart';
