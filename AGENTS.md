# AGENTS.md

面向 AI 编码代理的项目指南。项目详情见根目录 `README.md`，本文件聚焦「如何正确地在本仓库写代码」。

## 项目概述

AiCMHCS（智慧儿童心理保健系统）：为满足国家信创要求，技术栈已从 Serverpod + PostgreSQL 整体迁移为 **Dart Frog + 达梦 DM8**。现为 Dart Workspace 组织的三个子包（client / server / common），不再依赖 Serverpod、PostgreSQL、Redis 或 Docker。注释、文档、提交信息一律使用**中文**。

- DM8 没有官方/社区 Dart 驱动，后端通过 **DPI 原生接口（`dart:ffi` 直绑 `dmdpi.dll`）** 访问数据库；
- 数据访问层已抽象为 `DatabaseGateway` 双实现：**网络版达梦 DM8（DPI）/ 单机版 SQLite**（`package:sqlite3`），由环境变量 `AICMHCS_DB_DRIVER`（dm 默认 / sqlite）切换；
- 运行后端需本机安装 DM8（默认 `C:\dmdbms`，实例端口 5236），并安装 dart_frog CLI：`dart pub global activate dart_frog_cli`。

## 仓库结构与生成物

```
client/   Flutter 应用（MVVM，原 aicmhcs_flutter 更名并入）
server/   Dart Frog 后端：routes / lib(db, dm, services) / tool / test
common/   前后端共享包：lib/models（basic 行政区划 / system 医院、登录用户）+ lib/utils（SecurePayload 报文加解密）
database/         DM8 SQL 脚本：01 表空间+账号（SYSDBA 执行）；建表与结构变更在代码中（server/lib/db/migrations.dart，双方言迁移）
tools/            init_db.sh / start_backend.sh / serve_frontend.sh（Git Bash 运行）
```

**禁止手动编辑**（生成物，改动会被覆盖）：

- `server/build/**`、`server/.dart_frog/**` — `dart_frog build/dev` 的产物；
- `client/{android,ios,linux,macos,windows}/flutter/generated_*` 等平台生成文件。

## 常用命令

```bash
# 依赖（必须在仓库根目录执行，Workspace 会解析三个子包）
flutter pub get

# 初始化达梦数据库（Git Bash；建表空间/账号 → 结构迁移 → 演示账号，可重复执行）
# ⚠️ 内部会 DROP USER AICMHCS CASCADE，清空应用模式全部数据；SKIP_SEED=1 跳过迁移与演示数据
./tools/init_db.sh

# 重灌演示账号（改了演示账号后；结构变更走迁移，见「口令与数据库对象」）
cd server && dart run tool/seed_demo_data.dart                                  # 达梦（默认）
cd server && AICMHCS_DB_DRIVER=sqlite dart run tool/seed_demo_data.dart         # 单机版

# 启动后端（http://localhost:8080；dart_frog dev 需要交互终端，支持热重载）
cd server && dart_frog dev
# 无终端环境（后台/CI）用生产模式（build 后必须跑修复脚本，
# 否则 dart_frog 生成的 workspace 共享包 path 有误、服务起不来）：
cd server && dart_frog build && dart run tool/fix_build_overrides.dart && dart run build/bin/server.dart
# 一键脚本（旧进程清理 + 构建 + 修复 + 启动）：
./tools/start_backend.sh

# 启动前端（Web 调试）
cd client && flutter run -d chrome      # 或 -d web-server --web-port 5173

# 检查（提交前执行；后端测试为纯单元测试，无需数据库）
cd server && dart analyze && dart format --set-exit-if-changed . && dart test
cd client && flutter analyze && dart format --set-exit-if-changed . && flutter test
```

端口约定：后端 API `8080`（环境变量 `AICMHCS_PORT` 可覆盖）、前端静态托管 `5173`、DM8 `5236`。

