import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/high_risk_factor_service.dart';

/// POST /api/highRiskFactor/add
/// 请求体：{riskFactorCode, riskFactorName, riskFactorCategory?,
/// riskFactorSubcategory?, riskColor?, riskLevel?, riskScore?}
/// （编码/名称必填且编码同医院内唯一；医院与创建人从令牌会话推导，
/// 不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final riskFactorCode = body['riskFactorCode'];
  final riskFactorName = body['riskFactorName'];
  if (riskFactorCode is! String || riskFactorCode.trim().isEmpty) {
    return _error(400, 40001, '高危因素编码不能为空');
  }
  if (riskFactorName is! String || riskFactorName.trim().isEmpty) {
    return _error(400, 40001, '高危因素名称不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护高危因素');
  }

  final service = context.read<HighRiskFactorService>();
  try {
    final factor = await service.create(
      riskFactorCode: riskFactorCode,
      riskFactorName: riskFactorName,
      riskFactorCategory: body['riskFactorCategory']?.toString(),
      riskFactorSubcategory: body['riskFactorSubcategory']?.toString(),
      riskColor: body['riskColor']?.toString(),
      riskLevel: body['riskLevel']?.toString(),
      riskScore: body['riskScore']?.toString(),
      hospId: hospId,
      hospName: user!.hospName ?? '',
      creatorId: user.id,
      creatorName: user.userName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
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
