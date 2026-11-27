import 'package:client/main.dart';
import 'package:client/services/guidance_template_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/views/system/guidance_item_form_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 指导建议选择对话框（初筛记录表【选择模板】，需求 9.2；2026-11-27
/// 起数据源改为指导建议模板项目表 BASE_GUIDANCE_TEMPLATE_ITEM）。
///
/// 数据从默认指导建议模板（[GuidanceTemplateService.defaultTemplateId]）
/// 的项目列表读取——经公用查询方法 queryItems(templateId)，服务端按
/// 指导建议类别升序、空类别排最后。顶部搜索框过滤列表；列表每条显示
/// 指导建议内容（最多两行），内容下方显示类别与创建人。交互：
/// - **双击**某条 → 关闭对话框并回传该条内容（单条选入）；
/// - **确定** → 把全部选中项内容合并（换行分隔）回传；
/// - **新增** → 共用 GuidanceItemFormDialog（按默认模板 ID 落库）；
/// - **修改/删除** → 对选中项（多条取第一条）操作（修改共用表单对
///   话框，删除带确认）；
/// - **取消** → 关闭且不回传。
class GuidanceTemplateDialog extends StatefulWidget {
  const GuidanceTemplateDialog({super.key, this.service});

  /// 服务覆写（测试注入用；缺省经服务定位器获取）。
  final GuidanceTemplateService? service;

  /// 打开对话框，返回选中项目内容（单条或合并文本；取消为 null）。
  static Future<String?> show(BuildContext context, {GuidanceTemplateService? service}) {
    return showDialog<String>(
      context: context,
      builder: (_) => GuidanceTemplateDialog(service: service),
    );
  }

  @override
  State<GuidanceTemplateDialog> createState() => _GuidanceTemplateDialogState();
}

class _GuidanceTemplateDialogState extends State<GuidanceTemplateDialog> {
  final TextEditingController _searchCtrl = TextEditingController();

  GuidanceTemplateService get _service => widget.service ?? getIt<GuidanceTemplateService>();

  List<BaseGuidanceTemplateItem> _items = [];

  bool _loading = true;

  String? _errorMsg;

