/// 快照导入前的校验与归一化。
///
/// 设计要点：
/// 1. 一次收集**全部**问题而不是遇到第一个就停，让用户能一轮改完；
/// 2. 归一化时按白名单取列，未知键直接丢弃 —— 否则用户手改过的文件或旧版
///    本文件里的多余字段会让 INSERT 抛异常；
/// 3. 账单的三个派生金额列**不信任文件**，一律按文件里的流水重算，
///    与文件值不符只记 warning 不阻断导入。
library;

import 'models.dart';
import 'snapshot.dart';

/// 错误列表最多展示这么多条，超出只报总数，避免弹窗刷屏。
const int kMaxReportedErrors = 20;

class SnapshotData {
  const SnapshotData({
    required this.schemaVersion,
    required this.contacts,
    required this.bills,
    required this.transactions,
    required this.warnings,
  });

  final int schemaVersion;
  final List<Map<String, Object?>> contacts;
  final List<Map<String, Object?>> bills;
  final List<Map<String, Object?>> transactions;
  final List<String> warnings;

  int get receivableCents => _sumSignedBalance(bills, directionIn);
  int get payableCents => _sumSignedBalance(bills, directionOut);
  int get totalRows => contacts.length + bills.length + transactions.length;
  bool get isEmpty => totalRows == 0;
}

class SnapshotValidation {
  const SnapshotValidation._(this.data, this.errors, this.errorCount);

  final SnapshotData? data;
  final List<String> errors;
  final int errorCount;

  bool get ok => data != null && errors.isEmpty;

  String get tailHint =>
      errorCount > errors.length ? '……另有 ${errorCount - errors.length} 个问题未列出' : '';
}

const List<String> _contactCols = [
  'id', 'name', 'phone', 'note', 'archived', 'created_at'
];
const List<String> _billCols = [
  'id', 'contact_id', 'title', 'direction', 'note',
  'principal_cents', 'payment_cents', 'balance_cents', 'created_at', 'updated_at',
];
const List<String> _txCols = [
  'id', 'bill_id', 'kind', 'amount_cents', 'occurred_date',
  'channel', 'note', 'created_at', 'updated_at',
];

class _Reporter {
  final List<String> messages = [];
  int total = 0;

  void add(String message) {
    total++;
    if (messages.length < kMaxReportedErrors) messages.add(message);
  }
}

