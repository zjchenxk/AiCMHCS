import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/field_cipher.dart';

/// 用户类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / RoleException）。
final class UserException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const UserException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'UserException($httpStatus, $code): $message';
}

/// 用户管理服务：按医院列表、新增、修改与角色关联读写。
///
/// 经 DatabaseGateway 访问 SYS_USER（HOSP_ID 关联 SYS_HOSPITAL、DEPT_ID
/// 关联 SYS_DEPARTMENT，归属医院与挂载科室在新增时定死、不可改）与
/// SYS_USER_ROLE（用户-角色多对多，复合主键 USER_ID+ROLE_ID）。PHONE /
/// ID_CARD_NO 为 FieldCipher 密文存储并配 *_HMAC 盲索引列（本服务不提供
/// 按敏感字段查询，盲索引仅随写入同步维护）。USER_CODE 全局唯一（表上
/// 有 UK 约束兜底，本层先 COUNT 判重给出友好错误）。口令散列复用
/// AuthService.makeStoredPassword，PASSWORD 任何接口不下发。角色保存为
/// 全量覆盖（先清后插，网关 execute 不重试、无重复写入风险；网关无事务
/// 通道，清插非原子——中断重保存可自愈，不影响其他数据）。名称等含
/// 中文参数由达梦网关参数改写自动内联，业务层直接写参数化 SQL。
class UserService {
  /// 构造函数：注入数据库网关与字段加密器。
  UserService(this._db, this._cipher);

  final DatabaseGateway _db;
  final FieldCipher _cipher;

  /// 各字段长度上限（与表列宽对齐；PHONE / ID_CARD_NO 按明文长度校验，
  /// 密文由 FieldCipher 展开后仍远小于列宽）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 30;
  static const int _typeMaxLength = 20;
  static const int _phoneMaxLength = 20;
  static const int _idCardNoMaxLength = 20;
  static const int _extCodeMaxLength = 20;
  static const int _passwordMinLength = 8;
  static const int _passwordMaxLength = 32;
  static const int _signatureMaxLength = 1024 * 1024;
  static const int _avatarMaxLength = 1024 * 1024;

  /// 用户列表查询列（不含 PASSWORD——口令散列不出服务层）。
  static const String _columns =
      'ID, USER_CODE, USER_NAME, USER_TYPE, PERMISSION_LEVEL, PHONE, '
      'ID_CARD_NO, HIS_USER_CODE, MCHIS_USER_CODE, CERT_ID, '
      'AVATAR_IMAGE, SIGNATURE_IMAGE, DEPT_ID, HOSP_ID, STATUS';

  /// 查询指定医院下的全部用户（按创建顺序），携带各自拥有的角色 ID。
  Future<List<User>> listByHospital(String hospId) async {
    final hospValue = _toInt(hospId, '医院ID');
    final result = await _db.query(
      'SELECT $_columns FROM SYS_USER WHERE HOSP_ID = ? ORDER BY ID',
      [hospValue],
    );
    final rows = result.rowsAsMaps.toList();
    final roleIds = await _loadRoleIds(
      rows.map((row) => row['ID'] ?? '').where((v) => v.isNotEmpty),
    );
    return Future.wait(
      rows.map((row) async => _fromRow(row, roleIds[row['ID']] ?? const [])),
    );
  }

  /// 按 ID 查询单个用户，不存在时抛业务异常。
  Future<User> getById(String id) async {
    final result = await _db.query(
      'SELECT $_columns FROM SYS_USER WHERE ID = ?',
      [_toInt(id, '用户ID')],
    );
    if (result.rows.isEmpty) {
      throw UserException(400, 40001, '用户不存在：$id');
    }
    final roleIds = await _loadRoleIds([id]);
    return _fromRow(result.rowsAsMaps.first, roleIds[id] ?? const []);
  }

