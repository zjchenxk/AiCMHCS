/// 指导建议模板（BASE_GUIDANCE_TEMPLATE，按医院隔离）。
///
/// 一行表示一个具名的指导建议模板（如「随访指导」「家庭干预建议」），
/// 模板下的具体条目见 [BaseGuidanceTemplateItem]。TEMPLATE_NAME 同医院
/// 内唯一经服务层校验；DISPLAY_ORDER 显示顺序可空（排序时非空在前、
/// 按值升序，空值按创建时间续后）。创建人与医院冗余列由服务端从登录
/// 会话推导并冗余存储，客户端只读、修改不更新创建人。主键为应用侧
/// 生成的 UUID v7，经数据库网关以字符串返回。
class BaseGuidanceTemplate {
  /// 构造函数：注入模板各字段。
  const BaseGuidanceTemplate({
    required this.id,
    required this.templateName,
    this.displayOrder,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7）。
  final String id;

  /// 模板名称（同医院唯一）。
  final String templateName;

  /// 显示顺序（可空；小值在前）。
  final int? displayOrder;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory BaseGuidanceTemplate.fromJson(Map<String, dynamic> json) {
    return BaseGuidanceTemplate(
      id: json['id'] as String,
      templateName: json['templateName'] as String,
      displayOrder: (json['displayOrder'] as num?)?.toInt(),
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String,
      hospId: json['hospId'] as String,
      hospName: json['hospName'] as String,
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateName': templateName,
      'displayOrder': displayOrder,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}

/// 指导建议模板项目（BASE_GUIDANCE_TEMPLATE_ITEM，按医院隔离）。
///
/// 一行表示某模板下的一条指导建议：GUIDANCE_TYPE 类别（可空，自由
/// 文本）+ GUIDANCE 内容（按 UTF-8 字节数限长，与列宽 1000 字节对齐）
/// + IS_PERSONAL 是否个人模板（'0'-否=公共 / '1'-是=个人）。经
/// TEMPLATE_ID 逻辑关联所属模板（不建物理外键），TEMPLATE_ID 不可改。
/// 创建人与医院/科室/院区冗余列由服务端从登录会话推导写入。
class BaseGuidanceTemplateItem {
  /// 是否个人模板取值：否（公共模板，全院可见）。
  static const String personalNo = '0';

  /// 是否个人模板取值：是（个人模板）。
  static const String personalYes = '1';

  /// 构造函数：注入模板项目各字段。
  const BaseGuidanceTemplateItem({
    required this.id,
    required this.templateId,
    this.guidanceType,
    required this.guidance,
    required this.isPersonal,
    required this.creatorId,
    required this.creatorName,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    required this.hospId,
    required this.hospName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7）。
  final String id;

  /// 所属模板 ID（UUID v7，逻辑引用 BASE_GUIDANCE_TEMPLATE.ID）。
  final String templateId;

  /// 指导建议类别（可空）。
  final String? guidanceType;

  /// 指导建议内容。
  final String guidance;

  /// 是否个人模板（'0'-否 / '1'-是）。
  final String isPersonal;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 科室 ID（创建人会话归属，可空）。
  final String? deptId;

  /// 科室名称（可空）。
  final String? deptName;

  /// 院区 ID（创建人会话归属，可空）。
  final String? campusId;

  /// 院区名称（可空）。
  final String? campusName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  /// 是否个人模板。
  bool get isPersonalTemplate => isPersonal == personalYes;

  factory BaseGuidanceTemplateItem.fromJson(Map<String, dynamic> json) {
    return BaseGuidanceTemplateItem(
      id: json['id'] as String,
      templateId: json['templateId'] as String,
      guidanceType: json['guidanceType'] as String?,
      guidance: json['guidance'] as String,
      isPersonal: json['isPersonal'] as String,
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String,
      deptId: json['deptId'] as String?,
      deptName: json['deptName'] as String?,
      campusId: json['campusId'] as String?,
      campusName: json['campusName'] as String?,
      hospId: json['hospId'] as String,
      hospName: json['hospName'] as String,
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'guidanceType': guidanceType,
      'guidance': guidance,
      'isPersonal': isPersonal,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'deptId': deptId,
      'deptName': deptName,
      'campusId': campusId,
      'campusName': campusName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
