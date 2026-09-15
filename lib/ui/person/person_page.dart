import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../domain/money.dart';
import '../../domain/models.dart';
import '../../state/store.dart';
import '../bill/bill_page.dart';
import '../bill/bill_sheet.dart';
import '../contact/contact_sheet.dart';
import '../theme.dart';
import '../tx/tx_sheet.dart';
import '../widgets/empty_hint.dart';
import '../widgets/ledger_widgets.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.contactId, required this.name});
  final int contactId;
  final String name;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  LedgerStore? _store;
  Contact? _contact;
  List<Bill> _bills = const [];
  List<Tx> _txs = const [];
  String? _error;

  /// 「全部流水」默认收起：一个人几十笔流水时，账单列表会被顶到屏幕外，
  /// 而进这一页九成是为了看账单，不是翻流水。
  bool _txExpanded = false;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    _load();
  }

  Future<void> _load() async {
    final repo = _store!.repo;
    try {
      final results = await Future.wait([
        repo.requireContact(widget.contactId),
        repo.billsOfContact(widget.contactId),
        repo.txsOfContact(widget.contactId),
      ]);
      if (!mounted) return;
      setState(() {
        _contact = results[0] as Contact;
        _bills = results[1] as List<Bill>;
        _txs = results[2] as List<Tx>;
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

  /// 归还进度。应收侧的「已还」是他还我，应付侧的「已还」是我还他，
  /// 两边混成一个比值毫无意义，所以只取借款额更大的那一侧单独算。
  /// 用已经加载好的 _bills 现算，不再多查一次库。
  ({String sideLabel, int paid, int principal, Tone tone})? get _progress {
    int principalOf(Iterable<Bill> bs) =>
        bs.fold(0, (s, b) => s + b.principalCents);
    int paidOf(Iterable<Bill> bs) => bs.fold(0, (s, b) => s + b.paymentCents);

    final inBills = _bills.where((b) => b.direction == directionIn);
    final outBills = _bills.where((b) => b.direction == directionOut);
    final inPrincipal = principalOf(inBills);
    final outPrincipal = principalOf(outBills);
    if (inPrincipal == 0 && outPrincipal == 0) return null;
    return inPrincipal >= outPrincipal
        ? (
            sideLabel: '他还我',
            paid: paidOf(inBills),
            principal: inPrincipal,
            tone: Tone.receivable
          )
        : (
            sideLabel: '我还他',
            paid: paidOf(outBills),
            principal: outPrincipal,
            tone: Tone.payable
          );
  }

  /// 同一个人的账单之间不能撞色：只按标题哈希的话，「房租」和「押金」会落在同一格
  /// 青，反而分不出来。各自从自己的哈希位起步，撞了就往后挪一格 ——
  /// 账单数不超过 `billBarHues.length` 时必然互不相同。
  /// 第一笔例外：恒用主题深绿。它永远是最上面那张，颜色不变反而成了一个锚，
  /// 身份色只用来分「第二张往后是哪一单」。
  List<Color> get _barColors {
    final primary = Theme.of(context).colorScheme.primary;
    final used = <int>{};
    final out = <Color>[];
    for (var i = 0; i < _bills.length; i++) {
      if (i == 0) {
        out.add(primary);
        continue;
      }
      var slot = billBarHueSeed(_bills[i].title);
      while (used.contains(slot)) {
        slot = (slot + 1) % billBarHues.length;
      }
      used.add(slot);
      out.add(billBarHues[slot]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final contact = _contact;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: EmptyHint(icon: Icons.error_outline, message: _error!),
      );
    }
    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final receivable =
        _bills.where((b) => b.direction == directionIn).fold<int>(0, (s, b) => s + b.balanceCents);
    final payable =
        _bills.where((b) => b.direction == directionOut).fold<int>(0, (s, b) => s + b.balanceCents);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            PersonAvatar(
              name: contact.name,
              size: 34,
              muted: contact.archived,
              textStyle: Theme.of(context).textTheme.titleLarge,
              // 列表那边是「最多 5 个字 + 省略号」，这里不行：全名只有这一处落点。
              maxWidth: 220,
            ),
            // 手机号不校验格式，长串照样可能顶宽，只能给它在剩余宽度里省略。
            if (contact.phone != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  contact.phone!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert),
            onPressed: () => showContactActions(context, contact),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96, top: 4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SubtotalTile(
                        label: '他还欠我',
                        cents: receivable,
                        tone: Tone.receivable,
                        icon: Icons.north_east,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SubtotalTile(
                        label: '我欠他',
                        cents: payable,
                        tone: Tone.payable,
                        icon: Icons.south_east,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (contact.note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TintedCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2_outlined, size: 16, color: pal.meta),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(contact.note!,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: _RepaymentProgress(
                  sideLabel: _progress!.sideLabel,
                  paid: _progress!.paid,
                  principal: _progress!.principal,
                  tone: _progress!.tone,
                ),
              ),
            const SizedBox(height: 18),
            SectionHeader(
              title: '账单',
              accent: pal.receivable,
              trailing: TextButton.icon(
                onPressed: () =>
                    _run(() => showBillSheet(context, contactId: contact.id)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建账单'),
              ),
            ),
            const SizedBox(height: 6),
            if (_bills.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TintedCard(
                  tone: Tone.neutral,
                  onTap: () => _run(() => showBillSheet(context, contactId: contact.id)),
                  child: Row(
                    children: [
                      const IconBadge(icon: Icons.receipt_long_outlined, tone: Tone.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('还没有账单',
                                style: Theme.of(context).textTheme.titleMedium),
                            MetaLine(
                              gap: 2,
                              parts: ['一笔借款或一次往来都可以单独成一个账单'],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: pal.meta),
                    ],
                  ),
                ),
              )
            else
              for (var i = 0; i < _bills.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _BillCard(
                    bill: _bills[i],
                    barColor: _barColors[i],
                    onOpen: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BillPage(billId: _bills[i].id)));
                      if (context.mounted) await _load();
                    },
                    onQuickAdd: () =>
                        _run(() => showTxSheet(context, bill: _bills[i])),
                  ),
                ),
            const SizedBox(height: 10),
            SectionHeader(
              title: '全部流水',
              accent: pal.payable,
              trailing: _txs.isEmpty
                  ? null
                  : Text('${_txs.length} 笔',
                      style: Theme.of(context).textTheme.labelMedium),
              // 空的时候没有可折叠的东西，不给箭头也不给点击。
              onTap: _txs.isEmpty
                  ? null
                  : () => setState(() => _txExpanded = !_txExpanded),
              expanded: _txs.isEmpty ? null : _txExpanded,
            ),
            const SizedBox(height: 6),
            if (_txs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('还没有任何流水记录。',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else if (_txExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _TxTimeline(bills: _bills, txs: _txs),
              ),
          ],
        ),
      ),
    );
  }
}

/// 归还进度条。这里看的是比例，所以金额用压缩格式；
/// 精确到分的数字在下面的账单卡片里逐单可查。
class _RepaymentProgress extends StatelessWidget {
  const _RepaymentProgress({
    required this.sideLabel,
    required this.paid,
    required this.principal,
    required this.tone,
  });

  final String sideLabel;
  final int paid;
  final int principal;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    // 百分比留在整数分里算，只有进度条那一步才要 double。
    final percent = (paid * 100) ~/ principal;
    final percentText = (percent == 0 && paid > 0) ? '<1%' : '$percent%';
    return TintedCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '归还进度 · $sideLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: pal.meta),
                ),
              ),
              Text(
                percentText,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.ink(tone),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              // 超付时条子画满，但百分比照实写，不把 120% 藏成 100%。
              value: percent > 100 ? 1 : percent / 100,
              minHeight: 8,
              backgroundColor: pal.soft(tone),
              valueColor: AlwaysStoppedAnimation<Color>(pal.ink(tone)),
            ),
          ),
          MetaLine(
            gap: 6,
            parts: [
              '已还 ¥${formatCentsCompact(paid)}',
              '${sideLabel == '他还我' ? '借出' : '借入'} ¥${formatCentsCompact(principal)}',
            ],
          ),
        ],
      ),
    );
  }
}

