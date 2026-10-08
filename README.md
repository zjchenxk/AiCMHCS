# AiCMHCS · 智慧儿童心理保健系统

> Smart Children Mental Health Care System（英文简写 **AiCMHCS**）
> Flutter Web 前端 + Dart Frog 后端 + 达梦 DM8 数据库的开发框架骨架，
> 已内置用户登录全链路（登录界面 → 登录 API → 数据库校验 → 会话令牌）。

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 前端 | Flutter 3.x（Web） | Material 3，登录页 + 主页，`http` 访问后端 |
| 后端 | Dart Frog | `POST /api/auth/login`、`GET /api/auth/me`、`GET /health` |
| 数据库 | 达梦 DM8 | 通过 **DPI 原生接口（dart:ffi 直绑 dmdpi.dll）** 访问，无官方 Dart 驱动 |

### 为什么用 FFI 直绑 DPI？

pub.dev 上没有达梦官方/社区 Dart 驱动。本框架依据 DM8 自带头文件
（`C:\dmdbms\drivers\dpi\include\DPI.h`）用 `dart:ffi` 直接绑定
`dmdpi.dll`，并解决了两个关键问题：

1. **DLL 依赖解析**：Windows 按绝对路径加载 DLL 时不检索其所在目录，
   `dmdpi → dmcomm → libcrypto-3-x64` 依赖链会全部报“找不到模块”。
   `Dpi.open()` 收集驱动目录及 dependencies 子目录的 DLL 做**多轮加载
   直到不动点**，逐层解开依赖（`server/lib/dm/dpi.dart`）。
2. **中文字符集**：数据库实例为 GB18030（`SF_GET_UNICODE_FLAG()=0`）。
   框架全程使用 DPI 的 **W 系列（UTF-16）接口**执行语句、读列名与数据，
   由 DPI 自动完成 GB18030 ↔ UTF-16 转码，Dart 侧始终处理 Unicode，
   中文姓名、错误消息全程无乱码（已实测：王心怡 ✓）。

已知限制：`dpi_bind_param` 无宽字符版本，**绑定参数只支持 ASCII**
（登录用户名等满足）；含中文的值需转义后经 W 路径内联（登录审计即如此实现）。

## 目录结构

```
AiCMHCS/
├── client/                 # Flutter Web 前端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/user.dart
│   │   ├── pages/            # LoginPage / HomePage
│   │   ├── services/auth_api.dart
│   │   └── theme/app_theme.dart
│   └── web/index.html
├── server/                  # Dart Frog 后端
│   ├── main.dart             # 自定义入口：启动时初始化 DB 网关并注入
│   ├── routes/
│   │   ├── _middleware.dart  # CORS + 全局异常兜底
│   │   ├── index.dart / health.dart
│   │   └── api/auth/         # login.dart / me.dart
│   ├── lib/
│   │   ├── app_config.dart   # 环境变量配置
│   │   ├── dm/
│   │   │   ├── dpi.dart      # DPI FFI 绑定 + DLL 加载器
│   │   │   ├── dm_database.dart  # 连接/查询/执行（W 路径）
│   │   │   └── dm_gateway.dart   # 独立隔离区 + 自动重连
│   │   ├── models/user_info.dart
│   │   └── services/auth_service.dart
│   ├── tool/generate_demo_data.dart  # 生成演示数据 SQL（盐化哈希）
│   └── test/
├── database/
│   ├── 01_init_schema.sql    # 表空间 AICMHCS + 应用账号（SYSDBA 执行）
│   ├── 02_create_tables.sql  # SYS_USER / SYS_LOGIN_LOG
│   └── 03_demo_data.sql      # 4 个演示账号（生成物，勿手改）
├── tools/
│   ├── init_db.sh            # 数据库初始化（UTF-8→GBK 转码后调 DIsql）
│   ├── start_backend.sh      # 构建并启动后端（8080 端口）
│   └── serve_frontend.sh     # 构建并静态托管前端（5173 端口）
└── README.md
```

## 环境要求

- Flutter ≥ 3.24（含 Dart ≥ 3.5）
- dart_frog CLI：`dart pub global activate dart_frog_cli`
- 本机安装 DM8（默认 `C:\dmdbms`；不同路径请设 `DM_HOME` 环境变量）
- DM8 实例运行中（本机 5236 端口）

## 快速开始

### 1. 初始化数据库（建表空间/账号/表/演示数据，可重复执行）

```bash
./tools/init_db.sh
```

脚本以 SYSDBA 执行 `01`（重建应用账号 AICMHCS，默认表空间 AICMHCS），
再以 AICMHCS 执行 `02`、`03`。仓库 SQL 为 UTF-8，脚本自动转 GBK 后调 DIsql。

