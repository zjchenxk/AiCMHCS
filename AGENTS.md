# AGENTS.md

面向 AI 编码代理的项目指南。项目详情见根目录 `README.md`，本文件聚焦「如何正确地在本仓库写代码」。

## 项目概述

AiCMHCS（智慧儿童心理保健系统）：为满足国家信创要求，技术栈已从 Serverpod + PostgreSQL 整体迁移为 **Dart Frog + 达梦 DM8**。现为 Dart Workspace 组织的两个子包，不再依赖 Serverpod、PostgreSQL、Redis 或 Docker。注释、文档、提交信息一律使用**中文**。

- DM8 没有官方/社区 Dart 驱动，后端通过 **DPI 原生接口（`dart:ffi` 直绑 `dmdpi.dll`）** 访问数据库；
- 运行后端需本机安装 DM8（默认 `C:\dmdbms`，实例端口 5236），并安装 dart_frog CLI：`dart pub global activate dart_frog_cli`。

## 仓库结构与生成物

```
aicmhcs_client/   Flutter 应用（MVVM，原 aicmhcs_flutter 更名并入）
aicmhcs_server/   Dart Frog 后端：routes / lib(dm, models, services) / tool / test
database/         DM8 SQL 脚本：01 表空间+账号(SYSDBA 执行) / 02 建表 / 03 演示数据
tools/            init_db.sh / start_backend.sh / serve_frontend.sh（Git Bash 运行）
```

**禁止手动编辑**（生成物，改动会被覆盖）：

- `database/03_demo_data.sql` — 由 `aicmhcs_server/tool/generate_demo_data.dart` 生成；
- `aicmhcs_server/build/**`、`aicmhcs_server/.dart_frog/**` — `dart_frog build/dev` 的产物；
- `aicmhcs_client/{android,ios,linux,macos,windows}/flutter/generated_*` 等平台生成文件。

**遗留路径不一致（注意）**：`README.md` 与 `tools/*.sh` 中残留旧骨架的 `backend/`、`frontend/`、`scripts/` 目录名，实际目录为 `aicmhcs_server/`、`aicmhcs_client/`、`tools/`。其中 `tools/start_backend.sh`、`tools/serve_frontend.sh` 因 `cd` 旧路径当前**无法直接运行**，请按实际目录手动执行其中的命令；修订这些脚本时记得同步目录名。

## 常用命令

```bash
# 依赖（必须在仓库根目录执行，Workspace 会解析两个子包）
flutter pub get

# 初始化数据库（Git Bash；建表空间/账号/表/演示数据，可重复执行）
# ⚠️ 内部会 DROP USER AICMHCS CASCADE，清空应用模式全部数据
./tools/init_db.sh

# 重新生成演示数据（改了生成脚本或演示账号后）
cd aicmhcs_server && dart run tool/generate_demo_data.dart > ../database/03_demo_data.sql

# 启动后端（http://localhost:8080；dart_frog dev 需要交互终端，支持热重载）
cd aicmhcs_server && dart_frog dev
# 无终端环境（后台/CI）用生产模式：
cd aicmhcs_server && dart_frog build && dart run build/bin/server.dart

# 启动前端（Web 调试）
cd aicmhcs_client && flutter run -d chrome      # 或 -d web-server --web-port 5173

# 检查（提交前执行；后端测试为纯单元测试，无需数据库）
cd aicmhcs_server && dart analyze && dart format --set-exit-if-changed . && dart test
cd aicmhcs_client && flutter analyze && dart format --set-exit-if-changed . && flutter test
```

端口约定：后端 API `8080`（环境变量 `AICMHCS_PORT` 可覆盖）、前端静态托管 `5173`、DM8 `5236`。

环境变量（后端 `lib/app_config.dart` 读取，默认值对准本机开发环境）：`AICMHCS_DB_HOST`（LOCALHOST）、`AICMHCS_DB_PORT`（5236）、`AICMHCS_DB_USER`（AICMHCS，最小权限应用账号，不用 SYSDBA）、`AICMHCS_DB_PASSWORD`（Aicmhcs@2026）、`DM_HOME`（定位 `dmdpi.dll`）。初始化脚本另有 `DM_HOST`/`DM_PORT`/`DM_SYSDBA_PWD`/`APP_DB_PWD`，见 `tools/init_db.sh` 头部注释。

演示账号：`admin/Admin@123`（系统管理员）、`doctor01/Doctor@123`（儿童心理医生）、`teacher01/Teacher@123`（教师）、`parent01/Parent@123`（家长）。

## 架构与代码约定

### 后端（aicmhcs_server，Dart Frog）

分层：`routes/`（HTTP 适配，文件路径即 URL）→ `services/`（业务逻辑）→ `lib/dm/`（DM8 数据库网关）；`lib/models/` 手写业务模型。**没有任何代码生成环节**（无 serverpod generate、无 migration，协议就是手写 JSON + 手写模型）。

