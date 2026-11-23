import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/format.dart';
import '../../widget/widget_service.dart';
import '../data/csv_export.dart';
import '../data/summary.dart';
import '../data/tx_filter.dart';
import 'common.dart';
import 'filter_bar.dart';
import 'quick_add_sheet.dart';

sealed class _Item {}

class _Header extends _Item {
  final DateTime day;
  _Header(this.day);
}

class _Entry extends _Item {
  final TxRow row;
  _Entry(this.row);
}

List<_Item> _group(List<TxRow> rows) {
  final out = <_Item>[];
  DateTime? cur;
  for (final r in rows) {
    final d = startOfDay(fromEpochMs(r.tx.occurredAt));
    if (cur != d) {
      cur = d;
      out.add(_Header(d));
    }
    out.add(_Entry(r));
  }
  return out;
}

/// Hapus dengan Urungkan (snackbar). Dipakai juga di Beranda.
Future<void> deleteWithUndo(BuildContext context, WidgetRef ref, TxRow row) async {
  final repo = ref.read(repoProvider);
  final messenger = ScaffoldMessenger.of(context);
  await repo.deleteTransaction(row.tx.id);
  await WidgetService.refresh(repo, ref.read(settingsProvider));
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: const Text(S.deleted),
      action: SnackBarAction(
        label: S.undo,
        onPressed: () async {
          await repo.restoreTransaction(row.tx);
          await WidgetService.refresh(repo, ref.read(settingsProvider));
        },
      ),
    ));
}

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final async = ref.watch(rowsProvider(filter));
    final rows = async.value;

    Future<void> export() async {
      final data = rows ?? const <TxRow>[];
      if (data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.nothingToExport)));
        return;
      }
      await shareCsv(data);
    }

    return SafeArea(
      bottom: false,
      child: Column(children: [
        ContentWidth(
          child: PageTitle(S.history, actions: [
            const HideToggleButton(),
            IconButton(tooltip: S.exportCsv, onPressed: export, icon: const Icon(Icons.ios_share)),
          ]),
        ),
        const FilterBar(),
        Expanded(
          child: ContentWidth(
            child: rows == null
                ? const SkeletonList()
                : rows.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: S.noRecordsTitle,
                        message: filter.advancedCount == 0 && filter.period == QuickPeriod.all
                            ? S.noRecordsHome
                            : S.noRecordsFilter)
                    : _List(rows: rows),
          ),
        ),
      ]),
    );
  }
}

class _List extends ConsumerWidget {
  final List<TxRow> rows;
  const _List({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _group(rows);
    final totals = summarize(rows.map((r) => r.tx));
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Tk.fabClearance),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s8),
            child: SummaryCard(totals: totals),
          );
        }
        final it = items[i - 1];
        switch (it) {
          case _Header h:
            return Padding(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s4),
              child: Text(dayLabel(h.day),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            );
          case _Entry e:
            return Slidable(
              key: ValueKey(e.row.tx.id),
              startActionPane: ActionPane(motion: const DrawerMotion(), extentRatio: .25, children: [
                SlidableAction(
                  onPressed: (_) => showQuickAddSheet(context, editing: e.row),
                  icon: Icons.edit,
                  label: S.edit,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                ),
              ]),
              endActionPane: ActionPane(motion: const DrawerMotion(), extentRatio: .25, children: [
                SlidableAction(
                  onPressed: (_) => deleteWithUndo(context, ref, e.row),
                  icon: Icons.delete_outline,
                  label: S.delete,
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                ),
              ]),
              child: TxTile(row: e.row, onTap: () => showQuickAddSheet(context, editing: e.row)),
            );
        }
      },
    );
  }
}
