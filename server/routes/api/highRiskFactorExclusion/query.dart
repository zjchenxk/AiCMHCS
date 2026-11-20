import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/high_risk_factor_exclusion_service.dart';

/// POST /api/highRiskFactorExclusion/query
/// 请求体：{id} 查详情；缺省返回登录用户所属医院的全部互斥规则列表。
/// 医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护高危因素互斥规则');
  }

  final service = context.read<HighRiskFactorExclusionService>();
  try {
    final id = (body['id'] as String?)?.trim() ?? '';
    if (id.isNotEmpty) {
      final exclusion = await service.getById(id);
      // 医院隔离：跨院 ID 一律按不存在处理，不泄露其他医院数据
      if (exclusion.hospId != hospId) {
        return _error(400, 40001, '互斥规则不存在：$id');
      }
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'exclusion': exclusion.toJson()},
        },
      );
    }
    final exclusions = await service.listByHospital(hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'exclusions': exclusions.map((e) => e.toJson()).toList()},
      },
    );
  } on HighRiskFactorExclusionException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
