import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 相似儿童选择对话框（共享组件）：可滚动列表展示儿童姓名、性别、出生
/// 日期、联系电话、居住地址，点选某行即返回该儿童档案。
///
/// [showCancelButton] 为 true 时（儿童建档重复检查场景）底部增加【取消】
/// 按钮——点击取消返回 null，调用方按业务语义处理（建档查重场景下取消
/// 表示「作为新儿童继续保存」）。
Future<ChildInfo?> showChildPickDialog(
  BuildContext context,
  List<ChildInfo> results, {
  String title = '共找到儿童，请选择',
  bool showCancelButton = false,
  String? cancelHint,
}) {
  return showDialog<ChildInfo>(
    context: context,
    builder: (dialogContext) => _ChildPickDialog(
      results: results,
      title: title,
      showCancelButton: showCancelButton,
      cancelHint: cancelHint,
    ),
  );
}

class _ChildPickDialog extends StatelessWidget {
  const _ChildPickDialog({required this.results, required this.title, required this.showCancelButton, this.cancelHint});

  final List<ChildInfo> results;

  final String title;

  final bool showCancelButton;

  final String? cancelHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                    Icon(Icons.person_search_outlined, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      '$title（${results.length} 名）',
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 多条命中可超出一屏：限制最大高度并支持滚动
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = results[index];
                      final sex = switch (c.sex) {
                        '1' => '男',
                        '2' => '女',
                        _ => '',
                      };
                      final address = [
                        c.addressProvince,
                        c.addressCity,
                        c.addressCounty,
                        c.addressTown,
                        c.addressVillage,
                        c.addressDetails,
                      ].whereType<String>().where((s) => s.isNotEmpty).join();
                      return GlassPanel(
                        blur: 12,
                        borderRadius: 12,
                        child: ListTile(
                          dense: true,
                          onTap: () => Navigator.of(context).pop(c),
                          title: Text(
                            '${c.name}${sex.isEmpty ? '' : '  $sex'}  ${c.birthDate}',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              if (c.phone != null && c.phone!.isNotEmpty) '电话 ${c.phone!}',
                              if (address.isNotEmpty) address,
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 18),
                        ),
                      );
                    },
                  ),
                ),
                if (showCancelButton) ...[
                  const SizedBox(height: 8),
                  if (cancelHint != null)
                    Text(
                      cancelHint!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
