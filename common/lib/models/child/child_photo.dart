/// 儿童照片（对应 CHILD_PHOTO 表，经 childId 逻辑关联儿童 CHILD_INFO，
/// 按医院隔离；同一儿童可保留多次拍照历史，界面与服务端均取创建时间
/// 最近的一条生效）。
///
/// photoBase64/avatarBase64 为 JPEG 图像的裸 base64 文本（无 data: 前缀，
/// 与 SYS_USER.AVATAR_IMAGE 同口径），传输由信封加密保护；列表/最近
/// 记录查询可不带 photoBase64 大图字段（仅回显头像时省流量）。
class ChildPhoto {
  /// 构造函数：注入儿童照片各字段。
  const ChildPhoto({
    required this.childId,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.id,
    this.photoBase64,
    this.avatarBase64,
    this.createTime,
    this.updateTime,
  });

  /// 主键（自增 ID 的字符串形式；未入库时为 null）。
  final String? id;

  /// 儿童 ID（CHILD_INFO.ID 的字符串形式）。
  final String childId;

  /// 照片（竖版 720×900，JPEG base64；查询最近记录回显头像时可省略）。
  final String? photoBase64;

  /// 头像（320×320，JPEG base64）。
  final String? avatarBase64;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间（即拍照入库时间，相对时间显示依据）。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory ChildPhoto.fromJson(Map<String, dynamic> json) {
    return ChildPhoto(
      id: json['id'] as String?,
      childId: json['childId'] as String? ?? '',
      photoBase64: json['photoBase64'] as String?,
      avatarBase64: json['avatarBase64'] as String?,
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      hospId: json['hospId'] as String? ?? '',
      hospName: json['hospName'] as String? ?? '',
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'childId': childId,
      'photoBase64': photoBase64,
      'avatarBase64': avatarBase64,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