/// [decoded] 是 jsonDecode 的结果。任何形状都不假设，全部就地判空。
SnapshotValidation validateSnapshot(Object? decoded) {
  final rep = _Reporter();
  if (decoded is! Map) {
    rep.add('文件内容不是一个 JSON 对象，无法识别为记账快照');
    return SnapshotValidation._(null, rep.messages, rep.total);
  }

  final version = asExactInt(decoded['schemaVersion']);
  if (version == null) {
    rep.add('缺少 schemaVersion 字段，或它不是整数，无法判断快照格式版本');
  } else if (version < 1) {
    rep.add('schemaVersion=$version 不合法');
  } else if (version > kSchemaVersion) {
    rep.add('该快照由更新版本的 App 导出（schemaVersion=$version，'
        '当前仅支持到 $kSchemaVersion），请升级 App 后再导入');
  }

  final data = decoded['data'];
  if (data is! Map) {
    rep.add('缺少 data 字段或格式不对');
    return SnapshotValidation._(null, rep.messages, rep.total);
  }

  final contacts = _rows(data[kSnapshotKeyContacts], 'contacts', rep);
  final bills = _rows(data[kSnapshotKeyBills], 'bills', rep);
  final txs = _rows(data[kSnapshotKeyTransactions], 'transactions', rep);

  final warnings = <String>[];

  // 手工编辑的快照常省略 created_at / updated_at，而这两列在库里是 NOT NULL，
  // 统一回填快照自身的导出时间，避免导入时撞出一个看不懂的 SQL 约束错误。
  final fallbackTimestamp =
      asStringOrNull(decoded['exportedAt']) ?? DateTime.now().toIso8601String();

  final contactIds = _collectIds(contacts, '借款人', rep);
  final billIds = _collectIds(bills, '账单', rep);
  _checkUniqueIds(txs, '流水', rep);

  final normContacts = <Map<String, Object?>>[];
  for (var i = 0; i < contacts.length; i++) {
    final raw = contacts[i];
    final id = asExactInt(raw['id']);
    final tag = '借款人第 ${i + 1} 条${id == null ? '' : '（id=$id）'}';
    if (id == null || id <= 0) {
      rep.add('$tag：id 缺失或不是正整数');
    }
    if (asStringOrNull(raw['name']) == null) {
      rep.add('$tag：姓名不能为空');
    }
    normContacts.add(_pick(raw, _contactCols,
        fallbackTimestamp: fallbackTimestamp));
  }

  final normBills = <Map<String, Object?>>[];
  for (var i = 0; i < bills.length; i++) {
    final raw = bills[i];
    final id = asExactInt(raw['id']);
    final tag = '账单第 ${i + 1} 条${id == null ? '' : '（id=$id）'}';
    if (id == null || id <= 0) {
      rep.add('$tag：id 缺失或不是正整数');
    }
    final contactId = asExactInt(raw['contact_id']);
    if (contactId == null || !contactIds.contains(contactId)) {
      rep.add('$tag：contact_id=${raw['contact_id']} 在借款人中不存在');
    }
    if (asStringOrNull(raw['title']) == null) {
      rep.add('$tag：账单标题不能为空');
    }
    final direction = asStringOrNull(raw['direction']);
    if (!isDirection(direction)) {
      rep.add('$tag：direction=${raw['direction']} 非法，只能是 in 或 out');
    }
    normBills.add(_pick(raw, _billCols,
        fallbackTimestamp: fallbackTimestamp));
  }

  final normTxs = <Map<String, Object?>>[];
  for (var i = 0; i < txs.length; i++) {
    final raw = txs[i];
    final id = asExactInt(raw['id']);
    final tag = '流水第 ${i + 1} 条${id == null ? '' : '（id=$id）'}';
    if (id == null || id <= 0) {
      rep.add('$tag：id 缺失或不是正整数');
    }
    final billId = asExactInt(raw['bill_id']);
    if (billId == null || !billIds.contains(billId)) {
      rep.add('$tag：bill_id=${raw['bill_id']} 在账单中不存在');
    }
    final kind = asStringOrNull(raw['kind']);
    if (!isKind(kind)) {
      rep.add('$tag：kind=${raw['kind']} 非法，只能是 principal 或 payment');
    }
    final amount = asExactInt(raw['amount_cents']);
    if (amount == null || amount <= 0) {
      rep.add('$tag：amount_cents=${raw['amount_cents']} 必须是正整数（单位分）');
    }
    if (!isValidDateIso(asStringOrNull(raw['occurred_date']))) {
      rep.add('$tag：occurred_date=${raw['occurred_date']} 不是合法的 YYYY-MM-DD 日期');
    }
    normTxs.add(_pick(raw, _txCols, fallbackTimestamp: fallbackTimestamp));
  }

  _reconcileDerived(normBills, normTxs, warnings, rep);
  _checkSummary(decoded['summary'], normContacts, normBills, normTxs, warnings);

  if (normContacts.isEmpty && normBills.isEmpty && normTxs.isEmpty) {
    warnings.add('该快照不含任何记录，导入会清空当前全部数据');
  }

  if (rep.total > 0) {
    return SnapshotValidation._(null, rep.messages, rep.total);
  }
  return SnapshotValidation._(
    SnapshotData(
      schemaVersion: version ?? kSchemaVersion,
      contacts: normContacts,
      bills: normBills,
      transactions: normTxs,
      warnings: warnings,
    ),
    const [],
    0,
  );
}

