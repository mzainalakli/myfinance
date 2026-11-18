import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/category_style.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/format.dart';
import '../data/summary.dart';

/// Batasi lebar konten di layar lebar/tablet.
class ContentWidth extends StatelessWidget {
  final Widget child;
  const ContentWidth({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Tk.maxContentWidth), child: child),
      );
}

class PageTitle extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const PageTitle(this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s8, Tk.s4),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ...actions,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tk.s32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: cs.outline),
          const SizedBox(height: Tk.s12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Tk.s4),
            Text(message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}

/// Kerangka muat sederhana (tanpa animasi berlebihan).
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 6});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .6);
    Widget box(double w, double h) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)));
    return Column(children: [
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tk.s16, vertical: Tk.s12),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: Tk.s12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box(120, 14), const SizedBox(height: 6), box(70, 10),
            ])),
            box(64, 14),
          ]),
        ),
    ]);
  }
}

/// Nominal dengan topeng saat [hidden]. Fade pendek; pembaca layar tidak membacakan angka saat tersembunyi.
class MoneyText extends StatelessWidget {
  final Money money;
  final NumberStyle style;
  final bool hidden;
  final String prefix;
  final TextStyle? textStyle;
  const MoneyText(this.money,
      {super.key, required this.style, required this.hidden, this.prefix = '', this.textStyle});

  @override
  Widget build(BuildContext context) {
    final text = hidden ? kMask : '$prefix${money.format(style: style)}';
    Widget t = Text(text, key: ValueKey(hidden), style: textStyle, maxLines: 1);
    if (hidden) t = Semantics(label: S.amountHidden, excludeSemantics: true, child: t);
    return AnimatedSwitcher(duration: const Duration(milliseconds: 150), child: t);
  }
}

/// Ikon mata (>= 48dp) untuk menampilkan/menyembunyikan saldo.
class HideToggleButton extends ConsumerWidget {
  const HideToggleButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenProvider);
    return IconButton(
      tooltip: hidden ? S.showBalance : S.hideBalance,
      constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
      onPressed: () => ref.read(settingsProvider.notifier).toggleBalanceHidden(),
      icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  final String icon;
  final int color;
  final double size;
  const CategoryAvatar({super.key, required this.icon, required this.color, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: .16), shape: BoxShape.circle),
      child: Icon(iconFor(icon), color: c, size: size * .55),
    );
  }
}

class TxTile extends ConsumerWidget {
  final TxRow row;
  final bool showDate;
  final VoidCallback? onTap;
  const TxTile({super.key, required this.row, this.showDate = false, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(numberStyleProvider);
    final hidden = ref.watch(historyHiddenProvider);
    final cs = Theme.of(context).colorScheme;
    final color = row.isIncome ? context.incomeColor : context.expenseColor;
    final dt = fromEpochMs(row.tx.occurredAt);
    final sub = [
      if (showDate) shortDayLabel(dt) else timeLabel(dt),
      if (row.tx.note.isNotEmpty) row.tx.note,
    ].join(' · ');
    return ListTile(
      minTileHeight: 64,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Tk.s16),
      leading: CategoryAvatar(icon: row.category.icon, color: row.category.color),
      title: Text(row.category.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: MoneyText(
        row.money,
        style: style,
        hidden: hidden,
        prefix: row.isIncome ? '+' : '-',
        textStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Kartu rekap per mata uang (tidak pernah menjumlah mata uang berbeda).
class SummaryCard extends ConsumerWidget {
  final List<CurrencyTotal> totals;
  final String? title;

  /// Tampilkan ikon mata di judul kartu dan izinkan ketuk angka untuk menyembunyikan (Beranda).
  final bool showEye;
  const SummaryCard({super.key, required this.totals, this.title, this.showEye = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(numberStyleProvider);
    final hidden = ref.watch(hiddenProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget cell(String label, Money value, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(value,
                  style: style,
                  hidden: hidden,
                  textStyle: tt.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tk.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Row(children: [
              Expanded(child: Text(title!, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
              if (showEye) const HideToggleButton(),
            ]),
          if (totals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s4),
              child: Text('—', style: tt.headlineSmall),
            ),
          for (var i = 0; i < totals.length; i++) ...[
            if (i > 0) const Divider(height: Tk.s24),
            if (title != null || i > 0) const SizedBox(height: Tk.s4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: showEye ? () => ref.read(settingsProvider.notifier).toggleBalanceHidden() : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(totals[i].net,
                    style: style,
                    hidden: hidden,
                    textStyle: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: Tk.s8),
            Row(children: [
              cell(S.income, totals[i].income, context.incomeColor),
              cell(S.expense, totals[i].expense, context.expenseColor),
            ]),
          ],
        ]),
      ),
    );
  }
}
