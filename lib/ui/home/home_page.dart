import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/money.dart';
import '../../domain/models.dart';
import '../../state/store.dart';
import '../contact/contact_sheet.dart';
import '../data/data_page.dart';
import '../person/person_page.dart';
import '../theme.dart';
import '../widgets/empty_hint.dart';
import '../widgets/ledger_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  LedgerStore? _store;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = StoreScope.of(context);
  }

  /// 从人员/账单/数据页返回时重查一次。这几条查询都很轻，
  /// 不做「脏了才查」的判断，免得判断本身出错导致界面长期是旧的。
  void _refresh() {
    _store?.reload();
  }

  Future<void> _reload() async {
    await _store!.reload();
  }

  void _setFilter(HomeFilter f) {
    _store!.setFilter(f);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _reload,
          child: Column(
            children: [
              // 横幅是深绿渐变，而这一屏没有 AppBar 去管状态栏：
              // 默认深色图标压在绿色上，「3:47」和电量基本看不见。
              // 其余各屏有自己的 AppBar，进屏时会把样式换回深色。
              AnnotatedRegion<SystemUiOverlayStyle>(
                value: const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                ),
                child: _HeaderBanner(
                  store: store,
                  onTapFilter: _setFilter,
                  onOpenBackup: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const DataPage()));
                    if (context.mounted) _refresh();
                  },
                ),
              ),
              _SearchBar(
                controller: _search,
                store: store,
                onChanged: (v) {
                  store.setSearch(v);
                  _reload();
                },
                onToggleArchived: (v) {
                  store.setIncludeArchived(v);
                  _reload();
                },
              ),
              Expanded(
                child: store.loading
                    ? const Center(child: CircularProgressIndicator())
                    : _ContactList(
                        store: store,
                        onAdd: () async {
                          await showContactSheet(context);
                          if (context.mounted) _refresh();
                        },
                        onOpen: (c) async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  PersonPage(contactId: c.id, name: c.name)));
                          if (context.mounted) _refresh();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showContactSheet(context);
          if (context.mounted) _refresh();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('添加借款人'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _FooterNote(store: store),
    );
  }
}

