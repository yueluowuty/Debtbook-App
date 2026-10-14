import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../theme.dart';
import 'ledger_widgets.dart';

/// 账单详情页与人员页共用的流水列表块：每个自然月一张独立卡片，
/// 每页 [kTxPageSize] 条，页码状态由父页面持有（visibleCount = 页 × 10），
/// 点「更多」由父页面 +1 页重建。
const int kTxPageSize = 10;

/// 月份卡片内的文字竖线：标题左边缘和发丝线的两端都对到这儿。
/// 行自己那 12 的内边距在 TxRow 里（它还要服务首页列表），不在这儿统一。
const double _kFlowInset = 12;

class TxFlowCard extends StatelessWidget {
  const TxFlowCard({
    super.key,
    required this.txs,
    required this.visibleCount,
    required this.rowBuilder,
    this.onMore,
  });

  /// 全量流水，须按发生日期倒序（repo 的查询即是）。
  final List<Tx> txs;
  final int visibleCount;
  final Widget Function(Tx tx) rowBuilder;

  /// 还有未展示条目时的「更多」回调；null 或无剩余则不画按钮。
  final VoidCallback? onMore;

  /// 月份键：`2026-09-05` -> `2026年9月`；非法日期归进「其他」垫底。
  static String monthKeyOf(String occurredDate) {
    if (!isValidDateIso(occurredDate)) return '其他';
    final month = int.parse(occurredDate.substring(5, 7));
    return '${occurredDate.substring(0, 4)}年$month月';
  }

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final shown = txs.take(visibleCount < 0 ? 0 : visibleCount).toList(growable: false);

    // 同一月的行聚成一个区块（列表按日期倒序，月份天然连续）。
    final groups = <String, List<Tx>>{};
    for (final tx in shown) {
      groups.putIfAbsent(monthKeyOf(tx.occurredDate), () => []).add(tx);
    }

    // 每个自然月一张独立卡片：月份标题在卡顶，标题下一条发丝线，
    // 线的两端缩进到和下面内容同一条竖线上（不贴着卡片圆角）；
    // 行与行之间不画线 —— 行自己的上下留白已经把彼此分开了。
    final children = <Widget>[];
    for (final entry in groups.entries) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 10));
      }
      children.add(TintedCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthHeader(label: entry.key),
            Divider(
              height: 1,
              thickness: 1,
              indent: _kFlowInset,
              endIndent: _kFlowInset,
              color: pal.hairline,
            ),
            ...entry.value.map(rowBuilder),
          ],
        ),
      ));
    }

    final remaining = txs.length - shown.length;
    if (remaining > 0 && onMore != null) {
      children.add(const SizedBox(height: 2));
      children.add(TextButton.icon(
        onPressed: onMore,
        style: TextButton.styleFrom(
          minimumSize: const Size(double.infinity, 44),
          foregroundColor: pal.meta,
        ),
        icon: const Icon(Icons.expand_more, size: 18),
        label: const Text('更多'),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kFlowInset, 12, _kFlowInset, 6),
      child: Text(
        label,
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
