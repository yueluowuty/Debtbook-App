import 'package:debtbook/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseYuanToCents 接受', () {
    test('常见输入', () {
      expect(parseYuanToCents('12.34'), 1234);
      expect(parseYuanToCents('1000'), 100000);
      expect(parseYuanToCents('0.01'), 1);
      expect(parseYuanToCents('88.8'), 8880, reason: '一位小数按角补零');
      expect(parseYuanToCents('.5'), 50, reason: '允许省略整数部分');
    });

    test('容忍空白与千分位', () {
      expect(parseYuanToCents('  6,800.50 '), 680050);
      expect(parseYuanToCents('1，234'), 123400, reason: '中文逗号也去掉');
    });

    test('上限本身合法', () {
      expect(parseYuanToCents('$kMaxYuanPerTx'), kMaxYuanPerTx * 100);
    });
  });

  group('parseYuanToCents 拒绝', () {
    test('空与纯符号', () {
      expect(parseYuanToCents(''), isNull);
      expect(parseYuanToCents('   '), isNull);
      expect(parseYuanToCents('.'), isNull);
      expect(parseYuanToCents('12.'), isNull, reason: '小数点后必须有数字');
    });

    test('零额与负数', () {
      expect(parseYuanToCents('0'), isNull);
      expect(parseYuanToCents('0.00'), isNull);
      expect(parseYuanToCents('-5'), isNull, reason: '正负由 kind/direction 表达');
      expect(parseYuanToCents('+5'), isNull);
    });

    test('精度与非法字符', () {
      expect(parseYuanToCents('1.234'), isNull, reason: '不接受厘');
      expect(parseYuanToCents('abc'), isNull);
      expect(parseYuanToCents('1e3'), isNull);
      expect(parseYuanToCents('12.3.4'), isNull);
      expect(parseYuanToCents('10元'), isNull);
    });

    test('超上限', () {
      expect(parseYuanToCents('${kMaxYuanPerTx + 1}'), isNull);
    });
  });

  group('formatCents', () {
    test('正数带千分位', () {
      expect(formatCents(0), '0.00');
      expect(formatCents(1), '0.01');
      expect(formatCents(5), '0.05');
      expect(formatCents(1234), '12.34');
      expect(formatCents(100000), '1,000.00');
      expect(formatCents(12345678901), '123,456,789.01');
    });

    test('负数（超付场景）符号在前且分位不进位错', () {
      expect(formatCents(-1), '-0.01');
      expect(formatCents(-5), '-0.05');
      expect(formatCents(-99), '-0.99');
      expect(formatCents(-100), '-1.00');
      expect(formatCents(-123450), '-1,234.50');
    });
  });

  group('formatCentsPlain', () {
    test('给 Excel 用：无千分位', () {
      expect(formatCentsPlain(12345678901), '123456789.01');
      expect(formatCentsPlain(0), '0.00');
      expect(formatCentsPlain(-123450), '-1234.50');
    });
  });

  group('formatCentsCompact', () {
    test('不足 1 万元与 formatCents 完全一致', () {
      expect(formatCentsCompact(0), '0.00');
      expect(formatCentsCompact(1234), '12.34');
      expect(formatCentsCompact(999999), '9,999.99'); // 9,999.99 元，差 1 分才到 1 万
    });

    test('满 1 万转「万」，多余的零要去掉', () {
      expect(formatCentsCompact(1000000), '1万'); // 整万不带小数点
      expect(formatCentsCompact(1500000), '1.5万');
      expect(formatCentsCompact(12345678), '12.35万'); // 12.345678 万 → 两位小数
      expect(formatCentsCompact(100000000), '100万');
      expect(formatCentsCompact(1234567890), '1,234.57万'); // 千分位仍在
    });

    test('满 1 亿转「亿」', () {
      expect(formatCentsCompact(10000000000), '1亿');
      expect(formatCentsCompact(12345678901), '1.23亿');
    });

    test('四舍五入只发生在最后一步，不进位错', () {
      expect(formatCentsCompact(1000001), '1万'); // 1.000001 万
      expect(formatCentsCompact(999999999), '1,000万'); // 999.999999 万
    });

    test('负数（超付）符号在前', () {
      expect(formatCentsCompact(-1500000), '-1.5万');
      expect(formatCentsCompact(-10000000000), '-1亿');
    });
  });

  test('解析后格式化与输入一致（元两位小数不丢精度）', () {
    expect(formatCentsPlain(parseYuanToCents('0.01')!), '0.01');
    expect(formatCentsPlain(parseYuanToCents('1.10')!), '1.10');
    expect(formatCentsPlain(parseYuanToCents('5.5')!), '5.50', reason: '一位小数补零');
    expect(formatCentsPlain(parseYuanToCents('99.99')!), '99.99');
    expect(formatCentsPlain(parseYuanToCents('1234.56')!), '1234.56');
    expect(formatCentsPlain(parseYuanToCents('99999999.99')!), '99999999.99');
  });
}