### 2. 启动后端（http://localhost:8080）

```bash
./tools/start_backend.sh
```

> 注意：`dart_frog dev` 需要交互终端（无终端时 stdin 报错退出），
> 因此脚本使用生产模式 `dart_frog build` + `dart run build/bin/server.dart`。
> 在真实终端里做热重载开发可直接运行 `dart_frog dev`。

### 3. 启动前端（http://localhost:5173）

```bash
./tools/serve_frontend.sh          # 构建产物 + 静态托管
# 或开发模式：
cd client && flutter run -d chrome # 或 -d web-server --web-port 5173
```

后端地址默认 `http://localhost:8080`，可用编译参数覆盖：
`flutter run -d chrome --dart-define=AICMHCS_API_BASE=http://host:8080`

### 演示账号

| 用户名 | 密码 | 角色 |
|---|---|---|
| admin | Admin@123 | 系统管理员 |
| doctor01 | Doctor@123 | 儿童心理医生 |
| teacher01 | Teacher@123 | 教师 |
| parent01 | Parent@123 | 家长 |

## API

统一响应格式：`{"code": 0, "message": "...", "data": ...}`，`code=0` 为成功。

### POST /api/auth/login

```json
// 请求
{"username": "doctor01", "password": "Doctor@123"}

// 响应 200
{"code":0,"message":"登录成功","data":{
  "token":"<64位十六进制>","tokenType":"Bearer","expiresIn":7200,
  "user":{"id":2,"username":"doctor01","realName":"王心怡",
           "roleCode":"DOCTOR","roleName":"儿童心理医生",
           "phone":"13900000111","lastLoginAt":"2026-09-30 15:13:58"}}}
```

错误：40001 参数为空（400）；40101 用户名或密码错误（401）；40301 账号停用（403）。

### GET /api/auth/me

请求头 `Authorization: Bearer <token>`，返回当前用户；令牌无效/过期返回 401。
令牌存于内存（重启后失效，有效期 2 小时滑动续期），生产环境应落库或接 Redis。

### GET /health

数据库探活（经 FFI 走 `SELECT 1`），返回状态与耗时。

## 数据库对象（模式 AICMHCS）

- **SYS_USER** 系统用户表：ID/USERNAME/PASSWORD(`salt:sha256`)/REAL_NAME/
  ROLE_CODE(ADMIN|DOCTOR|TEACHER|PARENT)/PHONE/STATUS/LAST_LOGIN_AT/时间戳
- **SYS_LOGIN_LOG** 登录审计：USER_ID/USERNAME/LOGIN_IP/LOGIN_TIME/
  LOGIN_RESULT(SUCCESS|FAIL)/FAIL_REASON

口令算法：`sha256(salt + password)` 十六进制，存储 `salt:hash`；
后端 `AuthService` 与 `server/tool/generate_demo_data.dart` 保持一致。
修改演示数据后重新生成：

```bash
cd server && dart run tool/generate_demo_data.dart > ../database/03_demo_data.sql
```

## 配置（环境变量）

| 变量 | 默认值 | 说明 |
|---|---|---|
| AICMHCS_DB_HOST | LOCALHOST | 数据库主机 |
| AICMHCS_DB_PORT | 5236 | 数据库端口 |
| AICMHCS_DB_USER | AICMHCS | 应用账号（最小权限，不用 SYSDBA） |
| AICMHCS_DB_PASSWORD | Aicmhcs@2026 | 应用账号口令 |
| DM_HOME | C:\dmdbms | 达梦安装目录（定位 dmdpi.dll） |
| DM_SYSDBA_PWD | （见 tools/init_db.sh） | 仅初始化脚本用，生产环境务必覆盖 |

## 测试与验证

- `cd server && dart test` —— 口令散列/令牌单元测试
- `cd server && dart analyze` / `cd client && flutter analyze`
- 浏览器实测记录见 `gui-test-screenshots/`：T1 登录页布局与中文渲染、
  T2 错误口令提示、T3 登录成功页（王心怡/儿童心理医生）均通过

## 常见问题

- **dmdpi.dll 加载失败**：确认 DM8 已安装且 `DM_HOME` 指向正确目录
- **中文乱码**：本框架 W 路径已解决；若自行扩展 SQL 拼接，注意参数绑定
  只支持 ASCII（见上文“已知限制”）
- **端口占用（10048）**：`netstat -ano | findstr :8080` 找到 PID 后
  `taskkill /F /PID <pid>`，或直接重跑 `tools/start_backend.sh`（会先清理）
- **初始化脚本中文报错**：确认 SQL 文件为 UTF-8、机器装有 iconv（Git Bash 自带）