环境变量（后端 `lib/app_config.dart` 读取，默认值对准本机开发环境）：`AICMHCS_DB_DRIVER`（dm 默认 / sqlite 单机版）、`AICMHCS_DB_HOST`（LOCALHOST）、`AICMHCS_DB_PORT`（5236）、`AICMHCS_DB_USER`（AICMHCS，最小权限应用账号，不用 SYSDBA）、`AICMHCS_DB_PASSWORD`（Aicmhcs@2026）、`AICMHCS_DB_FILE`（SQLite 数据文件，默认 data/aicmhcs.db）、`AICMHCS_SQLITE3_DLL`（sqlite3.dll 路径，默认 exe 同目录 → 系统 winsqlite3.dll）、`AICMHCS_FIELD_MASTER_KEY`（字段加密主密钥，base64 的 32 字节；未设时走密钥文件，生产/等保环境必须以本变量注入实现密钥与数据分离）、`AICMHCS_FIELD_KEY_FILE`（字段加密密钥文件，默认 data/aicmhcs.field.key，首启自动生成——单机版交付依赖此机制，密钥文件须单独备份，丢失即无法解密存量数据）、`DM_HOME`（定位 `dmdpi.dll`）。初始化脚本另有 `DM_HOST`/`DM_PORT`/`DM_SYSDBA_PWD`/`APP_DB_PWD`，见 `tools/init_db.sh` 头部注释。

演示账号：`admin/Admin@123`（系统管理员）、`doctor01/Doctor@123`（儿童心理医生）、`teacher01/Teacher@123`（教师）、`parent01/Parent@123`（家长）。

## 架构与代码约定

### 后端（server，Dart Frog）

分层：`routes/`（HTTP 适配，文件路径即 URL）→ `services/`（业务逻辑）→ `lib/db/`（数据库网关抽象、SQLite 实现、结构迁移注册表与执行器）；达梦 FFI 绑定在 `lib/dm/`（DPI / DmGateway）；共享业务模型在 `common/lib/models/`（统一经 `package:common/model.dart` barrel 导入），DB 行解析（`fromRow` 类函数）留在服务层。**没有 ORM/代码生成环节**（协议就是手写 JSON + 手写模型；数据库结构走**手写版本化迁移**，见「口令与数据库对象」）。

- **入口注入**：`main.dart` 自定义 `run()` 在启动时按 `AICMHCS_DB_DRIVER` 经 `openDatabaseGateway()`（`lib/db/db_factory.dart`）打开网关（dm → `DmGateway` / sqlite → `SqliteGateway`）、经 `FieldCipher.fromConfig()` 解析字段加密密钥、带密钥跑 `SchemaMigrator.migrate()` 对齐结构、创建 `AuthService`，经 `handler.use(provider<T>(...))` 注入管线（现有 `DatabaseGateway` / `FieldCipher` / `AuthService`）；路由内 `context.read<T>()` 获取。新增单例服务照此在 `main.dart` 注册；
- **统一响应**：`{'code': 0|非0, 'message': '...', 'data': ...}`，`code == 0` 表示成功。业务码与 HTTP 状态对应：40001/40002→400、40101/40102/40103→401、40301→403、40500→405、50000→500（全局兜底）。参照 `routes/api/auth/login.dart` 的 `_error` helper。响应报文会被 `/api` 加密中间件整体封入信封（见「安全层现状」）；
- **业务异常模式**：service 层抛带 `httpStatus/code/message` 的异常（现有 `AuthException`，新模块可仿建），路由 `catch` 后转错误响应；用户不存在与口令错误统一提示，避免账号枚举；
- **中间件**：全局 `routes/_middleware.dart`（CORS `*` 供 Flutter Web 跨域 + 未捕获异常兜底 500）；`routes/api/_middleware.dart` 负责 `/api/**` 的报文加解密与会话校验（详见「安全层现状」）；
- **鉴权**：`Authorization: Bearer <token>`。令牌为内存会话（64 位十六进制，2 小时滑动续期，重启失效——生产环境应落库或接缓存）；登录同时下发会话密钥 `sessionKey`（`LoginSession` 持有，与 token 同生命周期），非白名单 `/api` 请求由加密中间件统一 `verifySession` 校验。

### 数据库访问约定（信创核心约束，务必遵守）