  /// 新增用户，返回新增后的对象。
  ///
  /// 校验：所属医院必须存在、挂载科室必须存在且属于该医院、登录账号
  /// 必填且全局唯一（回读新行 ID 的自然键）、姓名必填、用户类别与权限
  /// 级别必填、口令须满足等保三级复杂度（8-32 位、不含与账号相同的
  /// 口令、至少三类字符）、角色必须存在且属于该医院；手机号 / 身份证号
  /// 经 FieldCipher 加密并同步盲索引列。角色关联可为空。
  Future<User> create({
    required String hospId,
    required String deptId,
    required String userCode,
    required String userName,
    required String password,
    String? userType,
    String? permissionLevel,
    String? phone,
    String? idCardNo,
    String? hisUserCode,
    String? mchisUserCode,
    String? certId,
    String? avatarImage,
    String? signatureImage,
    String? status,
    List<String> roleIds = const [],
  }) async {
    final hospValue = await _ensureHospital(hospId);
    final deptValue = await _ensureDepartment(hospValue, deptId);
    final code = _required(userCode, '登录账号', _codeMaxLength);
    await _ensureUserCodeUnique(code);
    final name = _required(userName, '姓名', _nameMaxLength);
    final pwd = _requiredPassword(password, userCode: code);
    final type = _required(userType, '用户类别', _typeMaxLength);
    final level = _requiredLevel(permissionLevel);
    final phonePlain = _optional(phone, '手机号', _phoneMaxLength);
    final idCardPlain = _optional(idCardNo, '身份证号', _idCardNoMaxLength);
    final his = _optional(hisUserCode, 'HIS用户代码', _extCodeMaxLength);
    final mchis = _optional(mchisUserCode, '妇幼保健系统用户代码', _extCodeMaxLength);
    final cert = _optional(certId, 'CA证书ID', _extCodeMaxLength);
    final avatar = _optional(avatarImage, '用户头像', _avatarMaxLength);
    final signature = _optional(signatureImage, '手写签名', _signatureMaxLength);
    final statusValue = _parseStatus(status ?? '1');
    final roleValues = await _ensureRolesExist(hospValue, roleIds);

    await _db.execute(
      'INSERT INTO SYS_USER (USER_CODE, PASSWORD, USER_NAME, USER_TYPE, '
      'PERMISSION_LEVEL, PHONE, PHONE_HMAC, ID_CARD_NO, ID_CARD_NO_HMAC, '
      'HIS_USER_CODE, MCHIS_USER_CODE, CERT_ID, AVATAR_IMAGE, '
      'SIGNATURE_IMAGE, DEPT_ID, HOSP_ID, STATUS, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        code,
        AuthService.makeStoredPassword(pwd),
        name,
        type,
        level,
        await _cipher.seal(FieldCipher.phonePurpose, phonePlain),
        await _cipher.mac(FieldCipher.phonePurpose, phonePlain),
        await _cipher.seal(FieldCipher.idCardNoPurpose, idCardPlain),
        await _cipher.mac(FieldCipher.idCardNoPurpose, idCardPlain),
        his,
        mchis,
        cert,
        avatar,
        signature,
        deptValue,
        hospValue,
        statusValue,
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经全局唯一的登录账号回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_USER WHERE USER_CODE = ?',
      [code],
    );
    if (row.rows.isEmpty) {
      throw const UserException(500, 50000, '新增用户后回读失败');
    }
    final newId = row.rows.first[0]!;
    await _saveRoles(newId, roleValues);
    return getById(newId);
  }

