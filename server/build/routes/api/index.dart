import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        'name': 'AiCMHCS API',
        'version': 'v1',
        'endpoints': [
          {'method': 'POST', 'path': '/api/auth/login', 'desc': '用户登录'},
          {'method': 'GET', 'path': '/api/auth/me', 'desc': '当前登录用户'},
          {'method': 'POST', 'path': '/api/adminDivision/query', 'desc': '行政区划查询（code 查详情与子树规模；parentCode 缺省为省级查子级列表）'},
          {'method': 'POST', 'path': '/api/adminDivision/add', 'desc': '新增行政区划'},
          {'method': 'POST', 'path': '/api/adminDivision/update', 'desc': '修改行政区划（名称/编码，改编码级联更新下级父引用）'},
          {'method': 'POST', 'path': '/api/adminDivision/delete', 'desc': '级联删除行政区划及其全部下级'},
          {'method': 'POST', 'path': '/api/hospital/query', 'desc': '医院查询（id 查详情与子树规模；缺省查全部医院扁平列表）'},
          {'method': 'POST', 'path': '/api/hospital/add', 'desc': '新增医院（parentId 缺省为顶级；code 必填唯一）'},
          {'method': 'POST', 'path': '/api/hospital/update', 'desc': '修改医院（id 与上级不可改，树形结构调整走增删）'},
          {'method': 'POST', 'path': '/api/hospital/delete', 'desc': '级联删除医院及其全部下级'},
          {'method': 'GET', 'path': '/health', 'desc': '健康检查（含数据库探活）'},
        ],
      },
    },
  );
}
