import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../domain/money.dart';
import '../../domain/models.dart';
import '../../state/store.dart';
import '../bill/bill_sheet.dart';
import '../theme.dart';
import '../tx/tx_sheet.dart';
import '../widgets/empty_hint.dart';
import '../widgets/ledger_widgets.dart';

class BillPage extends StatefulWidget {
  const BillPage({super.key, required this.billId});
  final int billId;

  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  LedgerStore? _store;
  Bill? _bill;
  Contact? _contact;
  List<Tx> _txs = const [];
  List<Bill> _siblings = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    _load();
  }

  Future<void> _load() async {
    final repo = _store!.repo;
    try {
      final bill = await repo.requireBill(widget.billId);
      final contact = await repo.requireContact(bill.contactId);
      final all = await repo.billsOfContact(bill.contactId);
      final txs = await repo.txsOfBill(bill.id);
      if (!mounted) return;
      setState(() {
        _bill = bill;
        _contact = contact;
        _txs = txs;
        // 挪流水只能在同方向之间挪：方向不同意味着 kind 的含义不同，
        // 跨方向挪等于把借款算成还款。
        _siblings = all
            .where((b) => b.id != bill.id && b.direction == bill.direction)
            .toList(growable: false);
        _error = null;
      });
    } on LedgerFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
    _store!.invalidate();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on LedgerFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    if (mounted) await _load();
  }

  Future<void> _deleteTx(Tx tx) async {
    final pal = LedgerPalette.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔流水？'),
        content: Text('金额 ¥${formatCents(tx.amountCents)}，日期 ${tx.occurredDate}。\n'
            '删除后本账单余额会按剩余流水自动重算。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => _store!.repo.deleteTx(tx.id));
  }

  Future<void> _deleteBill(Bill bill) async {
    final pal = LedgerPalette.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除账单「${bill.title}」？'),
        content: const Text('这个账单下已经没有流水了，删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _store!.repo.deleteBill(bill.id);
      _store!.invalidate();
      if (mounted) Navigator.of(context).pop();
    } on LedgerFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final bill = _bill;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyHint(icon: Icons.error_outline, message: _error!),
      );
    }
    if (bill == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }

    final isIn = bill.direction == directionIn;
    final tone = pal.toneOfBalance(bill.balanceCents, direction: bill.direction);
    final ink = pal.onSoft(tone);

    return Scaffold(
      appBar: AppBar(
        // 两行标题：账单名 + 这是谁的账。
        // 「与 X 的往来」那行描述删掉之后，人名在这一屏就没有别的落点了，
        // 放在标题位比放在正文里更符合它「上下文」的身份。
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bill.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge),
            if (_contact != null)
              Text(_contact!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: pal.meta)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '编辑账单',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _run(() => showBillSheet(context,
                contactId: bill.contactId, bill: bill)),
          ),
          IconButton(
            tooltip: '删除账单',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteBill(bill),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120, top: 4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TintedCard(
                tone: tone,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _balanceLabel(isIn),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: ink),
                          ),
                        ),
                        ToneBadge(
                          text: directionShort(bill.direction),
                          tone: pal.toneOfDirection(bill.direction),
                          dot: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '¥${formatCentsCompact(bill.balanceCents)}',
                        maxLines: 1,
                        style: theme.textTheme.displaySmall
                            ?.copyWith(color: pal.ink(tone)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniSum(
                            label: isIn ? '累计借出' : '累计借入',
                            value: '¥${formatCents(bill.principalCents)}',
                            ink: ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniSum(
                            label: '已还',
                            value: '¥${formatCents(bill.paymentCents)}',
                            ink: ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (bill.note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TintedCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Text(bill.note!,
                      style: theme.textTheme.bodyMedium),
                ),
              ),
            const SizedBox(height: 18),
            SectionHeader(
              title: '流水',
              accent: pal.ink(tone),
              trailing: Text('${_txs.length} 笔',
                  style: theme.textTheme.labelMedium),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(21.5, 4, 16, 8),
              child: Text(
                '余额 = 借款合计 − 还款合计，增删改流水后自动重算。',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_txs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: TintedCard(
                  child: EmptyHint(
                    icon: Icons.receipt_long_outlined,
                    message: '这个账单还没有流水。\n记下第一笔借款，之后每次还款单独记一笔。',
                    actionLabel: '记第一笔借款',
                    onAction: () =>
                        _run(() => showTxSheet(context, bill: bill)),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TintedCard(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      for (var i = 0; i < _txs.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 50),
                            child: Divider(height: 1, color: pal.hairline),
                          ),
                        TxRow(
                          icon: _txs[i].isPayment
                              ? Icons.south_east
                              : Icons.north_east,
                          tone: _txs[i].isPayment
                              ? Tone.payable
                              : Tone.receivable,
                          title: txKindLabel(bill.direction, _txs[i].kind),
                          metaParts: [
                            _txs[i].occurredDate,
                            _txs[i].channel,
                            _txs[i].note,
                          ],
                          amount:
                              '${txSign(_txs[i].kind)}¥${formatCents(_txs[i].amountCents)}',
                          onTap: () => _run(() => showTxSheet(context,
                              bill: bill,
                              tx: _txs[i],
                              movableTargets: _siblings)),
                          onLongPress: () => _showTxMenu(_txs[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _run(() => showTxSheet(context,
                    bill: bill, initialKind: kindPrincipal)),
                icon: Icon(Icons.north_east, size: 18, color: pal.receivable),
                style: OutlinedButton.styleFrom(
                    foregroundColor: pal.receivable),
                label: Text(isIn ? '记借出' : '记借入'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _run(() => showTxSheet(context,
                    bill: bill, initialKind: kindPayment)),
                icon: const Icon(Icons.south_east, size: 18),
                style: FilledButton.styleFrom(backgroundColor: pal.payable),
                label: const Text('记还款'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _balanceLabel(bool isIn) {
    if (_bill!.isSettled) return '已结清';
    if (_bill!.isOverpaid) return isIn ? '已多收，可抵扣' : '已多付，可要回';
    return isIn ? '剩余未收' : '剩余未付';
  }

  void _showTxMenu(Tx t) {
    final pal = LedgerPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑这笔'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _run(() => showTxSheet(context,
                    bill: _bill!, tx: t, movableTargets: _siblings));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: pal.danger),
              title: Text('删除这笔',
                  style: TextStyle(color: pal.danger)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _deleteTx(t);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 主视觉里的次级数字块：白底半透明，永远比主金额低一级。
class _MiniSum extends StatelessWidget {
  const _MiniSum({
    required this.label,
    required this.value,
    required this.ink,
  });
  final String label;
  final String value;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: ink),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
