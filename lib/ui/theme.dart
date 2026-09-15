/// 全站视觉系统。
///
/// 上一版只有 `ColorScheme.fromSeed(绿)`，后果是 surface 也被染成薄荷绿、
/// 所有卡片都是「透明底 + 一圈灰线」，标题、正文、金额、次要信息挤在同一
/// 个灰度上。用户原话：「色彩太素了，文字一多起来就看起来有点乱」。
///
/// 这一版的取舍：底色回到中性，颜色**只**留给三件事——
/// 应收（绿）、应付（橙）、已结清（灰），危险操作另用红。
/// 层级靠底色块与字重拉开，不靠描边。
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// 语义色板。用 ThemeExtension 挂上去，业务代码只认语义名不认色值。
class LedgerPalette extends ThemeExtension<LedgerPalette> {
  const LedgerPalette({
    required this.receivable,
    required this.receivableSoft,
    required this.receivableInk,
    required this.payable,
    required this.payableSoft,
    required this.payableInk,
    required this.neutral,
    required this.neutralSoft,
    required this.neutralInk,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.meta,
    required this.hairline,
    required this.heroA,
    required this.heroB,
    required this.avatarHues,
  });

  final Color receivable;
  final Color receivableSoft;
  final Color receivableInk;
  final Color payable;
  final Color payableSoft;
  final Color payableInk;
  final Color neutral;
  final Color neutralSoft;
  final Color neutralInk;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  /// 次要文字统一色：一行里出现三个层级时，只有它是「可忽略」的。
  final Color meta;
  final Color hairline;
  final Color heroA;
  final Color heroB;

  /// 人名头像色相：同一个名字在任何页面永远是同一个颜色，
  /// 列表扫一眼就能认人，比读文字快。
  final List<Color> avatarHues;

  static LedgerPalette of(BuildContext context) =>
      Theme.of(context).extension<LedgerPalette>()!;

  Color hueOf(String name) {
    // 不用 String.hashCode：Dart 不保证它跨进程稳定，同一份数据两次打开
    // 头像会换色。按 rune 求和是确定的。
    var sum = 0;
    for (final r in name.runes) {
      sum = (sum + r) % 997;
    }
    return avatarHues[sum % avatarHues.length];
  }

  Tone toneOfDirection(String direction) =>
      direction == directionOut ? Tone.payable : Tone.receivable;

  Tone toneOfBalance(int cents, {String direction = directionIn}) {
    if (cents == 0) return Tone.neutral;
    return cents > 0
        ? toneOfDirection(direction)
        : direction == directionOut
            ? Tone.receivable
            : Tone.payable;
  }

  Color ink(Tone tone) => switch (tone) {
        Tone.receivable => receivable,
        Tone.payable => payable,
        Tone.neutral => neutral,
        Tone.danger => danger,
        Tone.info => info,
      };

  Color soft(Tone tone) => switch (tone) {
        Tone.receivable => receivableSoft,
        Tone.payable => payableSoft,
        Tone.neutral => neutralSoft,
        Tone.danger => dangerSoft,
        Tone.info => infoSoft,
      };

  Color onSoft(Tone tone) => switch (tone) {
        Tone.receivable => receivableInk,
        Tone.payable => payableInk,
        Tone.neutral => neutralInk,
        Tone.danger => danger,
        Tone.info => info,
      };

  @override
  LedgerPalette copyWith({
    Color? receivable,
    Color? receivableSoft,
    Color? receivableInk,
    Color? payable,
    Color? payableSoft,
    Color? payableInk,
    Color? neutral,
    Color? neutralSoft,
    Color? neutralInk,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? meta,
    Color? hairline,
    Color? heroA,
    Color? heroB,
    List<Color>? avatarHues,
  }) {
    return LedgerPalette(
      receivable: receivable ?? this.receivable,
      receivableSoft: receivableSoft ?? this.receivableSoft,
      receivableInk: receivableInk ?? this.receivableInk,
      payable: payable ?? this.payable,
      payableSoft: payableSoft ?? this.payableSoft,
      payableInk: payableInk ?? this.payableInk,
      neutral: neutral ?? this.neutral,
      neutralSoft: neutralSoft ?? this.neutralSoft,
      neutralInk: neutralInk ?? this.neutralInk,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      meta: meta ?? this.meta,
      hairline: hairline ?? this.hairline,
      heroA: heroA ?? this.heroA,
      heroB: heroB ?? this.heroB,
      avatarHues: avatarHues ?? this.avatarHues,
    );
  }

