import 'package:flutter/material.dart';

import '../theme.dart';

/// 全站共用的几个可视块。放在一起的唯一理由：让五屏的圆角、间距、
/// 语义色由同一处决定，改一次五屏一起变。

/// 有色块卡片。替代上一版清一色「透明底 + 描边」的 Card.outlined。
class TintedCard extends StatelessWidget {
  const TintedCard({
    super.key,
    required this.child,
    this.tone,
    this.tint,
    this.ink,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = kRadius,
    this.border = true,
  });

  final Widget child;
  final Tone? tone;

  /// 不写 tint 时用该 tone 的 soft 色；tone 为空则是白卡。
  final Color? tint;
  final Color? ink;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = tone;
    final bg = tint ?? (t == null ? scheme.surfaceContainerLowest : pal.soft(t));
    final line = t == null ? pal.hairline : Colors.transparent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? BorderSide(color: line) : BorderSide.none,
    );
    final card = Material(
      type: MaterialType.card,
      color: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// 金额胶囊：一行里最该被看见的东西。
/// [text] 是完整一句（如「借出 ¥1.23万」），刻意作为**一个** Text 渲染，
/// 这样它整体进 FittedBox 缩放，而不是拆成两段后各自截断。
class AmountTag extends StatelessWidget {
  const AmountTag({
    super.key,
    required this.text,
    this.tone = Tone.neutral,
    this.icon,
    this.dense = false,
  });

  final String text;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: pal.soft(tone),
        borderRadius: BorderRadius.circular(9),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: pal.onSoft(tone)),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              maxLines: 1,
              style: (dense ? theme.textTheme.labelMedium : theme.textTheme.titleSmall)
                  ?.copyWith(
                color: pal.onSoft(tone),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态/方向小徽标。
class ToneBadge extends StatelessWidget {
  const ToneBadge({
    super.key,
    required this.text,
    this.tone = Tone.neutral,
    this.dot = false,
  });

  final String text;
  final Tone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pal.soft(tone),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: pal.ink(tone),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: pal.onSoft(tone)),
          ),
        ],
      ),
    );
  }
}

/// 分区标题：一小段色条 + 标题 + 可选右侧动作。
/// 上一版分区只有文字，滚动时找不到边界。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.accent,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.onTap,
    this.expanded,
  });

  final String title;
  final Color? accent;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// 非空时整行可点，配合 [expanded] 把这一节变成可折叠区。
  final VoidCallback? onTap;

  /// null = 不画箭头（不可折叠）；true / false = 当前是否展开。
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exp = expanded;
    final row = Row(
      children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: accent ?? theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        ?trailing,
        if (exp != null)
          AnimatedRotation(
            // 收起时箭头朝下（点开），展开时朝上（点收）。
            turns: exp ? .5 : 0,
            duration: const Duration(milliseconds: 160),
            child:
                Icon(Icons.expand_more, size: 22, color: theme.colorScheme.outline),
          ),
      ],
    );
    final padded = Padding(padding: padding, child: row);
    if (onTap == null) return padded;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: padded,
    );
  }
}

/// 次要信息行：把一串字段用「·」拼成**一个** Text。
/// 用 Row 拼的话，非 flex 孩子拿到的是无限宽主约束，长金额永远不会换行
/// （上一版就是这么溢出 6.6px 的）；Text.rich 会正常折行。
class MetaLine extends StatelessWidget {
  const MetaLine({
    super.key,
    required this.parts,
    this.style,
    this.gap = 0,
    this.maxLines,
    this.overflow,
  });

  final List<String?> parts;
  final TextStyle? style;
  final double gap;

  /// 说明性文字是次要信息，允许在窄屏/大字号下折成一行加省略号；
  /// 金额不走这里，它必须整块缩放而不是被截断。
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = LedgerPalette.of(context);
    final kept = parts.where((p) => p != null && p.isNotEmpty).toList();
    if (kept.isEmpty) return const SizedBox.shrink();
    final base = style ?? theme.textTheme.bodySmall;
    final dot = TextSpan(
      text: ' · ',
      style: base?.copyWith(color: pal.meta.withValues(alpha: .55)),
    );
    final spans = <InlineSpan>[];
    for (var i = 0; i < kept.length; i++) {
      if (i > 0) spans.add(dot);
      spans.add(TextSpan(text: kept[i]));
    }
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: Text.rich(TextSpan(children: spans, style: base),
          maxLines: maxLines, overflow: overflow ?? TextOverflow.clip),
    );
  }
}

/// 人名头像：同一名字恒同一色相，扫列表时比读字快。
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.muted = false,
  });

  final String name;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final hue = pal.hueOf(name);
    final fg = muted ? pal.meta : hue;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fg.withValues(alpha: muted ? .10 : .13),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      alignment: Alignment.center,
      child: Text(
        name.characters.take(1).toString(),
        style: theme.textTheme.titleMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 圆形图标底座：给「一行只有字」的列表一个颜色锚点。
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.tone = Tone.info,
    this.size = 38,
  });

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pal.soft(tone),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, size: size * .5, color: pal.onSoft(tone)),
    );
  }
}

/// 一笔流水的行。人员页时间线与账单页流水表共用同一行式，
/// 免得两处字号、配色、对齐各长一套。
class TxRow extends StatelessWidget {
  const TxRow({
    super.key,
    required this.title,
    required this.metaParts,
    required this.amount,
    this.tone = Tone.neutral,
    this.icon,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final List<String?> metaParts;
  final String amount;
  final Tone tone;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: pal.soft(tone),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: pal.onSoft(tone)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                // 大字号下这一行必然放不下；让它折成一行加省略号，
                // 否则左侧变两行、右侧金额就跟着错位，看着像撞在一起。
                MetaLine(
                  gap: 1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  parts: metaParts,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 必须是 Expanded 而不是 Flexible：两者默认 flex 都是 1、都只分到一半空间，
          // 但 Flexible 不要求填满，金额就停在槽位起点、没贴到行的右边缘。
          // 也不能退回非 flex 孩子 —— Row 给非 flex 孩子无限宽主约束，
          // 裸 Text 里的 FittedBox 永远不会缩放，长金额直接顶穿行宽。
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amount,
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: pal.ink(tone),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: row,
    );
  }
}

/// 二选一的选择块。
///
/// 不用 SegmentedButton：ButtonStyle 拿不到「当前是哪个 segment」，
/// 没法让「应收」选中时是绿、「应付」选中时是橙。而选择结果的颜色
/// 必须和全 App 的语义色一致，用户才不用记「哪个是哪个」。
class ToneChoice extends StatelessWidget {
  const ToneChoice({
    super.key,
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.icon,
    this.caption,
    this.enabled = true,
  });

  final String label;
  final Tone tone;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? caption;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? pal.soft(tone) : Colors.white,
          borderRadius: BorderRadius.circular(kRadiusSm),
          border: Border.all(
            color: selected ? pal.ink(tone) : pal.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: selected ? pal.ink(tone) : pal.meta),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected ? pal.onSoft(tone) : theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: pal.ink(tone)),
          ],
        ),
      ),
    );
  }
}
