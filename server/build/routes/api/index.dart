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
          {'method': 'POST', 'path': '/api/campus/query', 'desc': '院区查询（id 查详情；hospId 查指定医院下的院区列表；缺省查全部）'},
          {'method': 'POST', 'path': '/api/campus/add', 'desc': '新增院区（hospId 必填；code 必填全表唯一；name 同医院内唯一）'},
          {'method': 'POST', 'path': '/api/campus/update', 'desc': '修改院区（含调整归属医院）'},
          {'method': 'POST', 'path': '/api/campus/delete', 'desc': '删除单个院区（院区下存在科室时须先删除科室）'},
          {'method': 'POST', 'path': '/api/department/query', 'desc': '科室查询（id 查详情；hospId 查指定医院下的科室列表；缺省查全部）'},
          {'method': 'POST', 'path': '/api/department/add', 'desc': '新增科室（挂载目标 parentId/campusId 三选一；医院已设置院区时须挂院区下）'},
          {'method': 'POST', 'path': '/api/department/update', 'desc': '修改科室（id 与归属不可改，树形结构调整走增删）'},
          {'method': 'POST', 'path': '/api/department/delete', 'desc': '删除单个科室（存在下级科室时须先删除下级）'},
          {'method': 'POST', 'path': '/api/menu/query', 'desc': '菜单项目查询（id 查详情；缺省查全部，前端构建模块→菜单→操作树）'},
          {'method': 'POST', 'path': '/api/menu/add', 'desc': '新增菜单项目（itemCode 必填全表唯一；类型为菜单时路由必填）'},
          {'method': 'POST', 'path': '/api/menu/update', 'desc': '修改菜单项目（id 与上级不可改，树形结构调整走增删）'},
          {'method': 'POST', 'path': '/api/menu/delete', 'desc': '删除单个菜单项目（存在下级项目时须先删除下级）'},
          {'method': 'POST', 'path': '/api/role/query', 'desc': '角色查询（id 查详情；hospId 查指定医院下的角色列表）'},
          {'method': 'POST', 'path': '/api/role/add', 'desc': '新增角色（hospId 必填；编码/名称同医院内唯一）'},
          {'method': 'POST', 'path': '/api/role/update', 'desc': '修改角色（id 与所属医院不可改）'},
          {'method': 'POST', 'path': '/api/role/delete', 'desc': '删除单个角色（连同其菜单权限关联一并删除）'},
          {'method': 'POST', 'path': '/api/role/permissionQuery', 'desc': '查询角色已授权的菜单ID列表'},
          {'method': 'POST', 'path': '/api/role/permissionSave', 'desc': '全量保存角色菜单权限（空列表即清空权限）'},
          {'method': 'GET', 'path': '/health', 'desc': '健康检查（含数据库探活）'},
        ],
      },
    },
  );
}
