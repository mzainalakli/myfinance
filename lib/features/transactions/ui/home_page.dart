import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/format.dart';
import '../data/summary.dart';
import 'common.dart';
import 'quick_add_sheet.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthRowsProvider);
    final recent = ref.watch(recentRowsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            PageTitle(AppConfig.appName, actions: [
              IconButton(
                tooltip: S.settings,
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s8),
              child: month.when(
                data: (rows) =>
                    SummaryCard(
                        title: monthLabel(DateTime.now()),
                        showEye: true,
                        totals: summarize(rows.map((r) => r.tx))),
                loading: () => const SizedBox(height: 120, child: Card()),
                error: (e, _) => Text('$e'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s4),
              child: Text(S.latest, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
            recent.when(
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: Tk.s32),
                      child: EmptyState(
                          icon: Icons.edit_note, title: S.noRecordsTitle, message: S.noRecordsHome),
                    )
                  : Column(children: [
                      for (final r in rows)
                        TxTile(
                          row: r,
                          showDate: true,
                          onTap: () => showQuickAddSheet(context, editing: r),
                        ),
                      TextButton(
                        onPressed: () => context.go('/history'),
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
                        child: const Text(S.history),
                      ),
                    ]),
              loading: () => const SkeletonList(count: 4),
              error: (e, _) => Text('$e'),
            ),
          ],
        ),
      ),
    );
  }
}