  @override
  LedgerPalette lerp(covariant LedgerPalette? other, double t) {
    if (other == null) return this;
    return LedgerPalette(
      receivable: Color.lerp(receivable, other.receivable, t)!,
      receivableSoft: Color.lerp(receivableSoft, other.receivableSoft, t)!,
      receivableInk: Color.lerp(receivableInk, other.receivableInk, t)!,
      payable: Color.lerp(payable, other.payable, t)!,
      payableSoft: Color.lerp(payableSoft, other.payableSoft, t)!,
      payableInk: Color.lerp(payableInk, other.payableInk, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralSoft: Color.lerp(neutralSoft, other.neutralSoft, t)!,
      neutralInk: Color.lerp(neutralInk, other.neutralInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      meta: Color.lerp(meta, other.meta, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      heroA: Color.lerp(heroA, other.heroA, t)!,
      heroB: Color.lerp(heroB, other.heroB, t)!,
      avatarHues: t < 0.5 ? avatarHues : other.avatarHues,
    );
  }
}

/// 界面里一切「带颜色的东西」都归到这五个语义上，不再有第六种色。
enum Tone { receivable, payable, neutral, danger, info }

const double kRadius = 16;
const double kRadiusSm = 11;

const List<Color> _avatarHues = [
  Color(0xFF0B7A52),
  Color(0xFF0E7490),
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFBE185D),
  Color(0xFFB45309),
  Color(0xFF4D7C0F),
  Color(0xFF0F766E),
];

/// 账单色条的身份色。刻意不复用 [_avatarHues]：那八个里有 `0B7A52`（就是应收绿）、
/// `B45309`（就是应付橙）和另外两个绿/青，两张应收账单的色条于是撞成同一种绿，
/// 「按账单区分」直接失效，还和语义色混在一起读。
/// 这四个离五个语义色都远。
const List<Color> billBarHues = [
  Color(0xFF0E7490), // 青
  Color(0xFF2563EB), // 蓝
  Color(0xFF7C3AED), // 紫
  Color(0xFFBE185D), // 玫红
];

/// 账单标题 → 首选色位。算法与 [LedgerPalette.hueOf] 同理：不用
/// String.hashCode（Dart 不保证跨进程稳定）。
/// 只保证「同一标题永远同一格」，**不保证同一个人的两张账单不撞色** ——
/// 撞色由调用方（人员页）避让，见 `billBarHues` 的用法的注释。
int billBarHueSeed(String title) {
  var sum = 0;
  for (final r in title.runes) {
    sum = (sum + r) % 997;
  }
  return sum % billBarHues.length;
}

/// 归档行的底色。刻意比 `neutralSoft`（EAEFF4）再深一档：页面底本身就是
/// 245,247,250 这一带的浅灰，只暗 20 个级差的卡片在列表里分不出「这是另一拨」，
/// 而分得出来正是归档这一组唯一的目的。
const Color archivedTint = Color(0xFFDCE4EC);

/// 中性色单独提出来：组件主题里要在 const 表达式里用到它们，
/// 而 `_lightPalette.meta` 这种属性访问在常量表达式里不合法。
const Color _meta = Color(0xFF6B7885);
const Color _hairline = Color(0xFFE4E9EF);

const _lightPalette = LedgerPalette(
  receivable: Color(0xFF0B7A52),
  receivableSoft: Color(0xFFDDF3E7),
  receivableInk: Color(0xFF07422C),
  payable: Color(0xFFB45309),
  payableSoft: Color(0xFFFCEBD8),
  payableInk: Color(0xFF6A3005),
  neutral: Color(0xFF5B6B7A),
  neutralSoft: Color(0xFFEAEFF4),
  neutralInk: Color(0xFF3A4653),
  danger: Color(0xFFB3261E),
  dangerSoft: Color(0xFFFBDFDC),
  info: Color(0xFF2F5FBF),
  infoSoft: Color(0xFFE3EAFB),
  meta: _meta,
  hairline: _hairline,
  heroA: Color(0xFF0A5F44),
  heroB: Color(0xFF12946A),
  avatarHues: _avatarHues,
);

ThemeData buildDebtBookTheme() {
  // fromSeed 而不是手写 ColorScheme：常量构造器的必填参数在不同 Flutter
  // 版本间会变（background/onBackground 被删、scrim 被加），copyWith 不受影响。
  final scheme = ColorScheme.fromSeed(
    seedColor: _seedPrimary,
    brightness: Brightness.light,
  ).copyWith(
    primary: _seedPrimary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD3F0E2),
    onPrimaryContainer: const Color(0xFF053A26),
    secondary: const Color(0xFF4A6357),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFD7E7DF),
    onSecondaryContainer: const Color(0xFF0B2018),
    // tertiary 历史上就是「应付」，这里直接把它定义成橙色，
    // 老代码里所有 colorScheme.tertiary 自动获得正确语义。
    tertiary: _lightPalette.payable,
    onTertiary: Colors.white,
    tertiaryContainer: _lightPalette.payableSoft,
    onTertiaryContainer: _lightPalette.payableInk,
    error: _lightPalette.danger,
    onError: Colors.white,
    errorContainer: _lightPalette.dangerSoft,
    onErrorContainer: const Color(0xFF410E0B),
    // 底色回到中性冷灰，不再让种子色把整屏染成薄荷绿。
    surface: const Color(0xFFF5F7FA),
    onSurface: const Color(0xFF131A22),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: const Color(0xFFF1F4F8),
    surfaceContainerHigh: const Color(0xFFE9EEF4),
    surfaceContainerHighest: const Color(0xFFE2E8EF),
    onSurfaceVariant: const Color(0xFF4F5B67),
    outline: _lightPalette.meta,
    outlineVariant: _lightPalette.hairline,
    // 关掉 M3 的彩色 elevation 叠加，否则卡片会一层层泛绿。
    surfaceTint: Colors.transparent,
  );

