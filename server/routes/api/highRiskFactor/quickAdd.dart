import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/high_risk_factor_service.dart';

/// POST /api/highRiskFactor/quickAdd
/// 请求体：{riskColor, riskFactorName}。快速新增高危因素（儿童建档页
/// 高危因素 TAB 的「新增高危因素」入口）：大类固定「其它」、编码按高危
/// 颜色默认映射（黄 02990000 / 橙 03990000 / 红 04990000 / 紫 05990000，
/// 允许重复）、等级与分值为空。医院与创建人从令牌会话推导（不信任客户端
/// 上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final riskColor = body['riskColor'];
  final riskFactorName = body['riskFactorName'];
  if (riskColor is! String || riskFactorName is! String) {
    return _error(400, 40001, '高危颜色、高危因素名称不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护高危因素');
  }

  final service = context.read<HighRiskFactorService>();
  try {
    final factor = await service.quickCreate(
      riskColor: riskColor,
      riskFactorName: riskFactorName,
      hospId: hospId,
      hospName: user!.hospName ?? '',
      creatorId: user.id,
      creatorName: user.userName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
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