- **入口注入**：`main.dart` 自定义 `run()` 在启动时创建 `DmGateway`、`AuthService`，经 `handler.use(provider<T>(...))` 注入管线；路由内 `context.read<T>()` 获取。新增单例服务照此在 `main.dart` 注册；
- **统一响应（明文 JSON，不再 AES 加密）**：`{'code': 0|非0, 'message': '...', 'data': ...}`，`code == 0` 表示成功。业务码与 HTTP 状态对应：40001/40002→400、40101/40102/40103→401、40301→403、40500→405、50000→500（全局兜底）。参照 `routes/api/auth/login.dart` 的 `_error` helper；
- **业务异常模式**：service 层抛带 `httpStatus/code/message` 的异常（现有 `AuthException`，新模块可仿建），路由 `catch` 后转错误响应；用户不存在与口令错误统一提示，避免账号枚举；
- **全局中间件** `routes/_middleware.dart`：CORS（`*`，供 Flutter Web 跨域）+ 未捕获异常兜底 500；
- **鉴权**：`Authorization: Bearer <token>`。令牌为内存会话（64 位十六进制，2 小时滑动续期，重启失效——生产环境应落库或接缓存）。

### DM8 访问约定（信创核心约束，务必遵守）

- 业务代码**不要直接使用 `Dpi` / `DmConnection`**（FFI 调用同步阻塞，会卡住 HTTP 事件循环），统一经 `DmGateway` 访问；
- `DmGateway`（`lib/dm/dm_gateway.dart`）把连接放进独立 isolate 串行执行：`query`/`ping` 失败自动重连并重试一次，`execute`/`executeDirect` **不重试**（防重复写入），默认 30 秒超时。`Dpi.open()` 已处理 DLL 依赖链多轮加载（`dmdpi → dmcomm → libcrypto`），勿重复造轮子；
- **字符集**：全程走 DPI 的 W 系列（UTF-16）接口，数据库实例为 GB18030 时由 DPI 自动转码，Dart 侧始终处理 Unicode，中文无乱码。但 `dpi_bind_param` 无宽字符版本——**绑定参数只支持 ASCII**；含中文的值必须单引号翻倍转义后经 SQL 内联（参照 `AuthService._lit()` 与 `_logLogin()`）；
- SQL 占位符为 `?`；`DmResult` 所有列以字符串返回（NULL 为 null），数值/时间由模型层按需转换（参照 `UserInfo.fromRow`）。

### 口令与数据库对象

- 口令散列：`sha256(salt + password)` 十六进制，存储格式 `salt:hash`（salt 为 16 字节随机数的十六进制）。后端 `AuthService` 与 `tool/generate_demo_data.dart` 的算法**必须保持一致**，改一侧同步另一侧；
- 数据库模式为 `AICMHCS`。现有表：`SYS_USER`（系统用户）、`SYS_LOGIN_LOG`（登录审计），系统表前缀 `SYS_`；
- **DDL 约定**（`database/*.sql`）：表/列名全大写；中文注释用 `COMMENT ON TABLE/COLUMN`；主键 `BIGINT IDENTITY(1,1)`，约束命名 `PK_<表>` / `UK_<表>_<字段>`；时间列 `TIMESTAMP(0)`。脚本是**达梦方言，不要写 PostgreSQL 语法**；建表脚本以 `DROP TABLE IF EXISTS` 开头（重建式，可重复执行但有破坏性）；`init_db.sh` 目前只执行 01–03，新增编号脚本需同步加入该脚本。

### 前端（aicmhcs_client）— MVVM

- **导入约定**：统一 `import 'package:material_ui/material_ui.dart';`（全仓库 0 处 `flutter/material.dart`），新页面遵循；
- **全局对象**在 `lib/main.dart`：`token`（登录令牌）、`getIt`（服务定位器）——Serverpod 的 `client` 已随迁移移除；
- **Service 模式**（参照 `admin_divisions_service.dart` 的骨架）：检查 `token == null` → 调后端 → 逐项校验 `code/message/data` 键 → `X.fromJson` 还原模型。新 Service 要在 `main.dart` 的 `setupServiceLocator()` 中注册。注意：现有 Service 内的后端调用全部被注释（拿到空串后抛「响应消息为空」），是待接 Dart Frog API 的骨架，接线时补 HTTP 调用即可；
- **ViewModel 模式**（参照 `hospital_management_view_model.dart`）：私有字段 + getter、`_loading`/`_errorMsg` 状态、状态变更后 `notifyListeners()`、异步方法返回 `Future<bool>` 表示成败。新 ViewModel 必须注册到 `main.dart` 的 `MultiProvider`；
- **新页面接入路由**：菜单项在 `main_view_model.dart` 的 `menus` 列表中定义（带 `route`），页面构造器注册到 `lib/routes/menu_routes.dart`（key 与 `MenuItem.route` 一致）；
- 后端地址配置在 `assets/config.json` 的 `apiUrl`（当前尚无代码读取它）；客户端 pubspec 暂未引入 `http` 包，接通后端时需添加依赖并读取该配置。

