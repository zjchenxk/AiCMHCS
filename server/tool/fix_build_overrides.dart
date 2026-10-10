// 修复 dart_frog build 生成的 build/pubspec_overrides.yaml。
//
// 背景：仓库为 pub workspace（client/server/common），dart_frog_cli 1.2.14 生成
// 生产构建时会把 workspace 共享包写成「相对前缀 + 绝对路径」的坏 path，
// 如 `..\..\..\..\D:\MyProjects\...\common`，导致 build 目录 `dart pub get`
// 直接失败（errno 123），干净环境下 `dart run build/bin/server.dart` 起不来。
// 本脚本把这类 path 统一改写为指向仓库根下共享包的正确相对路径 `..\..<包名>`，
// 并在 build 目录重新解析依赖，使 pubspec.lock 包含共享包。
// 在 dart_frog build 之后运行（见 tools/start_backend.sh 与 .vscode/tasks.json）。
//
// 说明：构建日志中的两条 `Exists failed, path = 'D:\D:\...'` 是 dart_frog CLI
// 自身处理 workspace 包的固有缺陷警告（1.2.14 最新版仍未修复），无法从外部
// 消除；经本脚本修复后它们不影响构建产物与运行，可忽略。
import 'dart:io';

Future<void> main() async {
  // dart_frog 还会在 server/ 根目录生成同名坏文件（resolution: null 会把
  // server 踢出 workspace 解析，直接删除；workspace 内依赖无需 overrides）。
  final stray = File('pubspec_overrides.yaml');
  if (stray.existsSync() &&
      stray.readAsStringSync().contains(RegExp(r'[A-Za-z]:[\\/]'))) {
    stray.deleteSync();
    stdout.writeln('已删除 dart_frog 误生成的 pubspec_overrides.yaml');
  }

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
  final fixed = original.replaceAllMapped(
    broken,
    (m) => '{path: ..\\..\\${m[1]}}',
  );
  file.writeAsStringSync(fixed);
  stdout.writeln('已修复 build/pubspec_overrides.yaml 中的共享包 path');
  stdout.writeln('（构建日志中的 Exists failed 警告为 dart_frog CLI 已知缺陷，不影响产物，可忽略）');

  // 修复后重新解析依赖，使 pubspec.lock / package_config 包含共享包，
  // 产物即刻自洽（否则需依赖 dart run 启动时自动补做 pub get）。
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get'],
    workingDirectory: 'build',
  );
  if (result.exitCode == 0) {
    stdout.writeln('build 依赖已更新，共享包已纳入解析');
  } else {
    stdout.writeln('警告：build 目录 pub get 失败（exit ${result.exitCode}）：');
    stdout.writeln(result.stderr);
  }
}
