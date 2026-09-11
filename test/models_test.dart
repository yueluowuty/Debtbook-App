import 'package:debtbook/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidDateIso', () {
    test('接受正常日期', () {
      expect(isValidDateIso('2026-09-05'), isTrue);
      expect(isValidDateIso('2026-01-01'), isTrue);
      expect(isValidDateIso('2026-12-31'), isTrue);
    });

    test('区分大小月与闰年', () {
      expect(isValidDateIso('2026-04-31'), isFalse, reason: '4 月只有 30 天');
      expect(isValidDateIso('2026-06-31'), isFalse);
      expect(isValidDateIso('2026-02-29'), isFalse, reason: '2026 非闰年');
      expect(isValidDateIso('2028-02-29'), isTrue, reason: '2028 是闰年');
      expect(isValidDateIso('2100-02-29'), isFalse, reason: '百年不闰');
      expect(isValidDateIso('2000-02-29'), isTrue, reason: '四百年再闰');
      expect(isValidDateIso('2026-03-31'), isTrue, reason: '3 月 31 日必须合法');
    });

    test('拒绝格式非法', () {
      expect(isValidDateIso(null), isFalse);
      expect(isValidDateIso(''), isFalse);
      expect(isValidDateIso('2026-9-5'), isFalse);
      expect(isValidDateIso('2026/09/05'), isFalse);
      expect(isValidDateIso('2026-00-10'), isFalse);
      expect(isValidDateIso('2026-13-01'), isFalse);
      expect(isValidDateIso('2026-09-00'), isFalse);
      expect(isValidDateIso('2026-09-32'), isFalse);
    });
  });

  group('口径标签', () {
    test('同一 kind 在两种方向账单上含义不同', () {
      expect(txKindLabel(directionIn, kindPrincipal), '借出');
      expect(txKindLabel(directionIn, kindPayment), '还款');
      expect(txKindLabel(directionOut, kindPrincipal), '借入');
      expect(txKindLabel(directionOut, kindPayment), '还款');
    });

    test('剩余的正负读法', () {
      expect(billStatusLabel(directionIn, 0), '已结清');
      expect(billStatusLabel(directionIn, 100), '未结清');
      expect(billStatusLabel(directionIn, -100), '已多收');
      expect(billStatusLabel(directionOut, -100), '已多付');
    });

    test('流水对剩余的影响符号与方向无关', () {
      expect(txSign(kindPrincipal), '+');
      expect(txSign(kindPayment), '-');
    });
  });

  group('行转模型', () {
    test('聚合列缺失时回落为 0 而不是抛异常', () {
      final contact = Contact.fromRow(contactRowMinimal);
      expect(contact.receivableCents, 0);
      expect(contact.billCount, 0);
      expect(contact.lastActivity, isNull);
      expect(contact.archived, isFalse);
    });

    test('archived 存 0/1，bool 脏数据也能容错', () {
      expect(Contact.fromRow({...contactRowMinimal, 'archived': 1}).archived, isTrue);
      expect(
          Contact.fromRow({...contactRowMinimal, 'archived': true}).archived, isTrue);
    });

    test('净差额 = 应收 - 应付，双向挂账时为净值', () {
      final c = Contact.fromRow({
        ...contactRowMinimal,
        'receivable_cents': 500000,
        'payable_cents': 200000,
      });
      expect(c.netCents, 300000);
    });

    test('asIntOrNull 覆盖 sqlite/JSON 各种数字形状', () {
      expect(asIntOrNull(12), 12);
      expect(asIntOrNull('12'), 12);
      expect(asIntOrNull(12.0), 12);
      expect(asIntOrNull(true), 1);
      expect(asIntOrNull(null), isNull);
      expect(asIntOrNull('abc'), isNull);
    });
  });
}

final Map<String, Object?> contactRowMinimal = {
  'id': 1,
  'name': '张三',
  'phone': null,
  'note': null,
  'archived': 0,
  'created_at': '2026-01-01T09:00:00.000',
};