  /// 修改用户（changes 为本次要更新的字段集合，键与 JSON 契约一致）。
  ///
  /// 可更新：userName / userType / permissionLevel / phone / idCardNo /
  /// status / hisUserCode / mchisUserCode / certId / avatarImage /
  /// signatureImage；值为 null 表示清空该列（仅可空列，userName /
  /// status / userType / permissionLevel 为必填不可清空）。登录账号
  /// （userCode）、归属医院、挂载科室（deptId）不可改；CREATE_TIME 不可
  /// 改，UPDATE_TIME 由本方法统一写入。password 非空时重置口令；roleIds
  /// 非 null 时全量覆盖角色关联（null 表示本次不动角色）。
  Future<User> update(String id, Map<String, Object?> changes, {String? password, List<String>? roleIds}) async {
    const allowed = <String>{
      'userName',
      'userType',
      'permissionLevel',
      'phone',
      'idCardNo',
      'status',
      'hisUserCode',
      'mchisUserCode',
      'certId',
      'avatarImage',
      'signatureImage',
    };
    for (final key in changes.keys) {
      if (!allowed.contains(key)) {
        throw UserException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _toInt(id, '用户ID');

    // 先解析目标值（含敏感字段重算密文与盲索引）
    final name = changes.containsKey('userName') ? _required(changes['userName']?.toString(), '姓名', _nameMaxLength) : null;
    // 用户类别 / 权限级别为必填项：传入 null（清空语义）直接拒绝
    final type = changes.containsKey('userType') ? _required(changes['userType']?.toString(), '用户类别', _typeMaxLength) : null;
    final level = changes.containsKey('permissionLevel') ? _requiredLevel(changes['permissionLevel']?.toString()) : null;
    final phonePlain = changes.containsKey('phone') ? _optional(changes['phone']?.toString(), '手机号', _phoneMaxLength) : null;
    final idCardPlain = changes.containsKey('idCardNo') ? _optional(changes['idCardNo']?.toString(), '身份证号', _idCardNoMaxLength) : null;
    final his = changes.containsKey('hisUserCode') ? _optional(changes['hisUserCode']?.toString(), 'HIS用户代码', _extCodeMaxLength) : null;
    final mchis = changes.containsKey('mchisUserCode')
        ? _optional(
            changes['mchisUserCode']?.toString(),
            '妇幼保健系统用户代码',
            _extCodeMaxLength,
          )
        : null;
    final cert = changes.containsKey('certId') ? _optional(changes['certId']?.toString(), 'CA证书ID', _extCodeMaxLength) : null;
    final avatar = changes.containsKey('avatarImage') ? _optional(changes['avatarImage']?.toString(), '用户头像', _avatarMaxLength) : null;
    final signature = changes.containsKey('signatureImage')
        ? _optional(
            changes['signatureImage']?.toString(),
            '手写签名',
            _signatureMaxLength,
          )
        : null;
    final statusValue = changes.containsKey('status') ? _parseStatus(changes['status']?.toString() ?? '') : null;
    final pwd = password == null || password.trim().isEmpty ? null : _requiredPassword(password, userCode: current.userCode);
    final roleValues = roleIds == null ? null : await _ensureRolesExist(_toInt(current.hospId, '医院ID'), roleIds);

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'userName':
          setters.add('USER_NAME = ?');
          params.add(name);
        case 'userType':
          setters.add('USER_TYPE = ?');
          params.add(type);
        case 'permissionLevel':
          setters.add('PERMISSION_LEVEL = ?');
          params.add(level);
        case 'phone':
          setters
            ..add('PHONE = ?')
            ..add('PHONE_HMAC = ?');
          params
            ..add(await _cipher.seal(FieldCipher.phonePurpose, phonePlain))
            ..add(await _cipher.mac(FieldCipher.phonePurpose, phonePlain));
        case 'idCardNo':
          setters
            ..add('ID_CARD_NO = ?')
            ..add('ID_CARD_NO_HMAC = ?');
          params
            ..add(await _cipher.seal(FieldCipher.idCardNoPurpose, idCardPlain))
            ..add(await _cipher.mac(FieldCipher.idCardNoPurpose, idCardPlain));
        case 'status':
          setters.add('STATUS = ?');
          params.add(statusValue);
        case 'hisUserCode':
          setters.add('HIS_USER_CODE = ?');
          params.add(his);
        case 'mchisUserCode':
          setters.add('MCHIS_USER_CODE = ?');
          params.add(mchis);
        case 'certId':
          setters.add('CERT_ID = ?');
          params.add(cert);
        case 'avatarImage':
          setters.add('AVATAR_IMAGE = ?');
          params.add(avatar);
        case 'signatureImage':
          setters.add('SIGNATURE_IMAGE = ?');
          params.add(signature);
      }
    }
    if (pwd != null) {
      setters.add('PASSWORD = ?');
      params.add(AuthService.makeStoredPassword(pwd));
    }

    if (setters.isNotEmpty) {
      setters.add('UPDATE_TIME = ?');
      params
        ..add(formatTimestamp(DateTime.now()))
        ..add(idValue);
      await _db.execute(
        'UPDATE SYS_USER SET ${setters.join(', ')} WHERE ID = ?',
        params,
      );
    }
    if (roleValues != null) {
      await _saveRoles(id, roleValues);
    }
    return getById(id);
  }

