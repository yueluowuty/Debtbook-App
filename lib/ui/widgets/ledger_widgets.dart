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
      // 水波纹/高亮全部抹平：点「全部流水」时标题行后面会糊出一块灰底，
      // 看着像多了一层背景。折叠状态本来就有那个旋转箭头在反馈，够了。
      // 仍然用 InkWell 而不是 GestureDetector：它保留焦点与无障碍语义。
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
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

/// 人名胶囊：高度恒为 [size]，宽度随全名自适应。
/// 同一名字恒同一色相，扫列表时比读字快。
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.muted = false,
    this.textStyle,
    this.maxChars,
    this.maxWidth,
  });

  final String name;
  final double size;
  final bool muted;

  /// null = titleMedium + w700。字号刻意不跟 [size] 走：两个调用点要的字号
  /// （列表 15 / 页面标题 17）和两个 size（44 / 34）不成比例，
  /// 没有任何一个系数能同时给对，所以交给调用点。
  final TextStyle? textStyle;

  /// 最多放几个字。非空时字号**固定不缩**，超出的走省略号 —— 列表里所有人
  /// 的名字于是同一个字号，左边缘是一条整齐的边线。
  /// 为空时宽度按 [maxWidth] 自适应，尽量把全名放下（详情页要的是全名）。
  final int? maxChars;

  /// 仅在 [maxChars] 为空时生效；null = 屏宽的 38% 与 168 取小。
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);
    final theme = Theme.of(context);
    final hue = pal.hueOf(name);
    final fg = muted ? pal.meta : hue;
    final style = (textStyle ?? theme.textTheme.titleMedium)
        ?.copyWith(color: fg, fontWeight: FontWeight.w700);
    final pad = size * .30;
    // 按**缩放后**的字号算宽度：这样 maxChars: 5 在 1.6 倍系统字号下仍是
    // 5 个字，而不是按比例缩成 3 个字加省略号。
    final glyph =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) + 1;
    double cap = maxChars != null
        ? maxChars! * glyph + pad * 2
        // 168 那道天花板是给「按屏宽算」的默认值兜底的，调用方显式给的
        // maxWidth 不能再被它夹掉 —— 详情页要放全名，传了 220 却只拿到 168。
        : (maxWidth ??
            (MediaQuery.sizeOf(context).width * .38).clamp(0.0, 168.0));
    if (cap < size) cap = size; // 别让上限把最小宽度切掉

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fg.withValues(alpha: muted ? .10 : .13),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      // 不用带 alignment 的 Container —— 那种盒会把自己撑到 maxWidth，
      // 于是每个名字都变成同一个最宽胶囊，「自适应」直接失效。
      // ConstrainedBox 必须自己封顶：非 flex 孩子从 Row 拿到的是无限宽主约束。
      child: SizedBox(
        height: size,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: size, maxWidth: cap),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            // Column 而不是 Center：Center 会把自己撑到 maxWidth，每个胶囊都变成
            // 同一个最宽块，「随名字自适应」直接失效。Column 的宽度取最宽的孩子
            // （就是文字本身），主轴又把 SizedBox 的定高填满、把文字摆到中线上 ——
            // 之前缺的就是这一步，字一直贴在胶囊上沿。
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name.isEmpty ? ' ' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ],
            ),
          ),
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
/// 固定两行：第一行「标题 + 右上角金额」，第二行整宽的「时间 · 渠道 · 备注」。
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              // 必须是 Expanded 而不是 Flexible：两者默认 flex 都是 1、都只分到一半空间，
              // 但 Flexible 不要求填满，金额就停在槽位起点、没贴到行的右边缘。
              // 也不能退回非 flex 孩子 —— Row 给非 flex 孩子无限宽主约束，
              // 裸 Text 里的 FittedBox 永远不会缩放，长金额直接顶穿行宽。
              // 金额要落在第一行的右上角，靠的就是这两条。
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
          // 第二行是 Column 的直接孩子，不再被左边那半个宽度卡着，
          // 于是整行宽度都归它，时间 · 渠道 · 备注 放得下的比原来多得多。
          // 放不下时仍折成一行加省略号，免得这列变两行把行高撑乱。
          MetaLine(
            gap: 2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            parts: metaParts,
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
