/// 全局状态：一个 [LedgerStore] 持有 repo 与首页所需的聚合数据，
/// 靠 ChangeNotifier 驱动刷新。
///
/// 之所以不引 riverpod：它的一次大版本破坏性改动，在没有设备可调试的情况下
/// 换来的收益不抵风险。这里只需要「写完数据让列表重查一遍」这一件事。
library;

import 'package:flutter/widgets.dart';

import '../db/repo.dart';
import '../domain/models.dart';

/// 首页人员列表的筛选口径。
enum HomeFilter { all, receivable, payable }

String? homeFilterDirection(HomeFilter filter) => switch (filter) {
      HomeFilter.all => null,
      HomeFilter.receivable => directionIn,
      HomeFilter.payable => directionOut,
    };

class LedgerStore extends ChangeNotifier {
  LedgerStore(this.repo, this.docsDir);

  final LedgerRepo repo;

  /// 应用私有目录，导出快照与自动备份都落在这里。
  final String docsDir;

  LedgerTotals totals = const LedgerTotals(receivableCents: 0, payableCents: 0);
  List<Contact> contacts = const [];
  int archivedCount = 0;

  HomeFilter filter = HomeFilter.all;
  String search = '';
  bool includeArchived = false;

  bool loading = true;

  Future<void> reload() async {
    // 并发查，任一路失败就保留上一次的数据而不是清空界面。
    final results = await Future.wait([
      repo.totals(),
      repo.listContacts(
        search: search,
        direction: homeFilterDirection(filter),
        includeArchived: includeArchived,
      ),
      repo.contactCount(includeArchived: true),
      repo.contactCount(),
    ]);
    totals = results[0] as LedgerTotals;
    contacts = results[1] as List<Contact>;
    // 归档数与搜索/方向筛选无关，必须由两条 COUNT 相减得到；
    // 用「总数 − 可见数」会把被筛掉的正常人也算成归档。
    archivedCount = (results[2] as int) - (results[3] as int);
    loading = false;
    notifyListeners();
  }

  /// 数据被写过，广播一次让还挂着的页面自己去重查。
  void invalidate() {
    notifyListeners();
  }

  void setFilter(HomeFilter value) {
    if (filter == value) return;
    filter = value;
    loading = true;
    notifyListeners();
  }

  void setSearch(String value) {
    final v = value.trim();
    if (search == v) return;
    search = v;
    loading = true;
    notifyListeners();
  }

  void setIncludeArchived(bool value) {
    if (includeArchived == value) return;
    includeArchived = value;
    loading = true;
    notifyListeners();
  }
}

/// 把 store 挂到 widget 树上，子树用 [LedgerStore.of] 取。
class StoreScope extends InheritedNotifier<LedgerStore> {
  const StoreScope({
    super.key,
    required LedgerStore store,
    required super.child,
  }) : super(notifier: store);

  static LedgerStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, '往上找不到 StoreScope');
    return scope!.notifier!;
  }

  /// 只读取不订阅，给 setState 回调里的写操作用。
  static LedgerStore read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, '往上找不到 StoreScope');
    return scope!.notifier!;
  }
}