  /// 当前登录用户自助修改口令（与 update 的 password 管理员重置语义
  /// 分离）：先验证原口令，再按等保三级复杂度兜底校验新口令，通过后
  /// 更新 SYS_USER.PASSWORD 并刷新 UPDATE_TIME。
  ///
  /// 原口令验证必须与登录同源（同一散列算法与比对方式），见下方
  /// verifyPassword 调用处注释。
  Future<void> changePassword({required String id, required String oldPassword, required String newPassword}) async {
    // 单独取 PASSWORD（_columns 特意不含它），仅在本方法内部比对，
    // 不随任何响应下发
    final result = await _db.query(
      'SELECT PASSWORD, USER_CODE, STATUS FROM SYS_USER WHERE ID = ?',
      [id],
    );
    if (result.rows.isEmpty) {
      throw UserException(400, 40001, '用户不存在：$id');
    }
    final row = result.rowsAsMaps.first;
    final stored = row['PASSWORD'] ?? '';
    if (stored.isEmpty) {
      throw const UserException(500, 50000, '用户口令数据异常，请联系管理员');
    }
    if ((row['STATUS'] ?? '1') == '0') {
      throw const UserException(400, 40003, '用户已停用，无法修改密码');
    }

    // 原口令验证：与登录校验同源。
    if (!AuthService.verifyStoredPassword(stored, oldPassword)) {
      throw const UserException(400, 40003, '原密码不正确');
    }
    if (oldPassword == newPassword) {
      throw const UserException(400, 40002, '新密码不能与原密码相同');
    }

    // 服务端兜底做等保三级强口令校验（防绕过前端直调接口）
    final pwd = _requiredPassword(newPassword, userCode: row['USER_CODE'] ?? '');

    await _db.execute(
      'UPDATE SYS_USER SET PASSWORD = ?, UPDATE_TIME = ? WHERE ID = ?',
      [AuthService.makeStoredPassword(pwd), formatTimestamp(DateTime.now()), id],
    );
  }

  /// 从数据库行解析（手机号 / 身份证号解密为明文，传输由信封保护；
  /// 不带版本前缀的存量明文由 open 原样返回兜底）。
  Future<User> _fromRow(Map<String, String?> row, List<String> roleIds) async => User(
    id: row['ID'] ?? '',
    userCode: row['USER_CODE'] ?? '',
    userName: row['USER_NAME'] ?? '',
    userType: row['USER_TYPE'],
    permissionLevel: row['PERMISSION_LEVEL'],
    phone: await _cipher.open(FieldCipher.phonePurpose, row['PHONE']),
    idCardNo: await _cipher.open(FieldCipher.idCardNoPurpose, row['ID_CARD_NO']),
    hisUserCode: row['HIS_USER_CODE'],
    mchisUserCode: row['MCHIS_USER_CODE'],
    certId: row['CERT_ID'],
    avatarImage: row['AVATAR_IMAGE'],
    signatureImage: row['SIGNATURE_IMAGE'],
    deptId: row['DEPT_ID'],
    hospId: row['HOSP_ID'] ?? '',
    status: row['STATUS'],
    roleIds: List.unmodifiable(roleIds),
  );

  /// 批量查询用户拥有的角色 ID（按 USER_ID 分组、ROLE_ID 升序）。
  Future<Map<String, List<String>>> _loadRoleIds(Iterable<String> userIds) async {
    final ids = userIds.map((v) => _toInt(v, '用户ID')).toSet().toList(growable: false);
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final result = await _db.query(
      'SELECT USER_ID, ROLE_ID FROM SYS_USER_ROLE '
      'WHERE USER_ID IN ($placeholders) ORDER BY ROLE_ID',
      ids,
    );
    final grouped = <String, List<String>>{};
    for (final row in result.rowsAsMaps) {
      final userId = row['USER_ID'];
      final roleId = row['ROLE_ID'];
      if (userId == null || roleId == null) continue;
      (grouped[userId] ??= []).add(roleId);
    }
    return grouped;
  }

  /// 全量覆盖保存用户角色（先清空既有关联再逐条插入，空列表即清空）。
  Future<void> _saveRoles(String userId, List<int> roleIds) async {
    final idValue = _toInt(userId, '用户ID');
    await _db.execute(
      'DELETE FROM SYS_USER_ROLE WHERE USER_ID = ?',
      [idValue],
    );
    for (final roleId in roleIds) {
      await _db.execute(
        'INSERT INTO SYS_USER_ROLE (USER_ID, ROLE_ID) VALUES (?, ?)',
        [idValue, roleId],
      );
    }
  }

