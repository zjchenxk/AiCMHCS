import 'package:server/db/database_gateway.dart';
import 'package:server/db/migration.dart';
import 'package:server/db/migrations.dart';
import 'package:server/security/field_cipher.dart';

/// 结构迁移执行器：确保库结构与迁移注册表（默认 [dbMigrations]）的
/// 最新版本一致。
///
/// 版本历史记录在 SYS_SCHEMA_VERSION 表；已应用的迁移绝不重复执行。
/// 单条迁移内的语句逐条自动提交（达梦 DDL 隐式提交，无法整体回滚），
/// 失败时直接抛错中止启动，修复后重新执行会继续完成剩余版本。
class SchemaMigrator {
  SchemaMigrator(
    this._db, {
    List<DbMigration> migrations = dbMigrations,
    FieldCipher? fieldCipher,
  }) : _migrations = migrations,
       _fieldCipher = fieldCipher {
    _validateVersions();
  }

  /// 版本历史表名。
  static const versionTable = 'SYS_SCHEMA_VERSION';

  final DatabaseGateway _db;
  final List<DbMigration> _migrations;

  /// 数据订正回调（dataFix）使用的字段加密器；待应用迁移包含 dataFix
  /// 而未注入时，migrate() 在执行任何语句前即抛错。
  final FieldCipher? _fieldCipher;

  /// 应用所有未执行的迁移，返回本次实际应用的迁移（已是最新时为空）。
  Future<List<DbMigration>> migrate() async {
    await _ensureVersionTable();
    final applied = (await _db.query(
      'SELECT VERSION FROM $versionTable',
    )).rows.map((row) => int.parse(row.first!)).toSet();

    final pending = _migrations
        .where((m) => !applied.contains(m.version))
        .toList(growable: false);
    // 订正需要密钥且不可中断重来（DDL 已自动提交），执行任何语句前先
    // 校验注入，避免出现「结构已变更、数据未订正」的半途状态。
    if (pending.any((m) => m.dataFix != null) && _fieldCipher == null) {
      throw StateError(
        '待应用迁移包含数据订正（dataFix），需要字段加密密钥（FieldCipher），'
        '请经 SchemaMigrator 构造函数注入',
      );
    }
    for (final migration in pending) {
      for (final sql in migration.statementsFor(_db.dialect)) {
        await _db.executeDirect(sql);
      }
      final dataFix = migration.dataFix;
      if (dataFix != null) {
        await dataFix(_db, _fieldCipher!);
      }
      // 时间列由 Dart 侧生成后参数绑定（两库通用，见 formatTimestamp）。
      await _db.execute(
        'INSERT INTO $versionTable (VERSION, DESCRIPTION, APPLIED_AT) '
        'VALUES (?, ?, ?)',
        [
          migration.version,
          migration.description,
          formatTimestamp(
            DateTime.now(),
          ),
        ],
      );
    }
    return pending;
  }

  /// 版本表不存在时创建；若库中已有业务表但没有版本表，说明是迁移机制
  /// 启用前的存量结构，直接报错引导重建，避免半途建表冲突。
  Future<void> _ensureVersionTable() async {
    if (await _tableExists(versionTable)) return;
    if (await _tableExists('SYS_USER')) {
      throw StateError(
        '检测到未纳入迁移管理的存量结构（SYS_USER 已存在但没有 $versionTable '
        '版本表）。达梦库请执行 ./tools/init_db.sh 重建应用模式；'
        '单机版请删除数据文件后重试。',
      );
    }
    await _db.executeDirect(_versionTableDdl);
  }

  String get _versionTableDdl => switch (_db.dialect) {
    DbDialect.dm =>
      '''
CREATE TABLE $versionTable (
  VERSION     INT NOT NULL,
  DESCRIPTION VARCHAR(200) NOT NULL,
  APPLIED_AT  TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT PK_SYS_SCHEMA_VERSION PRIMARY KEY (VERSION)
)''',
    DbDialect.sqlite =>
      '''
CREATE TABLE $versionTable (
  VERSION     INTEGER PRIMARY KEY,
  DESCRIPTION TEXT NOT NULL,
  APPLIED_AT  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
)''',
  };

  /// 判断表是否存在（达梦查数据字典视图，SQLite 查 sqlite_master）。
  Future<bool> _tableExists(String name) async {
    final sql = switch (_db.dialect) {
      DbDialect.dm =>
        'SELECT COUNT(*) AS CNT FROM USER_TABLES WHERE TABLE_NAME = ?',
      DbDialect.sqlite =>
        "SELECT COUNT(*) AS CNT FROM sqlite_master WHERE type = 'table' AND name = ?",
    };
    final result = await _db.query(sql, [name]);
    return int.parse(result.rowsAsMaps.first['CNT'] ?? '0') > 0;
  }

  /// 校验注册表版本号严格递增，编程错误在启动阶段即暴露。
  void _validateVersions() {
    for (var i = 1; i < _migrations.length; i++) {
      if (_migrations[i].version <= _migrations[i - 1].version) {
        throw StateError(
          '迁移版本号必须严格递增：v${_migrations[i - 1].version} 之后出现了 '
          'v${_migrations[i].version}',
        );
      }
    }
  }
}
