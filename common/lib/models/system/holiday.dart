/// 国家法定节假日（BASE_HOLIDAY，按医院隔离）。
///
/// 一行表示一个法定节假日的放假区间（startDate ~ endDate 闭区间），
/// holidayType 节假日类型（1-元旦，2-春节，3-清明节，4-劳动节，
/// 5-端午节，6-中秋节，7-国庆节，8-其它，标签见 [holidayTypeLabels]）。
/// 创建人与医院由服务端从登录会话推导并冗余存储，客户端只读、修改不
/// 更新创建人。主键为数据库自增 BIGINT，经数据库网关以字符串返回。
/// 所有列经数据库网关以字符串返回。
class BaseHoliday {
  /// 节假日类型标签（下标 + 1 即 holidayType 取值；前后端共用单一来源）。
  static const List<String> holidayTypeLabels = [
    '元旦',
    '春节',
    '清明节',
    '劳动节',
    '端午节',
    '中秋节',
    '国庆节',
    '其它',
  ];

  /// 构造函数：注入节假日各字段。
  const BaseHoliday({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.holidayType,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（数据库自增 BIGINT，经网关以字符串携带）。
  final String id;

  /// 起始日期（yyyy-MM-dd）。
  final String startDate;

  /// 截止日期（yyyy-MM-dd，闭区间）。
  final String endDate;

  /// 节假日类型（1-8，标签见 [holidayTypeLabels]）。
  final int holidayType;

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

  /// 节假日类型标签（越界时回退「未知」）。
  String get holidayTypeLabel =>
    holidayType >= 1 && holidayType <= holidayTypeLabels.length ? holidayTypeLabels[holidayType - 1] : '未知';

  factory BaseHoliday.fromJson(Map<String, dynamic> json) {
    return BaseHoliday(
      id: json['id'] as String,
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      holidayType: json['holidayType'] as int,
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
      'startDate': startDate,
      'endDate': endDate,
      'holidayType': holidayType,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
