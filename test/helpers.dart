/// 测试夹具：直接构造「数据库行」形状的 Map，与导出/导入的实际数据形态一致。
library;

import 'package:debtbook/domain/models.dart';
import 'package:debtbook/domain/snapshot.dart';

Map<String, Object?> contactRow(
  int id, {
  String name = '张三',
  String? phone,
  String? note,
  int archived = 0,
  String createdAt = '2026-01-01T09:00:00.000',
}) =>
    <String, Object?>{
      'id': id,
      'name': name,
      'phone': phone,
      'note': note,
      'archived': archived,
      'created_at': createdAt,
    };

Map<String, Object?> billRow(
  int id,
  int contactId, {
  String title = '借款',
  String direction = directionIn,
  String? note,
  int principalCents = 0,
  int paymentCents = 0,
  int balanceCents = 0,
  String createdAt = '2026-01-01T09:00:00.000',
  String updatedAt = '2026-01-01T09:00:00.000',
}) =>
    <String, Object?>{
      'id': id,
      'contact_id': contactId,
      'title': title,
      'direction': direction,
      'note': note,
      'principal_cents': principalCents,
      'payment_cents': paymentCents,
      'balance_cents': balanceCents,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };

Map<String, Object?> txRow(
  int id,
  int billId, {
  String kind = kindPrincipal,
  int amountCents = 100000,
  String occurredDate = '2026-01-01',
  String? channel,
  String? note,
  String createdAt = '2026-01-01T09:00:00.000',
  String updatedAt = '2026-01-01T09:00:00.000',
}) =>
    <String, Object?>{
      'id': id,
      'bill_id': billId,
      'kind': kind,
      'amount_cents': amountCents,
      'occurred_date': occurredDate,
      'channel': channel,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };

/// 一致的快照：账单派生列已经和流水对得上。
Map<String, Object?> consistentSnapshot({
  List<Map<String, Object?>>? contacts,
  List<Map<String, Object?>>? bills,
  List<Map<String, Object?>>? transactions,
  int schemaVersion = kSchemaVersionForTest,
  Map<String, Object?>? summary,
}) {
  final c = contacts ?? [contactRow(1)];
  final b = bills ?? [billRow(10, 1, principalCents: 0, balanceCents: 0)];
  final t = transactions ?? const <Map<String, Object?>>[];
  final rebalanced = _applyDerived(b, t);
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'appVersion': '1.0.0',
    'exportedAt': '2026-09-05T22:00:00.000',
    'summary': summary ??
        <String, Object?>{
          'contacts': c.length,
          'bills': b.length,
          'transactions': t.length,
          'receivableCents': _sumDirection(rebalanced, directionIn),
          'payableCents': _sumDirection(rebalanced, directionOut),
        },
    'data': <String, Object?>{
      'contacts': c,
      'bills': rebalanced,
      'transactions': t,
    },
  };
}

const int kSchemaVersionForTest = 1;

List<Map<String, Object?>> _applyDerived(
  List<Map<String, Object?>> bills,
  List<Map<String, Object?>> txs,
) =>
    withRecomputedBills(bills, txs);

int _sumDirection(List<Map<String, Object?>> bills, String direction) {
  var sum = 0;
  for (final b in bills) {
    if (b['direction'] == direction) sum += b['balance_cents'] as int;
  }
  return sum;
}