- 业务代码统一经 `DatabaseGateway`（`lib/db/database_gateway.dart`）访问数据库，**不要直接使用 `Dpi` / `DmConnection` / sqlite3**（FFI 调用同步阻塞，会卡住 HTTP 事件循环）；两个实现（`DmGateway` / `SqliteGateway`）共用 `lib/db/worker_gateway.dart` 的 isolate 工作区基类：连接在独立 isolate 串行执行，默认 30 秒超时；达梦侧 `query`/`ping` 失败自动重连并重试一次，`execute`/`executeDirect` **不重试**（防重复写入）。`Dpi.open()` 已处理 DLL 依赖链多轮加载（`dmdpi → dmcomm → libcrypto`），勿重复造轮子；
- **字符集**：达梦全程走 DPI 的 W 系列（UTF-16）接口，GB18030 实例由 DPI 自动转码，Dart 侧始终处理 Unicode。`dpi_bind_param` 无宽字符版本——**绑定参数只支持 ASCII**；该限制已下沉到 `DmGateway`（`lib/dm/dm_param_rewrite.dart` 自动把非 ASCII 参数转义内联、ASCII 照常绑定），**业务层直接写参数化 SQL，中文参数照常传，不要手拼 SQL 字面量**；
- SQL 占位符 `?` 两库通用；`DbResult` 所有列以字符串返回（NULL 为 null），数值/时间由模型层按需转换（参照 `AuthService._loginUserFromRow`）；
- **敏感字段加密存储（等保）**：`SYS_USER.PHONE` 等敏感个人信息列存 `FieldCipher`（`lib/security/field_cipher.dart`）的 AES-256-GCM 密文（`v1:` 版本前缀 + base64，同明文每次密文不同），配套冗余哈希列 `PHONE_HMAC`（HMAC-SHA256 盲索引，应用侧密钥防穷举）供精确查询——查询一律在应用侧 `cipher.mac(purpose, 明文)` 后 `WHERE PHONE_HMAC = ?` 绑定，**不支持 LIKE 模糊查询/排序**；写入经 `seal`、读出经 `open`（不带版本前缀的存量明文原样返回兜底）；purpose 按字段区分（现有 `FieldCipher.phonePurpose`），新敏感字段选新 purpose 即可派生独立子钥；密文与 HMAC 均为 ASCII，天然满足达梦绑定参数限制；**日志与异常信息中不得输出解密后的明文**；
- **时间列**：统一在 Dart 侧用 `formatTimestamp(DateTime.now())` 生成后作为参数绑定写入（达梦隐式转 TIMESTAMP(0)；SQLite 的 `CURRENT_TIMESTAMP` 是 UTC，且 Windows 系统 winsqlite3.dll 的 `'localtime'` 修饰符返回 NULL，SQL 端时间函数不可依赖）；
- SQLite 网关（`lib/db/sqlite_gateway.dart`）：Windows 原生库解析顺序 `AICMHCS_SQLITE3_DLL` → exe 同目录 `sqlite3.dll` → 系统 `winsqlite3.dll`（单机版打包时随包分发官方 sqlite3.dll 即可）；`:memory:` 供测试，按路径缓存防 dart_frog 热重载泄漏 isolate。依赖锁定 `sqlite3` **2.4.0 双保险**：`server/pubspec.yaml` 精确锁定（勿加 `^`）+ 根 `pubspec.yaml` 的 `dependency_overrides`——后者优先级高于一切约束，实测连 `pub upgrade --major-versions` 都会被挡下（pub 会警告 `dependency_overrides prevents upgrades for: sqlite3`，属预期，无需处理）。原因：3.x 删除了 `open.dart` 的动态库覆盖机制、改为构建期 hook 下载预编译库，与 dart_frog 打包/离线信创环境/随包分发 dll 冲突。将来若要升 3.x，必须先删根 pubspec 的 override。

### 口令与数据库对象

