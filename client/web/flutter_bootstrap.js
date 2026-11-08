// 自定义 Flutter Web 启动脚本：flutter tool 构建时优先使用本文件并替换
// 下方 {{...}} 模板变量（dev 与 build 产物均生效，见 Flutter 官方文档
// platform-integration/web/initialization）。
//
// 经 loader config 把 CanvasKit 渲染引擎指向项目 web/canvaskit/ 本地
// 目录（随 dev server / 构建产物一起提供）：默认从 www.gstatic.com 在线
// 下载 canvaskit，内网/无外网环境会因下载失败而黑屏——错误只出现在
// 浏览器 Console，VS Code 调试控制台不可见。
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: '/canvaskit/',
  },
});
