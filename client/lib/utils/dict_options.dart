import 'package:client/main.dart';
import 'package:client/services/dict_service.dart';
import 'package:common/model.dart';

/// 数据字典下拉选项公共绑定（client 端全局共享）。
///
/// 按字典编码（BASE_DICT.DICT_CODE，如 0101001-国籍）取本院数据字典的
/// 数据项列表：首次经 [DictService.queryAll] 建立「编码→字典ID」映射并
/// 缓存，数据项经 [DictService.queryItems] 拉取后按「显示顺序（未设置
/// 靠后）→项目编码」排序缓存；同编码并发请求单飞合并，登录会话不变时
/// 重复绑定同一字典零开销。业务表单统一经本类绑定字典下拉（值存
/// BASE_DICT_ITEM.ITEM_VALUE），字典数据维护变更后可调 [clearCache]
/// 重新拉取。
class DictOptions {
  DictOptions._();

  /// 全局单例。
  static final DictOptions instance = DictOptions._();

  /// 经服务定位器取字典服务（登录后才可用；调用期取便于测试覆写）。
  DictService get _dicts => getIt<DictService>();

  /// 字典编码 → 字典 ID 映射（本院字典清单缓存标记）。
  final Map<String, String> _dictIdByCode = {};

  /// 字典编码 → 已排序数据项缓存。
  final Map<String, List<DictItem>> _itemsByCode = {};

  /// 进行中的加载（单飞：同编码并发请求合并为一次）。
  final Map<String, Future<List<DictItem>>> _loading = {};

  /// 本院字典清单是否已加载。
  bool _dictsLoaded = false;

  /// 取指定字典编码的数据项列表（按显示顺序→项目编码排序，缓存优先；
  /// 字典未配置/加载失败时返回空列表）。
  Future<List<DictItem>> itemsOf(String dictCode) {
    final cached = _itemsByCode[dictCode];
    if (cached != null) {
      return Future.value(cached);
    }
    return _loading.putIfAbsent(dictCode, () => _loadItems(dictCode));
  }

  /// 取指定字典编码的默认数据项（IS_DEFAULT='1'，无默认项返回 null）。
  Future<DictItem?> defaultItemOf(String dictCode) async {
    final items = await itemsOf(dictCode);
    for (final item in items) {
      if (item.isDefault == '1') {
        return item;
      }
    }
    return null;
  }

  /// 同步取已缓存的指定字典数据项（未缓存返回 null；表单收集阶段取
  /// 下拉默认项用，无需再次异步请求）。
  List<DictItem>? cachedItemsOf(String dictCode) => _itemsByCode[dictCode];

  /// 同步取已缓存字典的默认数据项（未缓存返回 null）。
  DictItem? cachedDefaultOf(String dictCode) {
    for (final item in cachedItemsOf(dictCode) ?? const <DictItem>[]) {
      if (item.isDefault == '1') {
        return item;
      }
    }
    return null;
  }

  /// 选项值是否为「其他」类选项（选中含「其他」字样的选项后激活对应
  /// 其他输入框）。
  static bool isOther(String? value) => value != null && value.contains('其他');

  /// 清空全部缓存（字典/数据项维护变更后调用，下次绑定重新拉取）。
  void clearCache() {
    _dictIdByCode.clear();
    _itemsByCode.clear();
    _loading.clear();
    _dictsLoaded = false;
  }

  /// 拉取并排序指定编码的数据项，写入缓存。
  Future<List<DictItem>> _loadItems(String dictCode) async {
    try {
      await _ensureDicts();
      final dictId = _dictIdByCode[dictCode];
      if (dictId == null) {
        // 本院未配置该字典：缓存空列表，避免每次绑定都重复查询
        return _itemsByCode[dictCode] = const [];
      }
      final items = await _dicts.queryItems(dictId);
      final sorted = [...items]..sort(_compareOrderAndCode);
      return _itemsByCode[dictCode] = List.unmodifiable(sorted);
    } finally {
      _loading.remove(dictCode);
    }
  }

  /// 拉取本院全部字典并建立「编码→字典ID」映射。
  Future<void> _ensureDicts() async {
    if (_dictsLoaded) {
      return;
    }
    final dicts = await _dicts.queryAll();
    _dictIdByCode
      ..clear()
      ..addEntries(dicts.map((d) => MapEntry(d.dictCode, d.id)));
    _dictsLoaded = true;
  }

  /// 数据项排序：显示顺序（未设置靠后）→ 项目编码。
  int _compareOrderAndCode(DictItem a, DictItem b) {
    final ao = int.tryParse(a.displayOrder ?? '');
    final bo = int.tryParse(b.displayOrder ?? '');
    if (ao != null && bo != null) {
      if (ao != bo) return ao.compareTo(bo);
    } else if (ao != null) {
      return -1;
    } else if (bo != null) {
      return 1;
    }
    return a.itemCode.compareTo(b.itemCode);
  }
}
