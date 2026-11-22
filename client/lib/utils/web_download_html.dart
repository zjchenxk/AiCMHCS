import 'dart:convert';
import 'dart:typed_data';
// 本文件为 Web 平台实现（经条件导入仅在选择 dart:html 的平台编译）：
// dart:html 已被官方标记废弃（推荐 package:web），此处沿用以零依赖落地
// 文件下载（临时 <a download> 触发浏览器另存），升级路径可替换为
// package:web（与 web_camera_html.dart 同款取舍）。
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// 把字节流以指定文件名触发浏览器下载：数据 URL + 临时 `<a download>`
/// 元素 click（Chrome 对数据 URL 下载呈现「另存为」对话框，由浏览器
/// 下载设置决定）。
Future<void> saveBytes(Uint8List bytes, String filename, {String mime = 'image/jpeg'}) async {
  final anchor = html.AnchorElement(href: 'data:$mime;base64,${base64Encode(bytes)}')..download = filename;
  // 挂载后再点击并立即移除：部分浏览器要求元素在文档内才响应 click
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