/// 顶部绿色主视觉：净差一个数，应收/应付两个入口。
///
/// 上一版是三块一模一样的白底描边卡，谁都不突出，整屏只有一种绿。
/// 这里把「净差」抬成唯一主角，应收/应付降成它下面的两个可点筛选，
/// 用户打开 App 第一眼看的就是「到底谁欠我多少」。
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.store,
    required this.onTapFilter,
    required this.onOpenBackup,
  });
  final LedgerStore store;
  final ValueChanged<HomeFilter> onTapFilter;
  final VoidCallback onOpenBackup;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final t = store.totals;
    final caption = t.netCents > 0 ? '可收回' : t.netCents < 0 ? '待偿还' : '已结清';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [pal.heroA, pal.heroB],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: pal.heroA.withValues(alpha: .22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          // 状态栏高度自己吃进来：这一屏没有 AppBar，标题就是这一块的开头。
          padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('欠款台账',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        )),
                  ),
                  IconButton(
                    tooltip: '备份与恢复',
                    onPressed: onOpenBackup,
                    icon: const Icon(Icons.folder_open, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text('净差',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  _GhostChip(text: caption),
                ],
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '¥${formatCentsCompact(t.netCents)}',
                  maxLines: 1,
                  style: theme.textTheme.displayMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: '别人欠我',
                        value: '¥${formatCentsCompact(t.receivableCents)}',
                        active: store.filter == HomeFilter.receivable,
                        onTap: () => onTapFilter(HomeFilter.receivable),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: '我欠别人',
                        value: '¥${formatCentsCompact(t.payableCents)}',
                        active: store.filter == HomeFilter.payable,
                        onTap: () => onTapFilter(HomeFilter.payable),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostChip extends StatelessWidget {
  const _GhostChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? .26 : .12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? .6 : .18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.store,
    required this.onChanged,
    required this.onToggleArchived,
  });
  final TextEditingController controller;
  final LedgerStore store;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: '搜姓名或手机号',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: pal.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: pal.hairline),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            tooltip: store.includeArchived ? '隐藏归档' : '显示归档',
            icon: store.includeArchived
                ? Icons.inventory_2
                : Icons.inventory_2_outlined,
            active: store.includeArchived,
            onPressed: () => onToggleArchived(!store.includeArchived),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: active ? scheme.primaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? Colors.transparent : pal.hairline),
          ),
          child: Icon(
            icon,
            size: 21,
            color: active ? scheme.onPrimaryContainer : pal.meta,
          ),
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.store});
  final LedgerStore store;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              store.archivedCount > 0
                  ? Icons.inventory_2_outlined
                  : Icons.phone_iphone_outlined,
              size: 14,
              color: pal.meta,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                store.archivedCount > 0
                    ? '已归档 ${store.archivedCount} 人（点上方归档按钮可见）'
                    : '数据只存在本机，建议每次记账后导出一份备份',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.store,
    required this.onAdd,
    required this.onOpen,
  });
  final LedgerStore store;
  final Future<void> Function() onAdd;
  final ValueChanged<Contact> onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final list = store.contacts;

    if (list.isEmpty) {
      final isFiltered =
          store.search.isNotEmpty || store.filter != HomeFilter.all;
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: EmptyHint(
              icon: isFiltered ? Icons.search_off : Icons.people_outline,
              message: isFiltered
                  ? '没有符合条件的记录'
                  : '还没有任何记录。\n先添加一个借款人，再在他的页面里记借款和还款。',
              actionLabel: isFiltered ? '清空筛选' : '添加第一个借款人',
              onAction: () async {
                if (isFiltered) {
                  store.setSearch('');
                  store.setFilter(HomeFilter.all);
                  await store.reload();
                } else {
                  await onAdd();
                }
              },
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = list[i];
        final tone = c.netCents == 0
            ? Tone.neutral
            : c.netCents > 0
                ? Tone.receivable
                : Tone.payable;
        // 刻意不用 ListTile：它给 trailing 的 maxHeight 恒为 56 逻辑像素
        // （maxIconHeightConstraint），既不随行高也不随字号变化，
        // 而这里的 trailing 是两行文字 —— 1.6 倍字号实测溢出 6px。
        // 自己拼 Row 之后，行高由最高的孩子决定，字号再大也只是行变高。
        return TintedCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          onTap: () => onOpen(c),
          child: Row(
            children: [
              PersonAvatar(name: c.name, muted: c.archived),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (c.archived) ...[
                          const SizedBox(width: 6),
                          const ToneBadge(text: '已归档'),
                        ],
                      ],
                    ),
                    MetaLine(
                      gap: 2,
                      parts: [
                        c.phone,
                        // 账单数/流水数不再挤在首页这一行：左列只有半张卡的宽度，
                        // 三个数字必然折行，折在「5 笔流水」中间比少一个数字更难读。
                        // 这两个数在人员页页首就有。
                        if ((c.phone ?? '').isEmpty) '${c.txCount} 笔流水',
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 这里必须是 Expanded 而不是 Flexible：
              // 两者默认 flex 都是 1，可用空间一律 50/50 分，但 Flexible 只给上限、
              // 不要求填满，于是内容宽度 < 半个槽位，crossAxisAlignment.end 对齐的是
              // 槽位起点而不是卡片右边缘 —— 金额胶囊就没贴右，且每行的右空隙还不一样。
              // Expanded 强制填满槽位，右边缘才真的等于卡片内容右边缘。
              // 也不能用非 flex 孩子：Row 给它的无限宽主约束会让里面的 FittedBox 永不缩放。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountTag(
                      text: _amountLabel(c),
                      tone: tone,
                      icon: c.netCents < 0
                          ? Icons.south_east
                          : c.netCents > 0
                              ? Icons.north_east
                              : Icons.check,
                    ),
                    if (c.lastActivity != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '最近 ${c.lastActivity!.substring(5)}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: pal.meta),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _amountLabel(Contact c) {
    if (c.receivableCents > 0 && c.payableCents == 0) {
      return '借出 ¥${formatCentsCompact(c.receivableCents)}';
    }
    if (c.payableCents > 0 && c.receivableCents == 0) {
      return '欠人 ¥${formatCentsCompact(c.payableCents)}';
    }
    if (c.netCents == 0) return '已结清';
    return c.netCents > 0
        ? '净借出 ¥${formatCentsCompact(c.netCents)}'
        : '净欠人 ¥${formatCentsCompact(-c.netCents)}';
  }
}