- 口令散列：`sha256(salt + password)` 十六进制，存储格式 `salt:hash`（salt 为 16 字节随机数的十六进制）。演示数据 `tool/seed_demo_data.dart` 直接复用 `AuthService.makeStoredPassword`，算法天然一致，不存在两处维护；
- 数据库：达梦为 `AICMHCS` 模式，SQLite 为单个数据文件（默认 `data/aicmhcs.db`）。现有表：`SYS_USER`（系统用户，PHONE 存密文、PHONE_HMAC 为盲索引列，见「数据库访问约定」）、`SYS_LOGIN_LOG`（登录审计）、`SYS_SCHEMA_VERSION`（迁移版本历史），系统表前缀 `SYS_`；
- **结构变更走代码迁移**（`server/lib/db/migrations.dart` 注册表 + `SchemaMigrator`，启动/seed 时自动补齐到最新版本）：已发布的迁移**不可修改，只能向后追加**（版本号严格递增，启动时校验）；迁移里**不要写 `DROP TABLE IF EXISTS`**（对升级用户是数据丢失）；演示数据不进迁移（生产不得自动长出演示账号）。DDL 约定：表/列名全大写、主键达梦 `BIGINT IDENTITY(1,1)` / SQLite `INTEGER PRIMARY KEY AUTOINCREMENT`、约束命名 `PK_<表>` / `UK_<表>_<字段>`、时间列达梦 `TIMESTAMP(0)` / SQLite `TEXT`；中文注释达梦用 `COMMENT ON`、SQLite 用语句内 `--`。改结构 = 在 `migrations.dart` 追加一个 `DbMigration`（两库通用的语句放 `common`，方言差异放 `dm`/`sqlite`）；语句表达不了的数据订正（如 v2 存量明文加密）附 `dataFix` 回调——必须幂等（中断重跑不重复处理），`FieldCipher` 密钥经 `SchemaMigrator` 构造函数注入，含 dataFix 的迁移未注入密钥时启动即报错（DDL 不落半途状态）；
- `database/` 仅保留 `01_init_schema.sql`（表空间 + 应用账号——DBA 级对象创建进不了应用代码）；开发期推倒重来：达梦 `./tools/init_db.sh`（DROP USER 重建 + 迁移 + 演示账号），单机版删数据文件。

### 前端（client）— MVVM

- **导入约定**：统一 `import 'package:material_ui/material_ui.dart';`（全仓库 0 处 `flutter/material.dart`），新页面遵循；
- **全局对象**在 `lib/main.dart`：`token`（登录令牌）、`sessionKey`（会话 API 加密密钥，随登录下发、与 token 同生命周期）、`loginUser`（当前登录用户）——三者均由 `LoginViewModel` 登录成功写入、注销时清空；另有 `getIt`（服务定位器）——Serverpod 的 `client` 已随迁移移除；
- **Service 模式**：登录后的接口调用统一走 `services/base/base_service.dart` 的 `BaseService`（`get`/`post`：自动携带 Bearer token、请求体封信封、响应解信封并逐项校验 `code/message/data`，失败抛带 message 的异常、成功返回 data，上层 VM 再 `X.fromJson` 还原模型）。登录等明文接口留在 `AuthService`（自持 `http.Client` 明文调用后自行校验）——**不要**把 `login` 改走 `BaseService.post`：登录前拿不到 `token`/`sessionKey`，且服务端登录接口在明文白名单内、不收信封。新 Service 经 `getIt<BaseService>()` 调用，并在 `main.dart` 的 `setupServiceLocator()` 中注册。注意：`AdminDivisionsService` / `LogService` 仍是骨架（后端调用全部被注释），接线时经 `BaseService` 重写；
- **ViewModel 模式**（参照 `hospital_management_view_model.dart`）：私有字段 + getter、`_loading`/`_errorMsg` 状态、状态变更后 `notifyListeners()`、异步方法返回 `Future<bool>` 表示成败。新 ViewModel 必须注册到 `main.dart` 的 `MultiProvider`；
- **新页面接入路由**：菜单项在 `main_view_model.dart` 的 `menus` 列表中定义（带 `route`），页面构造器注册到 `lib/routes/menu_routes.dart`（key 与 `MenuItem.route` 一致）；
- 后端地址配置在 `assets/config.json` 的 `apiUrl`，`main()` 中分别调用 `AuthService.loadConfig()` 与 `BaseService.loadConfig()` 读取；`http` 包已在 client 依赖中。

### 安全层现状（报文加密）

前后端 API 通信已启用**信封加密**（等保通信保密性/完整性要求），而非此前的明文 JSON：

