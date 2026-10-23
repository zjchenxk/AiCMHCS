// 结构迁移注册表（建表、加列等全部结构变更在此按版本维护，双方言）。
//
// 铁律：
// 1. 已发布的迁移不可修改，只能向后追加新版本（版本号严格递增）；
// 2. 迁移里不要写 DROP TABLE IF EXISTS——对升级用户而言那是数据丢失，
//    开发期推倒重来：达梦库执行 ./tools/init_db.sh 重建应用模式，
//    单机版直接删除数据文件；
// 3. 演示/测试数据不写进迁移（生产环境不得自动长出演示账号），
//    见 tool/seed_demo_data.dart；
// 4. 通用语句放 common，方言专属（COMMENT ON、类型差异）放 dm/sqlite；
// 5. SQLite 无 COMMENT ON，注释以 `--` 形式附在语句内；
// 6. 语句表达不了的数据订正（如存量明文字段加密）用 dataFix 回调，
//    密钥经 SchemaMigrator 注入，回调必须幂等（中断重跑不重复处理）。
import 'package:server/db/database_gateway.dart';
import 'package:server/db/migration.dart';
import 'package:server/security/field_cipher.dart';

const dbMigrations = <DbMigration>[
  DbMigration(
    version: 1,
    description: '基础表：SYS_USER、SYS_LOGIN_LOG',
    dm: [
      '''
CREATE TABLE SYS_USER (
  ID            BIGINT IDENTITY(1, 1) NOT NULL,
  USER_CODE     VARCHAR(50)  NOT NULL,
  PASSWORD      VARCHAR(128) NOT NULL,
  USER_NAME     VARCHAR(50)  NOT NULL,
  ROLE_CODE     VARCHAR(20)  NOT NULL,
  PHONE         VARCHAR(20),
  STATUS        INT DEFAULT 1 NOT NULL,
  LAST_LOGIN_AT TIMESTAMP(0),
  CREATED_AT    TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  UPDATED_AT    TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT PK_SYS_USER PRIMARY KEY (ID),
  CONSTRAINT UK_SYS_USER_USER_CODE UNIQUE (USER_CODE)
)''',
      "COMMENT ON TABLE SYS_USER IS '系统用户表'",
      "COMMENT ON COLUMN SYS_USER.ID IS '用户ID'",
      "COMMENT ON COLUMN SYS_USER.USER_CODE IS '登录名'",
      "COMMENT ON COLUMN SYS_USER.PASSWORD IS '口令（salt:sha256hex）'",
      "COMMENT ON COLUMN SYS_USER.USER_NAME IS '姓名'",
      "COMMENT ON COLUMN SYS_USER.ROLE_CODE IS '角色：ADMIN/DOCTOR/TEACHER/PARENT'",
      "COMMENT ON COLUMN SYS_USER.PHONE IS '联系电话'",
      "COMMENT ON COLUMN SYS_USER.STATUS IS '状态：1=启用 0=停用'",
      "COMMENT ON COLUMN SYS_USER.LAST_LOGIN_AT IS '最近登录时间'",
      "COMMENT ON COLUMN SYS_USER.CREATED_AT IS '创建时间'",
      "COMMENT ON COLUMN SYS_USER.UPDATED_AT IS '更新时间'",
      '''
CREATE TABLE SYS_LOGIN_LOG (
  ID           BIGINT IDENTITY(1, 1) NOT NULL,
  USER_ID      BIGINT,
  USER_CODE    VARCHAR(50)  NOT NULL,
  LOGIN_IP     VARCHAR(50),
  LOGIN_TIME   TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  LOGIN_RESULT VARCHAR(20)  NOT NULL,
  FAIL_REASON  VARCHAR(100),
  CONSTRAINT PK_SYS_LOGIN_LOG PRIMARY KEY (ID)
)''',
      "COMMENT ON TABLE SYS_LOGIN_LOG IS '登录日志表'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.USER_ID IS '用户ID（登录失败且用户不存在时为空）'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.USER_CODE IS '登录名'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.LOGIN_IP IS '登录来源IP'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.LOGIN_TIME IS '登录时间'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.LOGIN_RESULT IS '结果：SUCCESS/FAIL'",
      "COMMENT ON COLUMN SYS_LOGIN_LOG.FAIL_REASON IS '失败原因'",
      'CREATE INDEX IDX_SYS_LOGIN_LOG_TIME ON SYS_LOGIN_LOG (LOGIN_TIME)',
    ],
    sqlite: [
      '''
-- 系统用户表（时间列默认值仅为兜底，业务写入统一在 Dart 侧生成时间
-- 并参数绑定，见 formatTimestamp——SQLite 的 CURRENT_TIMESTAMP 是 UTC）
CREATE TABLE SYS_USER (
  ID            INTEGER PRIMARY KEY AUTOINCREMENT,
  USER_CODE     TEXT NOT NULL,
  PASSWORD      TEXT NOT NULL,
  USER_NAME     TEXT NOT NULL,
  ROLE_CODE     TEXT NOT NULL,
  PHONE         TEXT,
  STATUS        INTEGER NOT NULL DEFAULT 1,
  LAST_LOGIN_AT TEXT,
  CREATED_AT    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UPDATED_AT    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)''',
      'CREATE UNIQUE INDEX UK_SYS_USER_USER_CODE ON SYS_USER (USER_CODE)',
      '''
-- 登录日志表
CREATE TABLE SYS_LOGIN_LOG (
  ID           INTEGER PRIMARY KEY AUTOINCREMENT,
  USER_ID      INTEGER,
  USER_CODE    TEXT NOT NULL,
  LOGIN_IP     TEXT,
  LOGIN_TIME   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  LOGIN_RESULT TEXT NOT NULL,
  FAIL_REASON  TEXT
)''',
      'CREATE INDEX IDX_SYS_LOGIN_LOG_TIME ON SYS_LOGIN_LOG (LOGIN_TIME)',
    ],
  ),
  DbMigration(
    version: 2,
    description: 'SYS_USER.PHONE 改存 AES-GCM 密文，新增 PHONE_HMAC 盲索引列并回填存量',
    dm: [
      'ALTER TABLE SYS_USER ADD COLUMN PHONE_HMAC VARCHAR(64)',
      // 扩宽容纳密文（11 位号码密文约 55 字符；达梦 VARCHAR 按字节计，
      // 预留充足）。
      'ALTER TABLE SYS_USER MODIFY PHONE VARCHAR(256)',
      'CREATE INDEX IDX_SYS_USER_PHONE_HMAC ON SYS_USER (PHONE_HMAC)',
      "COMMENT ON COLUMN SYS_USER.PHONE IS '联系电话（AES-256-GCM 密文，v1: 前缀）'",
      "COMMENT ON COLUMN SYS_USER.PHONE_HMAC IS '联系电话 HMAC-SHA256 盲索引（应用侧密钥，供精确查询）'",
    ],
    sqlite: [
      '''
-- 联系电话 HMAC-SHA256 盲索引（应用侧密钥，供精确查询）
ALTER TABLE SYS_USER ADD COLUMN PHONE_HMAC TEXT
''',
      'CREATE INDEX IDX_SYS_USER_PHONE_HMAC ON SYS_USER (PHONE_HMAC)',
    ],
    dataFix: encryptExistingPhones,
  ),
];

/// v2 数据订正：存量明文联系电话加密写回并计算盲索引。
///
/// 幂等：已是密文（`v<N>:` 前缀）或 PHONE 为空的行跳过，中断后重跑
/// 不会重复处理；行级 UPDATE 走 execute（网关约定不重试，无重复写）。
Future<void> encryptExistingPhones(
  DatabaseGateway db,
  FieldCipher cipher,
) async {
  final rows = await db.query(
    'SELECT ID, PHONE FROM SYS_USER WHERE PHONE IS NOT NULL',
  );
  for (final row in rows.rowsAsMaps) {
    final id = row['ID'];
    final phone = row['PHONE'];
    if (id == null || phone == null || FieldCipher.looksEncrypted(phone)) {
      continue;
    }
    await db.execute(
      'UPDATE SYS_USER SET PHONE = ?, PHONE_HMAC = ? WHERE ID = ?',
      [
        await cipher.seal(FieldCipher.phonePurpose, phone),
        await cipher.mac(FieldCipher.phonePurpose, phone),
        id,
      ],
    );
  }
}
