// 自定义 Flutter Web 启动脚本：flutter tool 构建时优先使用本文件并替换
// 下方 {{...}} 模板变量（dev 与 build 产物均生效，见 Flutter 官方文档
// platform-integration/web/initialization）。
//
// 经 loader config 把两项运行期资源指向项目 web/ 下的本地目录（随
// dev server / 构建产物一起提供），消除内网/无外网环境的在线依赖：
// 1. canvasKitBaseUrl：CanvasKit 渲染引擎（默认从 www.gstatic.com 在线
//    下载，失败会黑屏——错误只在浏览器 Console，VS Code 调试控制台不可见）；
// 2. fontFallbackBaseUrl：内置字体（阿里巴巴普惠体）缺字形时的 Noto
//    回退字体拆片（默认从 fonts.gstatic.com 按需下载，下载完成前显示
//    缺字形框、离线永久卡框）。拆片经 tools/download_noto_fonts.sh
//    镜像到 web/noto/，更新 Flutter SDK 后重跑该脚本即可补齐。
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: '/canvaskit/',
    fontFallbackBaseUrl: '/noto/',
  },
});