- 算法与信封格式：AES-256-GCM，`{'payload': '<base64(nonce[12] + 密文 + 认证标签[16])>'}`，解开后是原始 JSON 对象（nonce 每次报文随机）；
- 加解密实现前后端共享：`common/lib/utils/security_util.dart` 的 `SecurePayload`（`seal`/`open`/`generateSessionKey`，依赖 `cryptography` 包），失败抛 `SecurePayloadException`；
- 会话密钥由登录接口随 token 一起下发（base64 的 32 字节随机数），与 token 同生命周期；客户端存全局 `sessionKey`，注销清空；
- 服务端 `routes/api/_middleware.dart` 统一处理 `/api/**`：白名单 `/api/auth/login`、`/api`（API 索引自描述）走明文；其余请求先凭 token `verifySession`，非 GET 请求解开请求体信封、明文经 `provider<ApiBody>` 注入管线（**业务路由取参必须用 `context.read<ApiBody>().json`，勿直接 `request.json()`——那是密文**；模型在 `server/lib/models/api_body.dart`），路由响应的 `{code,message,data}` 整体封入信封返回；无有效会话或解密失败时返回**明文错误**（此时客户端没有可用密钥，无法解密错误响应）；
- 客户端 `BaseService` 做对称封装（自动带 token、封/解信封、校验统一响应格式后返回 data）；登录前无密钥的接口（目前仅 login）留在 `AuthService` 明文调用；
- 旧架构的 AES-128-CBC + MD5（`client/utils/security_util.dart`）**已随本次改造删除**；`AdminDivisionsService` / `LogService` 骨架中被注释的旧调用仍引用旧 `SecurityUtil`，接线时按 `BaseService` 协议重写，勿照抄注释代码。

### 字段级存储加密（等保，服务端）

敏感个人信息字段（首期 `SYS_USER.PHONE`）在数据库中加密存储，DBA 与拖库者均无法还原明文：

- 实现：`server/lib/security/field_cipher.dart` 的 `FieldCipher`（依赖 `cryptography` 包），**仅服务端持有**——客户端收发的 JSON 中敏感字段仍是明文，由传输信封保护，客户端零改动；算法与传输信封同为 AES-256-GCM 但**密钥独立**；
- 密文格式 `v1:<base64(nonce+密文+标签)>`（`v1` 为密钥版本号，为将来轮换预留，当前仅 v1）；盲索引列 `<字段>_HMAC` 为 HMAC-SHA256 十六进制，供等值查询（查询范式见「数据库访问约定」）；
- 密钥管理：单一主密钥（base64 的 32 字节）经 HKDF-SHA256 按 `field-enc:<purpose>` / `field-mac:<purpose>` 派生加密与 MAC 子钥（每字段独立）。主密钥解析顺序：环境变量 `AICMHCS_FIELD_MASTER_KEY` → 密钥文件（默认 `data/aicmhcs.field.key`，首启自动生成并启动告警，单机版交付依赖此机制）——密钥文件须单独备份，**丢失即无法解密存量数据**；生产/等保环境必须用环境变量注入，密钥与数据库备份分开保存；
- 存量数据经 v2 迁移的 `dataFix` 自动加密回填（幂等）；`tool/seed_demo_data.dart` 写入演示账号时同样走 `FieldCipher` seal/mac；
- 已知局限：仅支持精确匹配（盲索引），模糊查询/排序/范围查询不可用；主密钥仍在应用服务器上（等保三级可后续演进为加密机/KMS 托管）。

## UI 风格设定（client）

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

1. 在 `server/lib/db/migrations.dart` 追加结构迁移（`DbMigration`，双方言语句，沿用 DDL 约定），启动后端或 `dart run tool/seed_demo_data.dart` 即自动应用；
2. 在 `common/lib/models/<模块>/` 写共享模型（`fromJson`/`toJson`，并在 `common/lib/model.dart` 追加 export）；DB 行解析放 `server` 服务层（如 `AuthService._loginUserFromRow`）；
3. 在 `server/lib/services/` 写业务服务（构造注入 `DatabaseGateway`）；需在路由中直接读取的，在 `main.dart` 用 `provider<T>` 注入；
4. 在 `server/routes/api/<模块>/` 写路由（统一响应格式 + `_error` helper + 业务异常转换）；非 GET 请求取参用 `context.read<ApiBody>().json`（加密中间件已解出明文）；
5. `cd server && dart analyze && dart test`；
6. 在 `client/lib/services/` 写 HTTP 服务：经 `getIt<BaseService>()` 的 `get`/`post` 调后端（自动加解密，拿到校验过的 data 后 `fromJson`），注册到 `setupServiceLocator()`；
7. 写 ViewModel 并注册到 `MultiProvider`；写页面（遵循「UI 风格设定」章节），注册菜单与路由；
8. `cd client && flutter analyze && flutter test`。