/// 账单派生列以流水为准重算；文件里带的旧值只用于产生警告。
void _reconcileDerived(
  List<Map<String, Object?>> bills,
  List<Map<String, Object?>> txs,
  List<String> warnings,
  _Reporter rep,
) {
  final totals = billTotalsFromTxs(txs);

  var drifted = 0;
  for (final b in bills) {
    final id = asIntOrNull(b['id']);
    if (id == null) continue;
    final (:principal, :payment) = totals[id] ?? kZeroBillTotals;
    final correct = principal - payment;
    if ((asIntOrNull(b['principal_cents']) ?? 0) != principal ||
        (asIntOrNull(b['payment_cents']) ?? 0) != payment ||
        (asIntOrNull(b['balance_cents']) ?? 0) != correct) {
      drifted++;
      b['principal_cents'] = principal;
      b['payment_cents'] = payment;
      b['balance_cents'] = correct;
    }
  }
  if (drifted > 0) {
    warnings.add('有 $drifted 个账单的余额字段与流水不符，已按流水重算后导入');
  }
}

void _checkSummary(
  Object? summary,
  List<Map<String, Object?>> contacts,
  List<Map<String, Object?>> bills,
  List<Map<String, Object?>> txs,
  List<String> warnings,
) {
  if (summary is! Map) return;
  // bills 的派生列已被 _reconcileDerived 重算过，这里统计出的就是权威值。
  final actual = snapshotSummary(contacts, bills, txs);
  for (final key in actual.keys) {
    final declared = asIntOrNull(summary[key]);
    final computed = asIntOrNull(actual[key]);
    if (declared != null && computed != null && declared != computed) {
      warnings.add('快照声明的 $key=$declared 与按记录统计的 $computed 不一致，'
          '以记录统计为准');
    }
  }
}

int _sumSignedBalance(List<Map<String, Object?>> bills, String direction) {
  var sum = 0;
  for (final b in bills) {
    if (asStringOrNull(b['direction']) == direction) {
      sum += asIntOrNull(b['balance_cents']) ?? 0;
    }
  }
  return sum;
}

List<Map<String, Object?>> _rows(
  Object? raw,
  String label,
  _Reporter rep,
) {
  if (raw == null) {
    rep.add('data.$label 字段缺失');
    return const [];
  }
  if (raw is! List) {
    rep.add('data.$label 不是数组');
    return const [];
  }
  final out = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(item.cast<String, Object?>());
    } else {
      rep.add('data.$label 中存在不是对象的元素');
    }
  }
  return out;
}

Set<int> _collectIds(List<Map<String, Object?>> rows, String label, _Reporter rep) {
  final ids = <int>{};
  for (var i = 0; i < rows.length; i++) {
    final id = asExactInt(rows[i]['id']);
    if (id == null) continue;
    if (!ids.add(id)) {
      rep.add('$label 中 id=$id 重复出现（第 ${i + 1} 条）');
    }
  }
  return ids;
}

void _checkUniqueIds(List<Map<String, Object?>> rows, String label, _Reporter rep) {
  final ids = <int>{};
  for (var i = 0; i < rows.length; i++) {
    final id = asExactInt(rows[i]['id']);
    if (id == null) continue;
    if (!ids.add(id)) {
      rep.add('$label 中 id=$id 重复出现（第 ${i + 1} 条）');
    }
  }
}

Map<String, Object?> _pick(
  Map<String, Object?> raw,
  List<String> cols, {
  required String fallbackTimestamp,
}) {
  const timestampCols = {'created_at', 'updated_at'};

  final out = <String, Object?>{};
  for (final col in cols) {
    final value = raw[col];
    if (value == null) {
      if (col.endsWith('_cents') || col == 'archived') {
        out[col] = 0;
      } else if (timestampCols.contains(col)) {
        // 库表里时间戳是 NOT NULL，手工编辑的快照常不写它，回填导出时间。
        out[col] = fallbackTimestamp;
      } else {
        out[col] = null;
      }
      continue;
    }
    if (col.endsWith('_cents') || col == 'id') {
      // 校验阶段已拒绝非整数，这里再截断一次就是第二个吞钱的口径。
      // 万一真漏过去，落成 0 会被库约束挡下来 —— 导入失败远好于静默改钱。
      out[col] = asExactInt(value) ?? 0;
    } else if (col == 'archived') {
      out[col] = asIntOrNull(value) ?? 0;
    } else {
      out[col] = value;
    }
  }
  return out;
}
