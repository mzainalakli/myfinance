import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/money/currencies.dart';
import '../../core/money/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../transactions/data/csv_export.dart';
import '../transactions/data/tx_filter.dart';
import '../transactions/ui/common.dart';
import '../transactions/ui/pickers.dart';
import '../widget/widget_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final cur = currencyByCode(s.defaultCurrency);
    final tt = Theme.of(context).textTheme;

    Widget block(String title, Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s12, Tk.s16, Tk.s12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.labelLarge),
            const SizedBox(height: Tk.s8),
            SizedBox(width: double.infinity, child: child),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(children: [
            ListTile(
              minTileHeight: Tk.touch,
              title: const Text(S.defaultCurrency),
              subtitle: Text('${cur.code} · ${cur.name}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final used = ref.read(usedCurrenciesProvider).value ?? const <String>[];
                final c = await showCurrencyPicker(context, selected: s.defaultCurrency, pinned: used);
                if (c != null) {
                  await n.setCurrency(c.code);
                  await WidgetService.refresh(ref.read(repoProvider), ref.read(settingsProvider));
                }
              },
            ),
            block(
              S.defaultType,
              SegmentedButton<TxType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TxType.expense, label: Text(S.expense)),
                  ButtonSegment(value: TxType.income, label: Text(S.income)),
                ],
                selected: {s.defaultType},
                onSelectionChanged: (v) => n.setType(v.first),
              ),
            ),
            block(
              S.theme,
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text(S.themeSystem)),
                  ButtonSegment(value: ThemeMode.light, label: Text(S.themeLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(S.themeDark)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => n.setTheme(v.first),
              ),
            ),
            block(
              S.numberFormat,
              SegmentedButton<NumberStyle>(
                showSelectedIcon: false,
                segments: [for (final x in NumberStyle.values) ButtonSegment(value: x, label: Text(x.label))],
                selected: {s.numberStyle},
                onSelectionChanged: (v) async {
                  await n.setNumberStyle(v.first);
                  await WidgetService.refresh(ref.read(repoProvider), ref.read(settingsProvider));
                },
              ),
            ),
            const Divider(),
            ListTile(
              minTileHeight: Tk.touch,
              leading: const Icon(Icons.category_outlined),
              title: const Text(S.manageCategories),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/categories'),
            ),
            ListTile(
              minTileHeight: Tk.touch,
              leading: const Icon(Icons.ios_share),
              title: const Text(S.exportAllCsv),
              onTap: () async {
                final rows = await ref.read(repoProvider).rows(TxFilter.all);
                if (!context.mounted) return;
                if (rows.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.nothingToExport)));
                  return;
                }
                await shareCsv(rows);
              },
            ),
            Padding(
              padding: const EdgeInsets.all(Tk.s16),
              child: Text(S.about, style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ),
          ]),
        ),
      ),
    );
  }
}