  /// 校验医院存在，返回其 int 形式 ID。
  Future<int> _ensureHospital(String hospId) async {
    final value = _toInt(hospId, '医院ID');
    final result = await _db.query(
      'SELECT ID FROM SYS_HOSPITAL WHERE ID = ?',
      [value],
    );
    if (result.rows.isEmpty) {
      throw UserException(400, 40001, '所属医院不存在：$hospId');
    }
    return value;
  }

  /// 校验挂载科室存在且属于指定医院，返回其 int 形式 ID。
  Future<int> _ensureDepartment(int hospId, String deptId) async {
    final value = _toInt(deptId, '科室ID');
    final result = await _db.query(
      'SELECT HOSP_ID FROM SYS_DEPARTMENT WHERE ID = ?',
      [value],
    );
    if (result.rows.isEmpty) {
      throw UserException(400, 40001, '挂载科室不存在：$deptId');
    }
    final deptHosp = int.tryParse(result.rowsAsMaps.first['HOSP_ID'] ?? '');
    if (deptHosp != hospId) {
      throw const UserException(400, 40001, '挂载科室不属于当前医院');
    }
    return value;
  }

  /// 校验角色 ID 全部存在于 SYS_ROLE 且属于指定医院，返回去重后的
  /// int 形式列表（防止跨医院绑定角色）。
  Future<List<int>> _ensureRolesExist(int hospId, List<String> roleIds) async {
    final values = <int>{};
    for (final roleId in roleIds) {
      values.add(_toInt(roleId, '角色ID'));
    }
    if (values.isEmpty) return [];
    final placeholders = List.filled(values.length, '?').join(', ');
    final result = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_ROLE '
      'WHERE HOSP_ID = ? AND ID IN ($placeholders)',
      [hospId, ...values],
    );
    if (int.parse(result.rowsAsMaps.first['CNT'] ?? '0') != values.length) {
      throw const UserException(400, 40001, '存在无效的角色，请刷新后重试');
    }
    return values.toList();
  }

  /// 校验登录账号全局唯一（USER_CODE 表上有 UK 约束兜底，此处先判重
  /// 给出友好错误）。
  Future<void> _ensureUserCodeUnique(String code) async {
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_USER WHERE USER_CODE = ?',
      [code],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw UserException(400, 40001, '登录账号已存在：$code');
    }
  }

  /// 口令校验（等保三级复杂度要求）：去空格、非空、8-32 位、不得与
  /// 登录账号相同、须包含大写字母 / 小写字母 / 数字 / 特殊字符中的
  /// 至少三类。前端表单有同规则即时提示，本方法为服务端兜底（防绕过
  /// 前端直调接口），两处规则须保持一致。
  String _requiredPassword(String password, {required String userCode}) {
    final v = password.trim();
    if (v.isEmpty) {
      throw const UserException(400, 40002, '密码不能为空');
    }
    if (v.length < _passwordMinLength || v.length > _passwordMaxLength) {
      throw const UserException(
        400,
        40002,
        '密码长度须在 $_passwordMinLength-$_passwordMaxLength 位之间',
      );
    }
    if (userCode.trim().isNotEmpty && v == userCode.trim()) {
      throw const UserException(400, 40002, '密码不能与登录账号相同');
    }
    var kinds = 0;
    if (RegExp(r'[A-Z]').hasMatch(v)) kinds++;
    if (RegExp(r'[a-z]').hasMatch(v)) kinds++;
    if (RegExp(r'[0-9]').hasMatch(v)) kinds++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(v)) kinds++;
    if (kinds < 3) {
      throw const UserException(
        400,
        40002,
        '密码复杂度不足：须包含大写字母、小写字母、数字、特殊字符中的至少三类',
      );
    }
    return v;
  }

  /// 权限级别校验（必填）：非空且须为 0 / 1 / 2，返回 int 形式。
  int _requiredLevel(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw const UserException(400, 40002, '权限级别不能为空');
    }
    if (v != '0' && v != '1' && v != '2') {
      throw const UserException(400, 40002, '权限级别须为 0、1 或 2');
    }
    return int.parse(v);
  }

  /// 状态校验：空报错（列 NOT NULL），否则须为 0-停用 / 1-启用，返回
  /// int 形式。
  int _parseStatus(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      throw const UserException(400, 40002, '状态不能为空');
    }
    if (v != '0' && v != '1') {
      throw const UserException(400, 40002, '状态须为 0-停用或 1-启用');
    }
    return int.parse(v);
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw UserException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw UserException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw UserException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
