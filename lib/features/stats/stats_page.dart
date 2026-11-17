import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/money/currencies.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../transactions/data/summary.dart';
import '../transactions/ui/common.dart';
import '../transactions/ui/filter_bar.dart';
import '../transactions/ui/pickers.dart';
import 'stats_calculator.dart';

class StatsSelection {
  final String? currency;
  final TxType type;
  const StatsSelection({this.currency, this.type = TxType.expense});
}

class StatsSelectionNotifier extends Notifier<StatsSelection> {
  @override
  StatsSelection build() => const StatsSelection();
  void setCurrency(String c) => state = StatsSelection(currency: c, type: state.type);
  void setType(TxType t) => state = StatsSelection(currency: state.currency, type: t);
}

final statsSelectionProvider =
    NotifierProvider<StatsSelectionNotifier, StatsSelection>(StatsSelectionNotifier.new);

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final rows = ref.watch(rowsProvider(filter)).value;
    final sel = ref.watch(statsSelectionProvider);
    final codes = rows == null ? const <String>[] : currenciesIn(rows);
    final effective = sel.currency != null && codes.contains(sel.currency)
        ? sel.currency
        : (codes.isEmpty ? null : codes.first);

    Widget body;
    if (rows == null) {
      body = const SkeletonList();
    } else if (rows.isEmpty || effective == null) {
      body = const EmptyState(icon: Icons.insert_chart_outlined, title: S.noData, message: S.noRecordsFilter);
    } else {
      body = _Charts(rows: rows, currency: currencyByCode(effective), type: sel.type);
    }

    return SafeArea(
      bottom: false,
      child: Column(children: [
        const ContentWidth(child: PageTitle(S.stats)),
        Expanded(child: ContentWidth(child: body)),
        FilterBar(trailing: [
          if (effective != null)
            Padding(
              padding: const EdgeInsets.only(right: Tk.s4),
              child: ActionChip(
                label: Text(effective),
                onPressed: codes.length < 2
                    ? null
                    : () async {
                        final c = await showCurrencyPicker(context, selected: effective, pinned: codes);
                        if (c != null) ref.read(statsSelectionProvider.notifier).setCurrency(c.code);
                      },
              ),
            ),
        ]),
        ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s12, 0, Tk.s12, Tk.s8),
            child: SegmentedButton<TxType>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text(S.expense)),
                ButtonSegment(value: TxType.income, label: Text(S.income)),
              ],
              selected: {sel.type},
              onSelectionChanged: (v) => ref.read(statsSelectionProvider.notifier).setType(v.first),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Nilai untuk grafik saja (tampilan); angka tampil tetap dari [Money].
double _chartValue(int minor, Currency c) {
  var f = 1.0;
  for (var i = 0; i < c.decimals; i++) {
    f *= 10;
  }
  return minor / f;
}

class _Charts extends ConsumerWidget {
  final List<TxRow> rows;
  final Currency currency;
  final TxType type;
  const _Charts({required this.rows, required this.currency, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(numberStyleProvider);
    final slices = categoryBreakdown(rows, type, currency.code);
    final bars = monthlyBars(rows, currency.code);
    final trend = balanceTrend(rows, currency.code);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final total = slices.fold<int>(0, (a, s) => a + s.minor);

    Widget titled(String t, Widget child, {String? sub}) => Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Tk.s16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (sub != null) Text(sub, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: Tk.s12),
                child,
              ]),
            ),
          ),
        );

    Widget noData = SizedBox(
        height: 80, child: Center(child: Text(S.noData, style: TextStyle(color: cs.onSurfaceVariant))));

    final donut = slices.isEmpty
        ? noData
        : Column(children: [
            SizedBox(
              height: 200,
              child: Stack(alignment: Alignment.center, children: [
                PieChart(PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 64,
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(
                        value: s.minor.toDouble(),
                        color: Color(s.category.color),
                        radius: 28,
                        showTitle: false,
                      ),
                  ],
                )),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(S.total, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  SizedBox(
                    width: 110,
                    child: FittedBox(
                      child: Text(Money(total, currency).format(style: style),
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: Tk.s8),
            for (final s in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(s.category.color), shape: BoxShape.circle)),
                  const SizedBox(width: Tk.s8),
                  Expanded(child: Text(s.category.name, overflow: TextOverflow.ellipsis)),
                  Text('${(s.minor * 100 / total).toStringAsFixed(0)}%', style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(width: Tk.s12),
                  Text(Money(s.minor, currency).format(style: style), style: const TextStyle(fontWeight: FontWeight.w500)),
                ]),
              ),
          ]);

    final maxBar = bars.fold<double>(0, (m, b) {
      final a = _chartValue(b.incomeMinor, currency), e = _chartValue(b.expenseMinor, currency);
      return [m, a, e].reduce((x, y) => x > y ? x : y);
    });
    final barChart = bars.isEmpty
        ? noData
        : Column(children: [
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                maxY: maxBar == 0 ? 1 : maxBar * 1.15,
                gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: .5)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, m) => v == m.max
                          ? const SizedBox.shrink()
                          : Text(compactNumber(v), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(shortMonthLabel(bars[i].month), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(x: i, barsSpace: 3, barRods: [
                      BarChartRodData(toY: _chartValue(bars[i].incomeMinor, currency), color: context.incomeColor, width: 8, borderRadius: BorderRadius.circular(3)),
                      BarChartRodData(toY: _chartValue(bars[i].expenseMinor, currency), color: context.expenseColor, width: 8, borderRadius: BorderRadius.circular(3)),
                    ]),
                ],
              )),
            ),
            const SizedBox(height: Tk.s8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Legend(color: context.incomeColor, label: S.income),
              const SizedBox(width: Tk.s16),
              _Legend(color: context.expenseColor, label: S.expense),
            ]),
          ]);

    Widget line;
    if (trend.length < 2) {
      line = noData;
    } else {
      final ys = [for (final p in trend) _chartValue(p.cumulativeMinor, currency)];
      final minY = ys.reduce((a, b) => a < b ? a : b), maxY = ys.reduce((a, b) => a > b ? a : b);
      final pad = (maxY - minY).abs() * .15 + 1;
      line = SizedBox(
        height: 200,
        child: LineChart(LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant, strokeWidth: .5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, m) => (v == m.max || v == m.min)
                    ? const SizedBox.shrink()
                    : Text(compactNumber(v), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (trend.length / 3).clamp(1, 9999).toDouble(),
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= trend.length || v != i.toDouble()) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(shortDayLabel(trend[i].day), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${shortDayLabel(trend[s.spotIndex].day)}\n${Money(trend[s.spotIndex].cumulativeMinor, currency).format(style: style)}',
                    TextStyle(color: cs.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
              isCurved: true,
              curveSmoothness: .2,
              preventCurveOverShooting: true,
              color: cs.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: .10)),
            ),
          ],
        )),
      );
    }

    return ListView(padding: const EdgeInsets.only(bottom: Tk.s16), children: [
      titled(S.expenseByCategory, donut, sub: type == TxType.expense ? S.expense : S.income),
      titled(S.monthly, barChart),
      titled(S.trend, line, sub: S.trendNote),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);
}