## 代码风格

- 客户端 `analysis_options.yaml` 设置 `formatter: trailing_commas: preserve`——格式化时保留既有尾随逗号写法，勿手动增删；服务端使用 `dart_frog_lint/recommended.yaml`（启用了 `public_member_api_docs`、`avoid_print`、`prefer_single_quotes` 等较严规则）；
- 服务端存量 lint 未清零（约百条 info，主要是 `public_member_api_docs` 与 `tool/` 脚本的 `print`），新代码至少做到不新增；无 CI 门禁，提交前本地自查；
- 文档注释格式统一：`///中文描述`、`///param x: 说明`、`///returns: 说明`；
- 字符串用单引号；变量声明常用 `var`（局部）。

## 测试

- 后端测试位于 `server/test/`，为纯单元测试（口令散列、令牌逻辑、`SecurePayload` 信封加解密、`FieldCipher` 字段加密与盲索引、v2 存量加密回填、达梦参数改写、SQLite 网关 / 结构迁移 / 登录链路集成），**不需要** DM8 实例或 Docker——SQLite 测试走 `:memory:`，Windows 下原生库自动回退系统 `winsqlite3.dll`，直接 `dart test`；
- 前端测试位于 `client/test/`，用 `flutter test`；现有登录链路 widget 测试（`FakeAuthService` 注入 `LoginViewModel`）：登录失败 SnackBar 提示、登录成功写入全局 `loginUser` 并同步 `MainViewModel` 工作副本——新增涉及登录/主界面的改动时仿照扩展；
- 原 GitHub Actions CI 已随信创迁移移除（仓库无 `.github/` 目录）。

## 当前已知 Mock / 待接线（勿误判为已接通）

- **后端已实现真实接口**：`POST /api/auth/login`、`GET /api/auth/me`、`GET /health`（数据库探活）——登录链路后端侧已通（达梦经 `init_db.sh` 初始化后可用，单机版 `AICMHCS_DB_DRIVER=sqlite` 首启自动建库）；
- **客户端登录已接通**：`LoginViewModel.login()` 调用真实后端，成功后写入全局 `token`、`sessionKey` 与 `loginUser`（`LoginUser.fromJson` 解析），登录页跳转主界面前经 `MainViewModel.syncLoginUser()` 刷新工作副本，注销时三者清空。注意 `MainViewModel` 的医院/院区/科室仍为本地默认示例（`_defaultWorkUser`，后端暂无对应接口），登录页科室下拉选值（纯名称、无 ID）暂未映射进 `loginUser.deptId`；
- 客户端 `AdminDivisionsService` / `LogService` 的后端调用全部被注释，行政区划联动当前**未接通**；医院管理加载与保存为 mock（`HospitalManagementViewModel` 中标注 `TODO`）。

改动这些区域时保留 TODO 标注与被注释的调用代码，不要顺手删除。

## 其他注意事项

- **密钥与口令**：`tools/init_db.sh` 内置开发机 SYSDBA 口令默认值；应用账号口令 `Aicmhcs@2026` 同时硬编码在 `init_db.sh`、`database/01_init_schema.sql` 与后端 `app_config.dart` 默认值中——不要在示例或文档中扩散这些值，生产环境必须覆盖；修改应用账号口令需多处（脚本 + SQL + 环境变量）同步；
- `./tools/init_db.sh` 会 `DROP USER AICMHCS CASCADE` 重建应用模式，执行前确认数据可丢弃；
- 必须以仓库根目录（而非子文件夹）打开 VS Code，`.vscode/launch.json` 的 F5 全栈启动（server `dart_frog dev` + client Chrome）才生效；
- 提交信息：中文短句描述变更（如「接入达梦数据库登录接口」），无 conventional-commit 前缀；
- `dmdpi.dll` 加载失败先确认 DM8 已安装且 `DM_HOME` 指向正确目录（`AICMHCS_DB_DRIVER=sqlite` 时不加载达梦库）；若自行扩展 SQL 拼接，注意绑定参数只支持 ASCII（见「数据库访问约定」）。
