/// 离线 JSON 快照的生成。只处理「数据库行」这一种表示，
/// 因此导出内容与 SQLite 里的真实状态一一对应，不引入第二套口径。
library;

import 'dart:convert';

import 'models.dart';

/// 快照格式版本。只升不降：文件版本高于 App 支持版本时拒绝导入。
const int kSchemaVersion = 1;

const String kSnapshotKeyContacts = 'contacts';
const String kSnapshotKeyBills = 'bills';
const String kSnapshotKeyTransactions = 'transactions';

/// 从三张表的原始行构造快照对象。
Map<String, Object?> buildSnapshot({
  required List<Map<String, Object?>> contacts,
  required List<Map<String, Object?>> bills,
  required List<Map<String, Object?>> transactions,
  required String appVersion,
  required String exportedAt,
}) {
  final derivedBills = withRecomputedBills(bills, transactions);
  return <String, Object?>{
    'schemaVersion': kSchemaVersion,
    'appVersion': appVersion,
    'exportedAt': exportedAt,
    'summary': snapshotSummary(contacts, derivedBills, transactions),
    'data': <String, Object?>{
      kSnapshotKeyContacts: contacts,
      kSnapshotKeyBills: derivedBills,
      kSnapshotKeyTransactions: transactions,
    },
  };
}

/// 单个账单应有的本金与还款合计。
typedef BillTotals = ({int principal, int payment});

const BillTotals kZeroBillTotals = (principal: 0, payment: 0);

/// 按流水算出每个账单的本金与还款合计。
///
/// 这是纯 Dart 侧的唯一口径，导出与导入校验都走它；运行时的权威实现是
/// repo.recomputeBills 里的 SQL SUM，两者必须始终一致（test/repo_test.dart
/// 里有对拍用例）。
Map<int, BillTotals> billTotalsFromTxs(List<Map<String, Object?>> txs) {
  final totals = <int, BillTotals>{};
  for (final t in txs) {
    final billId = asIntOrNull(t['bill_id']);
    final amount = asIntOrNull(t['amount_cents']);
    if (billId == null || amount == null) continue;
    final kind = t['kind'];
    if (kind != kindPrincipal && kind != kindPayment) continue;
    final current = totals[billId] ?? kZeroBillTotals;
    totals[billId] = kind == kindPrincipal
        ? (principal: current.principal + amount, payment: current.payment)
        : (principal: current.principal, payment: current.payment + amount);
  }
  return totals;
}

/// 把账单的三个派生金额列按流水重写一遍。
///
/// 导出前做这件事，是为了让「导出的文件」本身自洽：否则只要库里有一行漂移，
/// 错误就会跟着备份永久固化，再导入时还会被当成用户手改而告警。
List<Map<String, Object?>> withRecomputedBills(
  List<Map<String, Object?>> bills,
  List<Map<String, Object?>> txs,
) {
  final totals = billTotalsFromTxs(txs);
  return [
    for (final b in bills)
      () {
        final id = asIntOrNull(b['id']);
        final t = id == null ? kZeroBillTotals : (totals[id] ?? kZeroBillTotals);
        // 展开后覆盖同名键不会改变键的顺序，导出列序仍与库表一致。
        return <String, Object?>{
          ...b,
          'principal_cents': t.principal,
          'payment_cents': t.payment,
          'balance_cents': t.principal - t.payment,
        };
      }(),
  ];
}

/// 人读的缩进 JSON。导出文件允许用户自己打开查看甚至手改，
/// 所以不做紧凑编码。
String encodeSnapshot(Map<String, Object?> snapshot) =>
    const JsonEncoder.withIndent('  ').convert(snapshot);

Map<String, Object?> snapshotSummary(
  List<Map<String, Object?>> contacts,
  List<Map<String, Object?>> bills,
  List<Map<String, Object?>> transactions,
) {
  return <String, Object?>{
    'contacts': contacts.length,
    'bills': bills.length,
    'transactions': transactions.length,
    'receivableCents': _sumBalance(bills, directionIn),
    'payableCents': _sumBalance(bills, directionOut),
  };
}

int _sumBalance(List<Map<String, Object?>> bills, String direction) {
  var sum = 0;
  for (final b in bills) {
    if (asStringOrNull(b['direction']) == direction) {
      sum += asIntOrNull(b['balance_cents']) ?? 0;
    }
  }
  return sum;
}
