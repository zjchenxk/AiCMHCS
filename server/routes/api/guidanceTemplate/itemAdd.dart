import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/guidance_template_service.dart';

/// POST /api/guidanceTemplate/itemAdd
/// 请求体：{templateId, guidanceType?, guidance, isPersonal}（模板须属
/// 本院；类别可空、填则按 UTF-8 字节数限长；内容必填同规则限长；是否
/// 个人模板 0-否/1-是）。医院与创建人及科室/院区归属从令牌会话推导，
/// 不信任客户端上报。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final templateId = body['templateId'];
  final guidanceType = body['guidanceType']?.toString();
  final guidance = body['guidance'];
  final isPersonal = body['isPersonal'];
  if (templateId is! String || templateId.trim().isEmpty) {
    return _error(400, 40001, '模板ID不能为空');
  }
  if (guidance is! String || guidance.trim().isEmpty) {
    return _error(400, 40001, '指导建议不能为空');
  }
  final personal = isPersonal is String ? isPersonal.trim() : isPersonal?.toString().trim() ?? '';
  if (personal.isEmpty) {
    return _error(400, 40001, '是否个人模板不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护指导建议模板');
  }

  final service = context.read<GuidanceTemplateService>();
  try {
    final item = await service.createItem(
      templateId: templateId,
      guidanceType: guidanceType,
      guidance: guidance,
      isPersonal: personal,
      hospId: hospId,
      hospName: user!.hospName ?? '',
      creatorId: user.id,
      creatorName: user.userName,
      deptId: user.deptId,
      deptName: user.deptName,
      campusId: user.campusId,
      campusName: user.campusName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'item': item.toJson()},
      },
    );
  } on GuidanceTemplateException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