### 安全层现状

- 新后端响应为**明文 JSON**（无 AES 加密、无 MD5 签名）；
- 客户端 `utils/security_util.dart` 为旧架构遗留（AES-128-CBC + MD5，密钥/IV 硬编码），当前无任何调用方——保留但**不要在新代码中扩展使用**；若要恢复报文加密，需前后端同步设计。

## UI 风格设定（aicmhcs_client）

整体视觉：**毛玻璃 + 扁平化**，基于 Material 3，所有颜色跟随当前主题（`Theme.of(context).colorScheme`），**禁止硬编码颜色**（`Colors.white`、`Color(0xFF...)` 等）。

### 主题（flex_color_scheme）

- 主题定义在 `utils/theme_data_util.dart` 的 `AppThemes.themes`，共 7 套浅色主题：Blue / AquaBlue / Green / Gold / **Teal（默认）** / Purple / Red；
- 每套主题使用**完全相同**的 `FlexSubThemesData` 配置（`interactionEffects`、`tintedDisabledControls`、`inputDecoratorIsFilled` + outline 边框、`alignedDropdown`、`comfortablePlatformDensity` 等）——新增主题必须复制同一份 subThemesData，只换 `FlexScheme`；
- 主题切换与持久化由 `providers/theme_provider.dart`（`ThemeProvider`，SharedPreferences key `current_theme`）负责；字体 5 档缩放由 `FontProvider` 负责，`main.dart` 中统一应用到 textTheme 与各类按钮。

### 默认字体设定

字号体系由 `FontProvider` 在 `main.dart` 中统一缩放（bodyLarge 16 / bodyMedium 14 / bodySmall 12 / titleLarge 22 / titleMedium 18 / titleSmall 14…），业务代码**不要手动乘 fontScale、不要凭空 `TextStyle(fontSize: ...)` 新造样式**，一律取 `Theme.of(context).textTheme.<样式>` 并用 `copyWith` 微调字重/颜色。场景对应关系：

| 场景 | 样式 |
| ---- | ---- |
| 正文 / 普通文字（默认选项） | `theme.textTheme.bodyMedium` |
| 卡片类标题、表单分组标题 | `theme.textTheme.bodyLarge`（常加 `fontWeight: FontWeight.bold`） |
| 对话框标题、面板标题 | `theme.textTheme.titleMedium`（常加 `fontWeight: FontWeight.bold`） |
| 注释性 / 辅助描述文字 | `theme.textTheme.bodySmall`（常配 `onSurface` 60% 透明度弱化显示） |
| 顶栏品牌名 / 页面主标题 | `theme.textTheme.titleLarge`（品牌名加 `letterSpacing: 1.5`） |
| 顶栏副标题 | `theme.textTheme.titleSmall` |
| 登录页等展示型大标题 / 副标题 | `theme.textTheme.displayLarge` / `displaySmall` |
| 按钮文字 | Material 默认（labelLarge），字号已随 FontProvider 缩放，勿单独覆盖 |

### 毛玻璃（GlassPanel）

- 通用组件 `widgets/glass_panel.dart`：`BackdropFilter` 模糊（默认 `blur: 20`）+ `colorScheme.surface` 90% 透明底 + `outlineVariant` 30% 透明细描边（`borderWidth: 0.5`）+ 默认圆角 16，全部参数可覆盖；
- **使用场景约定**：工作区面板、侧栏内容、表单容器统一包 `GlassPanel`；弹出对话框统一毛玻璃背景（参照 `change_password_dialog.dart`），且 `Dialog` 自身 `backgroundColor: Colors.transparent` 去掉默认白底；
- 个别页面（登录卡片）直接用 `ClipRRect + BackdropFilter` 手写毛玻璃（blur 15、圆角 24）。

### 扁平化细节

- 输入框：填充式 + outline 边框（`inputDecoratorIsFilled: true`、`inputDecoratorBorderType: outline`），不使用重阴影、浮雕效果；
- 表面装饰靠色彩与透明度区分层级（surface/primaryContainer/outlineVariant），不用 `BoxShadow` 堆叠；
- 下拉菜单 `alignedDropdown: true`，与输入框对齐；
- 功能菜单图标统一使用 **outlined 系列** Material 图标（如 `Icons.home_outlined`、`Icons.local_hospital_outlined`）。

### 背景与插画

