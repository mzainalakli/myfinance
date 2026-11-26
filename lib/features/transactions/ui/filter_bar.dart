import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/format.dart';
import '../data/tx_filter.dart';
import 'common.dart';

/// Chip periode cepat + tombol filter lanjutan, di zona jempol (bawah).
class FilterBar extends ConsumerWidget {
  final List<Widget> trailing;
  const FilterBar({super.key, this.trailing = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filterProvider);
    final n = ref.read(filterProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final custom = f.customRange;
    return Material(
      color: cs.surface,
      child: ContentWidth(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s12, Tk.s8, Tk.s4, Tk.s4),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (custom != null)
                    Padding(
                      padding: const EdgeInsets.only(right: Tk.s8),
                      child: InputChip(
                        selected: true,
                        showCheckmark: false,
                        label: Text('${shortDayLabel(custom.start)} – ${shortDayLabel(custom.end)}'),
                        onDeleted: () => n.setPeriod(QuickPeriod.all),
                        onPressed: () => showFilterSheet(context),
                      ),
                    ),
                  for (final p in QuickPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Tk.s8),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: custom == null && f.period == p,
                        onSelected: (_) => n.setPeriod(p),
                      ),
                    ),
                ]),
              ),
            ),
            ...trailing,
            IconButton.filledTonal(
              tooltip: S.filter,
              constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
              onPressed: () => showFilterSheet(context),
              icon: Badge(
                isLabelVisible: f.advancedCount > 0,
                label: Text('${f.advancedCount}'),
                child: const Icon(Icons.tune),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

Future<void> showFilterSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _FilterSheet(),
    );

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TxFilter f = ref.read(filterProvider);
  late final q = TextEditingController(text: f.query);

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: f.customRange == null
          ? null
          : DateTimeRange(start: f.customRange!.start, end: f.customRange!.end),
    );
    if (r != null) setState(() => f = f.copyWith(customRange: DayRange(r.start, r.end)));
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final used = ref.watch(usedCurrenciesProvider).value ?? const <String>[];
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final tt = Theme.of(context).textTheme;
    Widget section(String t, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: Tk.s16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: tt.labelLarge),
            const SizedBox(height: Tk.s8),
            child,
          ]),
        );

    final visibleCats = cats.where((c) => !c.isArchived || f.categoryIds.contains(c.id));
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s8),
              shrinkWrap: true,
              children: [
                section(
                  S.type,
                  SegmentedButton<TxType?>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: null, label: Text(S.all)),
                      ButtonSegment(value: TxType.expense, label: Text(S.expense)),
                      ButtonSegment(value: TxType.income, label: Text(S.income)),
                    ],
                    selected: {f.type},
                    onSelectionChanged: (s) => setState(() => f = f.copyWith(type: s.first)),
                  ),
                ),
                section(
                  S.dateRange,
                  Wrap(spacing: Tk.s8, children: [
                    ActionChip(
                      avatar: const Icon(Icons.date_range, size: 18),
                      label: Text(f.customRange == null
                          ? S.pickRange
                          : '${shortDayLabel(f.customRange!.start)} – ${shortDayLabel(f.customRange!.end)}'),
                      onPressed: _pickRange,
                    ),
                    if (f.customRange != null)
                      ActionChip(
                        label: const Text(S.reset),
                        onPressed: () => setState(() => f = f.copyWith(customRange: null)),
                      ),
                  ]),
                ),
                section(
                  S.category,
                  Wrap(spacing: Tk.s8, runSpacing: Tk.s8, children: [
                    for (final c in visibleCats)
                      FilterChip(
                        label: Text('${c.name}${c.type == TxType.income ? ' (${S.income})' : ''}'),
                        selected: f.categoryIds.contains(c.id),
                        onSelected: (v) => setState(() {
                          final s = {...f.categoryIds};
                          v ? s.add(c.id) : s.remove(c.id);
                          f = f.copyWith(categoryIds: s);
                        }),
                      ),
                  ]),
                ),
                if (used.isNotEmpty)
                  section(
                    S.currency,
                    Wrap(spacing: Tk.s8, runSpacing: Tk.s8, children: [
                      for (final c in used)
                        FilterChip(
                          label: Text(c),
                          selected: f.currencies.contains(c),
                          onSelected: (v) => setState(() {
                            final s = {...f.currencies};
                            v ? s.add(c) : s.remove(c);
                            f = f.copyWith(currencies: s);
                          }),
                        ),
                    ]),
                  ),
                section(
                  S.keyword,
                  TextField(
                    controller: q,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.rMd)),
                    ),
                    onChanged: (v) => f = f.copyWith(query: v),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s16 + (kb > 0 ? 0 : MediaQuery.viewPaddingOf(context).bottom)),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(Tk.touch),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tk.rMd))),
                  onPressed: () {
                    ref.read(filterProvider.notifier).set(const TxFilter(period: QuickPeriod.all));
                    Navigator.pop(context);
                  },
                  child: const Text(S.reset),
                ),
              ),
              const SizedBox(width: Tk.s12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    ref.read(filterProvider.notifier).set(f);
                    Navigator.pop(context);
                  },
                  child: const Text(S.apply),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
