import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/high_risk_factor_service.dart';

/// POST /api/highRiskFactor/update
/// 请求体：{id, riskFactorCode?, riskFactorName?, riskFactorCategory?,
/// riskFactorSubcategory?, riskColor?, riskLevel?, riskScore?}
/// （仅传本次要修改的字段；值为 null 表示清空可空列；编码同医院内
/// 唯一；医院从令牌会话推导，跨院 ID 按不存在处理）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id is! String || id.trim().isEmpty) {
    return _error(400, 40001, '高危因素ID不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护高危因素');
  }

  // 字段白名单透传（键与 JSON 契约一致，服务层再校验合法性）。
  const allowed = {
    'riskFactorCategory',
    'riskFactorSubcategory',
    'riskFactorCode',
    'riskFactorName',
    'riskColor',
    'riskLevel',
    'riskScore',
  };
  final changes = {
    for (final e in body.entries)
      if (allowed.contains(e.key)) e.key: e.value?.toString(),
  };

  final service = context.read<HighRiskFactorService>();
  try {
    // 医院隔离：跨院 ID 一律按不存在处理，不泄露其他医院数据
    final current = await service.getById(id.trim());
    if (current.hospId != hospId) {
      return _error(400, 40001, '高危因素不存在：${id.trim()}');
    }
    final factor = await service.update(id.trim(), changes);
    return Response.json(
      body: {
        'code': 0,
        'message': '保存成功',
        'data': {'factor': factor.toJson()},
      },
    );
  } on HighRiskFactorException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