  final textTheme = _textTheme(scheme.onSurface, _lightPalette.meta);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: textTheme,
    primarySwatch: null,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    iconTheme: const IconThemeData(size: 22, color: _meta),
    extensions: const [_lightPalette],
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black12,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: _lightPalette.hairline),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.headlineSmall,
      iconTheme: IconThemeData(size: 22, color: scheme.onSurface),
      systemOverlayStyle: null,
    ),
    dividerTheme: const DividerThemeData(
      thickness: 1,
      color: _hairline,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: _lightPalette.meta,
      textColor: scheme.onSurface,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: _lightPalette.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: Colors.white,
      elevation: 2,
      extendedTextStyle: textTheme.labelLarge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: textTheme.bodyMedium?.copyWith(color: _lightPalette.meta),
      labelStyle: textTheme.bodyMedium?.copyWith(color: _lightPalette.meta),
      floatingLabelStyle: textTheme.bodySmall?.copyWith(color: scheme.primary),
      prefixIconColor: _lightPalette.meta,
      suffixIconColor: _lightPalette.meta,
      border: _fieldBorder(scheme.outlineVariant),
      enabledBorder: _fieldBorder(Colors.transparent),
      focusedBorder: _fieldBorder(scheme.primary, width: 1.6),
      errorBorder: _fieldBorder(scheme.error),
      focusedErrorBorder: _fieldBorder(scheme.error, width: 1.6),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _lightPalette.neutralSoft,
      selectedColor: scheme.primaryContainer,
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: textTheme.labelMedium
          ?.copyWith(color: _lightPalette.neutralInk),
      secondaryLabelStyle: textTheme.labelMedium
          ?.copyWith(color: scheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        side: WidgetStatePropertyAll(BorderSide(color: _hairline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusSm),
          ),
        ),
        // ButtonStyle 没有 selectedXxx 参数，选中态只能靠 WidgetState 解析。
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : scheme.surfaceContainer,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : _meta,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black54,
      showDragHandle: true,
      dragHandleColor: _lightPalette.hairline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium
          ?.copyWith(color: scheme.onInverseSurface),
      width: null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _seedPrimary,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

const Color _seedPrimary = Color(0xFF0B7A52);

OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusSm),
      borderSide: BorderSide(color: color, width: width),
    );

/// 字号表刻意拉开：上一版 title/body/label 只差 1~2px，
/// 结果是「一行里五个东西一样重」，字一多就找不到落点。
TextTheme _textTheme(Color ink, Color meta) {
  TextStyle s(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.35,
    Color? color,
    double spacing = 0,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color ?? ink,
      // 等宽数字：金额右对齐时位数能对齐，这是「不乱」里最容易被忽略的一条。
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  return TextTheme(
    displayLarge: s(34, weight: FontWeight.w700, height: 1.12),
    displayMedium: s(29, weight: FontWeight.w700, height: 1.14),
    displaySmall: s(24, weight: FontWeight.w700, height: 1.16),
    headlineLarge: s(22, weight: FontWeight.w700),
    headlineMedium: s(20, weight: FontWeight.w700),
    headlineSmall: s(18.5, weight: FontWeight.w700),
    titleLarge: s(17, weight: FontWeight.w700),
    titleMedium: s(15, weight: FontWeight.w600),
    titleSmall: s(13.5, weight: FontWeight.w600),
    bodyLarge: s(15, height: 1.5),
    bodyMedium: s(13.5, height: 1.5),
    bodySmall: s(12, height: 1.4, color: meta),
    labelLarge: s(14, weight: FontWeight.w600),
    labelMedium: s(12, weight: FontWeight.w600, color: meta, spacing: .1),
    labelSmall: s(11, weight: FontWeight.w600, color: meta, spacing: .2),
  );
}
