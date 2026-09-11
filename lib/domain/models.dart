/// 领域常量、显示口径与实体模型。
/// 本文件不得 import 任何 flutter 包，保证可脱离设备单测。
library;

const String directionIn = 'in'; // 别人欠我（应收）
const String directionOut = 'out'; // 我欠别人（应付）

const String kindPrincipal = 'principal'; // 借款 / 再借款：增加欠款
const String kindPayment = 'payment'; // 还款：减少欠款

const List<String> kDirections = [directionIn, directionOut];
const List<String> kKinds = [kindPrincipal, kindPayment];

bool isDirection(Object? v) => v == directionIn || v == directionOut;
bool isKind(Object? v) => v == kindPrincipal || v == kindPayment;

/// 完整口径说明，用于表单与统计卡标题。
String directionLabel(String direction) =>
    direction == directionOut ? '我欠别人' : '别人欠我';

/// 列表分段与表格里的短标签。
String directionShort(String direction) =>
    direction == directionOut ? '应付' : '应收';

/// 同一类流水在不同方向的账单上含义不同：应收账单上的 principal 是「借出」，
/// 应付账单上的 principal 是「借入」。
String txKindLabel(String direction, String kind) {
  if (kind == kindPayment) return '还款';
  return direction == directionOut ? '借入' : '借出';
}

/// 流水对「剩余」的影响符号。principal 增债、payment 减债，与方向无关。
String txSign(String kind) => kind == kindPayment ? '-' : '+';

/// 结清状态完全由重算出的剩余推导，库里不存状态列。
String billStatusLabel(String direction, int balanceCents) {
  if (balanceCents == 0) return '已结清';
  if (balanceCents > 0) return '未结清';
  return direction == directionOut ? '已多付' : '已多收';
}

/// 读**数据库行**用。SQLite 这些列都是 INTEGER，这里的 num 分支只为兼容
/// 表达式查询可能返回的 double；因此它允许截断。
int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return int.tryParse(v);
  if (v is num) return v.toInt();
  return null;
}

/// 读**不可信输入**（用户手改过的 JSON 快照）用，绝不截断。
///
/// 与 [asIntOrNull] 的区别就是钱：12.5 元会被前者的 toInt() 变成 12 分，
/// 金额、id、外键任何一个经过它都会静默变成「钱没了」或「流水改了父级」，
/// 所以这三类字段必须走这个函数，非整数一律判为非法。
int? asExactInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v % 1 == 0 ? v.toInt() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

bool isValidDateIso(String? s) {
  if (s == null || !_datePattern.hasMatch(s)) return false;
  final parts = s.split('-').map(int.parse).toList();
  final y = parts[0], m = parts[1], d = parts[2];
  if (m < 1 || m > 12 || d < 1) return false;
  // m+1 月的第 0 天即 m 月的最后一天，这样才含闰年与大月判断。
  return d <= DateTime(y, m + 1, 0).day;
}

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 界面展示用的中文短日期；非法输入原样返回，不让界面崩。
String formatDateCn(String iso) {
  if (!isValidDateIso(iso)) return iso;
  final parts = iso.split('-');
  return '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日';
}

class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.note,
    required this.archived,
    required this.createdAt,
    this.receivableCents = 0,
    this.payableCents = 0,
    this.billCount = 0,
    this.txCount = 0,
    this.lastActivity,
  });

  factory Contact.fromRow(Map<String, Object?> row) => Contact(
        id: asIntOrNull(row['id']) ?? 0,
        name: asStringOrNull(row['name']) ?? '',
        phone: asStringOrNull(row['phone']),
        note: asStringOrNull(row['note']),
        archived: (asIntOrNull(row['archived']) ?? 0) != 0,
        createdAt: asStringOrNull(row['created_at']) ?? '',
        receivableCents: asIntOrNull(row['receivable_cents']) ?? 0,
        payableCents: asIntOrNull(row['payable_cents']) ?? 0,
        billCount: asIntOrNull(row['bill_count']) ?? 0,
        txCount: asIntOrNull(row['tx_count']) ?? 0,
        lastActivity: asStringOrNull(row['last_activity']),
      );

  final int id;
  final String name;
  final String? phone;
  final String? note;
  final bool archived;
  final String createdAt;

  /// 以下聚合值仅在人员列表查询中带出，按 id 单查时为 0。
  final int receivableCents;
  final int payableCents;
  final int billCount;
  final int txCount;
  final String? lastActivity;

  /// 净差额：正数表示对方净欠我，负数表示我净欠对方。
  int get netCents => receivableCents - payableCents;
  bool get hasDebt => receivableCents != 0 || payableCents != 0;
}

class Bill {
  const Bill({
    required this.id,
    required this.contactId,
    required this.title,
    required this.note,
    required this.direction,
    required this.principalCents,
    required this.paymentCents,
    required this.balanceCents,
    required this.createdAt,
    required this.updatedAt,
    this.txCount = 0,
    this.firstDate,
    this.lastDate,
  });

  factory Bill.fromRow(Map<String, Object?> row) => Bill(
        id: asIntOrNull(row['id']) ?? 0,
        contactId: asIntOrNull(row['contact_id']) ?? 0,
        title: asStringOrNull(row['title']) ?? '',
        note: asStringOrNull(row['note']),
        direction: asStringOrNull(row['direction']) ?? directionIn,
        principalCents: asIntOrNull(row['principal_cents']) ?? 0,
        paymentCents: asIntOrNull(row['payment_cents']) ?? 0,
        balanceCents: asIntOrNull(row['balance_cents']) ?? 0,
        createdAt: asStringOrNull(row['created_at']) ?? '',
        updatedAt: asStringOrNull(row['updated_at']) ?? '',
        txCount: asIntOrNull(row['tx_count']) ?? 0,
        firstDate: asStringOrNull(row['first_date']),
        lastDate: asStringOrNull(row['last_date']),
      );

  final int id;
  final int contactId;
  final String title;
  final String? note;
  final String direction;
  final int principalCents;
  final int paymentCents;
  final int balanceCents;
  final String createdAt;
  final String updatedAt;
  final int txCount;
  final String? firstDate;
  final String? lastDate;

  bool get isSettled => balanceCents == 0;
  bool get isOverpaid => balanceCents < 0;
  bool get hasTransactions => txCount > 0;
  String get statusLabel => billStatusLabel(direction, balanceCents);
}

class Tx {
  const Tx({
    required this.id,
    required this.billId,
    required this.kind,
    required this.amountCents,
    required this.occurredDate,
    required this.channel,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tx.fromRow(Map<String, Object?> row) => Tx(
        id: asIntOrNull(row['id']) ?? 0,
        billId: asIntOrNull(row['bill_id']) ?? 0,
        kind: asStringOrNull(row['kind']) ?? kindPrincipal,
        amountCents: asIntOrNull(row['amount_cents']) ?? 0,
        occurredDate: asStringOrNull(row['occurred_date']) ?? '',
        channel: asStringOrNull(row['channel']),
        note: asStringOrNull(row['note']),
        createdAt: asStringOrNull(row['created_at']) ?? '',
        updatedAt: asStringOrNull(row['updated_at']) ?? '',
      );

  final int id;
  final int billId;
  final String kind;
  final int amountCents;
  final String occurredDate;
  final String? channel;
  final String? note;
  final String createdAt;
  final String updatedAt;

  bool get isPayment => kind == kindPayment;
}

/// 记一笔时常用的收付渠道。存库为自由文本，不做枚举校验，
/// 这里只是输入快捷项。
const List<String> kChannelPresets = ['微信', '支付宝', '银行卡', '现金'];
