// 修复 dart_frog build 生成的 build/pubspec_overrides.yaml。
//
// 背景：仓库为 pub workspace（client/server/common），dart_frog_cli 1.2.14 生成
// 生产构建时会把 workspace 共享包写成「相对前缀 + 绝对路径」的坏 path，
// 如 `..\..\..\..\D:\MyProjects\...\common`，导致 build 目录 `dart pub get`
// 直接失败（errno 123），干净环境下 `dart run build/bin/server.dart` 起不来。
// 本脚本把这类 path 统一改写为指向仓库根下共享包的正确相对路径 `..\..<包名>`。
// 在 dart_frog build 之后运行（见 tools/start_backend.sh 与 .vscode/tasks.json）。
import 'dart:io';

void main() {
  final file = File('build/pubspec_overrides.yaml');
  if (!file.existsSync()) {
    stdout.writeln('跳过：build/pubspec_overrides.yaml 不存在');
    return;
  }
  final original = file.readAsStringSync();
  // 匹配 {path: 任意含盘符绝对路径、以包名结尾}，例如
  // {path: ..\..\..\..\D:\MyProjects\Flutter\AiCMHCS\common}
  final broken = RegExp(r'\{path: [^}]*[A-Za-z]:[\\/][^}]*[/\\]([\w.-]+)\s*\}');
  if (!broken.hasMatch(original)) {
    stdout.writeln('跳过：未发现需要修复的绝对路径');
    return;
  }
  final fixed = original.replaceAllMapped(broken, (m) => '{path: ..\\..\\${m[1]}}');
  file.writeAsStringSync(fixed);
  stdout.writeln('已修复 build/pubspec_overrides.yaml 中的共享包 path');
}