  /// 选中项目 ID 集合（支持多选）。
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final items = await _service.queryItems(GuidanceTemplateService.defaultTemplateId);
      if (!mounted) return;
      setState(() {
        _items = items;
        // 移除已不存在的选中项
        _selectedIds.removeWhere((id) => !items.any((t) => t.id == id));
        _loading = false;
      });
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateDialog._load', e, st);
      if (!mounted) return;
      setState(() {
        _errorMsg = _messageOf(e);
        _loading = false;
      });
    }
  }

  /// 搜索过滤后的列表（内容或类别包含关键词）。
  List<BaseGuidanceTemplateItem> get _filtered {
    final kw = _searchCtrl.text.trim().toLowerCase();
    if (kw.isEmpty) return _items;
    return _items.where((t) => t.guidance.toLowerCase().contains(kw) || (t.guidanceType ?? '').toLowerCase().contains(kw)).toList();
  }

  /// 提示（错误/成功统一 SnackBar）。
  void _toast(String message, {bool error = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: error ? theme.colorScheme.onError : null)),
          backgroundColor: error ? theme.colorScheme.error : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 选中项（多条取第一条，用于修改/删除）。
  BaseGuidanceTemplateItem? get _firstSelected {
    for (final t in _items) {
      if (_selectedIds.contains(t.id)) return t;
    }
    return null;
  }

  /// 保存回调（新增/修改共用表单对话框）：直连服务按默认模板 ID 落库，
  /// 返回错误信息（null = 成功）。
  Future<String?> _saveItem(BaseGuidanceTemplateItem? item, {String? guidanceType, required String guidance, required bool personal}) async {
    final isPersonal = personal ? BaseGuidanceTemplateItem.personalYes : BaseGuidanceTemplateItem.personalNo;
    try {
      if (item == null) {
        await _service.createItem(
          templateId: GuidanceTemplateService.defaultTemplateId,
          guidanceType: guidanceType,
          guidance: guidance,
          isPersonal: isPersonal,
        );
      } else {
        await _service.updateItem(item.id, {
          'guidanceType': guidanceType,
          'guidance': guidance,
          'isPersonal': isPersonal,
        });
      }
      return null;
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateDialog._saveItem', e, st);
      return _messageOf(e);
    }
  }

  /// 新增指导建议（挂默认模板）。
  ///
  /// 前台业务入口新增默认【个人模板】（后台管理页入口默认公共模板，
  /// 2026-11-27 需求）。
  Future<void> _add() async {
    final saved = await GuidanceItemFormDialog.show(
      context,
      templateName: '初筛指导建议',
      defaultPersonal: true,
      onSave: ({String? guidanceType, required String guidance, required bool personal}) => _saveItem(null, guidanceType: guidanceType, guidance: guidance, personal: personal),
    );
    if (saved) await _load();
  }

  /// 修改选中的指导建议（多条取第一条）。
  Future<void> _edit() async {
    final target = _firstSelected;
    if (target == null) {
      _toast('请先选择要修改的指导建议', error: true);
      return;
    }
    final saved = await GuidanceItemFormDialog.show(
      context,
      templateName: '初筛指导建议',
      item: target,
      onSave: ({String? guidanceType, required String guidance, required bool personal}) => _saveItem(target, guidanceType: guidanceType, guidance: guidance, personal: personal),
    );
    if (saved) await _load();
  }

  /// 删除选中的指导建议（带确认）。
  Future<void> _delete() async {
    final target = _firstSelected;
    if (target == null) {
      _toast('请先选择要删除的指导建议', error: true);
      return;
    }
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('删除指导建议', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('将删除选中的指导建议，删除后不可恢复。确定删除吗？', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteItem(target.id);
      _toast('删除成功');
      await _load();
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateDialog._delete', e, st);
      _toast(_messageOf(e), error: true);
    }
  }

  /// 单条双击选入（直接关闭回传内容）。
  void _pickOne(BaseGuidanceTemplateItem item) {
    Navigator.of(context).pop(item.guidance);
  }

  /// 确定：合并全部选中项（按列表顺序，换行分隔）。
  void _confirm() {
    final all = [
      for (final t in _items)
        if (_selectedIds.contains(t.id)) t.guidance,
    ];
    if (all.isEmpty) {
      _toast('请至少选择一条指导建议', error: true);
      return;
    }
    Navigator.of(context).pop(all.join('\n'));
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '选择指导建议',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '双击某条直接选入；勾选多条后确定则合并（换行分隔）；按类别排序，无类别排最后',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '搜索指导建议内容或类别').copyWith(
                    prefixIcon: Icon(Icons.search_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _searchCtrl.clear(),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMsg != null
                      ? Center(
                          child: Text(
                            '指导建议加载失败：$_errorMsg',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : list.isEmpty
                      ? Center(
                          child: Text(
                            _items.isEmpty ? '暂无指导建议，可点击【新增】录入' : '没有匹配的指导建议',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final item = list[index];
                            final selected = _selectedIds.contains(item.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() {
                                    selected ? _selectedIds.remove(item.id) : _selectedIds.add(item.id);
                                  }),
                                  onDoubleTap: () => _pickOne(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                                      border: Border.all(
                                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          onChanged: (checked) => setState(() {
                                            (checked ?? false) ? _selectedIds.add(item.id) : _selectedIds.remove(item.id);
                                          }),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.guidance,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodyMedium,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${item.guidanceType?.trim().isNotEmpty ?? false ? item.guidanceType : '无类别'}　${item.creatorName}${item.isPersonalTemplate ? '（个人模板）' : ''}',
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Tooltip(
                      message: '新增指导建议',
                      child: OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add_outlined, size: 16), label: const Text('新增')),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '修改选中的指导建议',
                      child: OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('修改')),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '删除选中的指导建议',
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                        label: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => _load(), icon: const Icon(Icons.refresh_outlined, size: 16), label: const Text('刷新')),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _confirm, child: Text('确定（已选 ${_selectedIds.length} 条）')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(ThemeData theme, String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: border(theme.colorScheme.primary),
    );
  }
}