- 主框架页面背景：`theme.colorScheme.primaryContainer` 纯色；
- 登录页背景：`primaryContainer → primaryFixed` 对角线性渐变（`Alignment.topLeft → bottomRight`），左侧 `welcome.svg` 用 `ThemeColorMapper(primary: theme.colorScheme.primary)` 按主题着色；
- 图片资源放 `assets/images/`（SVG 用 `flutter_svg` 渲染），新增资源需同步注册 `pubspec.yaml`。

### 页面骨架与响应式

- 功能页继承 `views/base/base_page.dart` 的 `BasePage`（必须接收 `loginUser` + `child` 两个参数），由 `menu_routes.dart` 统一构造；
- 响应式断点（`responsive_framework`，在 `main.dart` 配置）：MOBILE `0–450`、TABLET `451–800`、DESKTOP `801+`，新页面应在这三档下可用。

## 新增一个全栈功能的标准流程

1. 在 `database/` 新增/修改建表脚本（沿用编号与 DDL 约定），必要时同步 `tools/init_db.sh`；执行 `./tools/init_db.sh` 应用；
2. 在 `aicmhcs_server/lib/models/` 写模型（`fromRow`/`toJson`）；
3. 在 `aicmhcs_server/lib/services/` 写业务服务（构造注入 `DmGateway`）；需在路由中直接读取的，在 `main.dart` 用 `provider<T>` 注入；
4. 在 `aicmhcs_server/routes/api/<模块>/` 写路由（统一响应格式 + `_error` helper + 业务异常转换）；
5. `cd aicmhcs_server && dart analyze && dart test`；
6. 在 `aicmhcs_client/lib/services/` 写 HTTP 服务（校验 `code/message/data` 后 `fromJson`），注册到 `setupServiceLocator()`；
7. 写 ViewModel 并注册到 `MultiProvider`；写页面（遵循「UI 风格设定」章节），注册菜单与路由；
8. `cd aicmhcs_client && flutter analyze && flutter test`。

## 代码风格

- 客户端 `analysis_options.yaml` 设置 `formatter: trailing_commas: preserve`——格式化时保留既有尾随逗号写法，勿手动增删；服务端使用 `dart_frog_lint/recommended.yaml`（启用了 `public_member_api_docs`、`avoid_print`、`prefer_single_quotes` 等较严规则）；
- 服务端存量 lint 未清零（约百条 info，主要是 `public_member_api_docs` 与 `tool/` 脚本的 `print`），新代码至少做到不新增；无 CI 门禁，提交前本地自查；
- 文档注释格式统一：`///中文描述`、`///param x: 说明`、`///returns: 说明`；
- 字符串用单引号；变量声明常用 `var`（局部）。

## 测试

- 后端测试位于 `aicmhcs_server/test/`，为纯单元测试（口令散列、令牌逻辑），**不需要**数据库或 Docker，直接 `dart test`；
- 前端测试位于 `aicmhcs_client/test/`，用 `flutter test`；
- 原 GitHub Actions CI 已随信创迁移移除（仓库无 `.github/` 目录）。

## 当前已知 Mock / 待接线（勿误判为已接通）

- **后端已实现真实接口**：`POST /api/auth/login`、`GET /api/auth/me`、`GET /health`（数据库探活）——登录链路后端侧已通；
- **客户端登录仍是演示逻辑**：`LoginViewModel.login()` 中 token 硬编码 `'aicmhcs'`，未调用真实后端；
- 客户端 `AdminDivisionsService` / `LogService` 的后端调用全部被注释，行政区划联动当前**未接通**；医院管理加载与保存为 mock（`HospitalManagementViewModel` 中标注 `TODO`）。

改动这些区域时保留 TODO 标注与被注释的调用代码，不要顺手删除。

## 其他注意事项

- **密钥与口令**：`tools/init_db.sh` 内置开发机 SYSDBA 口令默认值；应用账号口令 `Aicmhcs@2026` 同时硬编码在 `init_db.sh`、`database/01_init_schema.sql` 与后端 `app_config.dart` 默认值中——不要在示例或文档中扩散这些值，生产环境必须覆盖；修改应用账号口令需多处（脚本 + SQL + 环境变量）同步；
- `./tools/init_db.sh` 会 `DROP USER AICMHCS CASCADE` 重建应用模式，执行前确认数据可丢弃；
- 必须以仓库根目录（而非子文件夹）打开 VS Code，`.vscode/launch.json` 的 F5 全栈启动（server `dart_frog dev` + client Chrome）才生效；
- 提交信息：中文短句描述变更（如「接入达梦数据库登录接口」），无 conventional-commit 前缀；
- `dmdpi.dll` 加载失败先确认 DM8 已安装且 `DM_HOME` 指向正确目录；若自行扩展 SQL 拼接，注意绑定参数只支持 ASCII（见「DM8 访问约定」）。