class _SubtotalTile extends StatelessWidget {
  const _SubtotalTile({
    required this.label,
    required this.cents,
    required this.tone,
    required this.icon,
  });
  final String label;
  final int cents;
  final Tone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final empty = cents == 0;
    return TintedCard(
      tone: tone,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 14, color: pal.onSoft(tone).withValues(alpha: .75)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: pal.onSoft(tone)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${formatCentsCompact(cents)}',
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: empty ? pal.onSoft(tone).withValues(alpha: .45) : pal.ink(tone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard(
      {required this.bill,
      required this.barColor,
      required this.onOpen,
      required this.onQuickAdd});
  final Bill bill;

  /// 由页面统一分配：同一个人的账单之间不撞色。
  final Color barColor;
  final VoidCallback onOpen;
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final isIn = bill.direction == directionIn;
    final tone = pal.toneOfBalance(bill.balanceCents, direction: bill.direction);

    return TintedCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧色条按账单取色（同一账单标题永远同一格，同一个人的账单互不相同）：
            // 之前它跟着「应收绿 / 应付橙」走，三张应收账单叠在一起就是三条
            // 一模一样的绿，分不出这是哪一单。方向信息没丢 —— 「剩余未收/未付」
            // 的金额和大号余额都还是语义色。
            Container(width: 4, color: barColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bill.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 原来这里挂着一个「应收/应付」胶囊：方向其实一处没少，
                        // 左边 4px 色条、「剩余未收/未付」、下面的「借出 ¥…」都是，
                        // 三个地方说同一件事就是噪音。
                        FilledButton.tonal(
                          onPressed: onQuickAdd,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            // 主题把 filledButton 钉在 48 高 + labelLarge：
                            // 标题行会被顶得比文字高出一截，和当初把 IconButton
                            // 压到 34 是同一个理由。
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: theme.textTheme.labelMedium,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9)),
                          ),
                          child: const Text('记一笔'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _balanceLabel(isIn),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: pal.meta),
                    ),
                    const SizedBox(height: 1),
                    // 刻意不跟明细挤在一行：Row 给非 flex 孩子的是无限宽主约束，
                    // 千万级金额实测 RIGHT OVERFLOWED BY 6.6 PIXELS。
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '¥${formatCentsCompact(bill.balanceCents)}',
                        maxLines: 1,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: pal.ink(tone)),
                      ),
                    ),
                    MetaLine(
                      gap: 6,
                      parts: [
                        '${isIn ? '借出' : '借入'} ¥${formatCents(bill.principalCents)}',
                        '已还 ¥${formatCents(bill.paymentCents)}',
                        _dateRange(bill),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _balanceLabel(bool isIn) {
    if (bill.isSettled) return '已结清';
    if (bill.isOverpaid) return isIn ? '已多收，可抵扣' : '已多付，可要回';
    return isIn ? '剩余未收' : '剩余未付';
  }

  String? _dateRange(Bill b) {
    if (b.firstDate == null) return null;
    final first = formatDateDot(b.firstDate!);
    final last = formatDateDot(b.lastDate!);
    return first == last ? first : '$first ~ $last';
  }
}

class _TxTimeline extends StatelessWidget {
  const _TxTimeline({required this.bills, required this.txs});
  final List<Bill> bills;
  final List<Tx> txs;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final titles = <int, String>{for (final b in bills) b.id: b.title};

    return TintedCard(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < txs.length; i++) ...[
            if (i > 0)
              Padding(
                // 12 = TxRow 自己的横向内边距：行的左内容边就是那枚图标。
                padding: const EdgeInsets.only(left: 12),
                child: Divider(height: 1, color: pal.hairline),
              ),
            TxRow(
              icon: txs[i].isPayment ? Icons.south_east : Icons.north_east,
              tone: txs[i].isPayment ? Tone.payable : Tone.receivable,
              title: titles[txs[i].billId] ?? '已删除的账单',
              // 「还款/借款」不写第二遍了：箭头和金额正负号已经说了两遍，
              // 而这一屏真正区分每行的是账单名 —— 它已经在第一行了。
              metaParts: [
                formatDateDot(txs[i].occurredDate),
                if (txs[i].channel != null) txs[i].channel,
                txs[i].note,
              ],
              amount: '${txSign(txs[i].kind)}¥${formatCents(txs[i].amountCents)}',
            ),
          ],
        ],
      ),
    );
  }
}
