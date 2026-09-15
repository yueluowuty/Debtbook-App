/// 金额一律以「分」为单位的 64 位整数表示，界面输入「元」。
/// 全项目不存在任何 double 参与金额计算。
library;

/// 单笔金额上限（元）。超出视为录入错误，避免手滑多打零。
const int kMaxYuanPerTx = 100000000;

final RegExp _yuanPattern = RegExp(r'^\d*(?:\.\d{1,2})?$');

/// 把用户输入的「元」解析成「分」。
/// 返回 null 表示非法输入：空、负数、三位以上小数、非数字、零、超过上限。
int? parseYuanToCents(String input) {
  final s = input.trim().replaceAll(RegExp(r'[,，\s]'), '');
  if (s.isEmpty || s == '.') return null;
  if (s.startsWith('-') || s.startsWith('+')) return null;
  if (!_yuanPattern.hasMatch(s)) return null;

  final dot = s.indexOf('.');
  final intText = dot < 0 ? s : s.substring(0, dot);
  final fracText = dot < 0 ? '' : s.substring(dot + 1);

  final yuan = int.tryParse(intText.isEmpty ? '0' : intText);
  if (yuan == null) return null;
  final cents = int.parse(fracText.isEmpty ? '0' : fracText.padRight(2, '0'));

  final total = yuan * 100 + cents;
  if (total <= 0 || total > kMaxYuanPerTx * 100) return null;
  return total;
}

/// 千分位格式化，如 123450 -> '1,234.50'，-123450 -> '-1,234.50'。
String formatCents(int cents) =>
    '${_sign(cents)}${_group('${_abs(cents ~/ 100)}')}.${_frac(cents)}';

/// 无千分位的精确金额，给需要原样解析的场景（表格、剪贴板）用。
String formatCentsPlain(int cents) =>
    '${_sign(cents)}${_abs(cents ~/ 100)}.${_frac(cents)}';

const int _centsPerWan = 10000 * 100; // 1 万元 = 1,000,000 分
const int _centsPerYi = 100000000 * 100; // 1 亿元

/// 空间有限的大号金额用：满 1 万改说「1.5万」，满 1 亿说「1.23亿」。
/// 精确值仍在流水列表行与「数据」页汇总里，这里只是避免长数字撑坏布局。
String formatCentsCompact(int cents) {
  final a = _abs(cents);
  if (a < _centsPerWan) return formatCents(cents);

  final bool isYi = a >= _centsPerYi;
  final int unitCents = isYi ? _centsPerYi : _centsPerWan;
  // 先四舍五入到两位小数（q = 数值 × 100），全程整数。
  final int q = (a * 100 + unitCents ~/ 2) ~/ unitCents;
  final int whole = q ~/ 100;
  final int frac = q % 100;
  final String number = frac == 0
      ? _group('$whole')
      : frac % 10 == 0
          ? '${_group('$whole')}.${frac ~/ 10}'
          : '${_group('$whole')}.${frac < 10 ? '0$frac' : '$frac'}';
  return '${_sign(cents)}$number${isYi ? '亿' : '万'}';
}

int _abs(int v) => v < 0 ? -v : v;

String _sign(int cents) => cents < 0 ? '-' : '';

String _frac(int cents) {
  // 必须先取绝对值再取模：Dart 的 % 对正除数恒返回非负数，
  // -5 % 100 会得到 95 而不是 -5。
  final f = _abs(cents) % 100;
  return f < 10 ? '0$f' : '$f';
}

/// 对非负数字字符串插入千分位分隔符。
String _group(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}
