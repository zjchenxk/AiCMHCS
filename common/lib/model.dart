/// model 包统一出口（barrel）。
/// 使用方统一 `import 'package:common/model.dart';` 即可用到全部共享模型，
/// 无需逐个 import 具体文件；新增共享模型时在此追加一行 export。
export 'models/basic/province.dart';
export 'models/basic/city.dart';
export 'models/basic/county.dart';
export 'models/basic/town.dart';
export 'models/basic/village.dart';
export 'models/system/hospital.dart';
