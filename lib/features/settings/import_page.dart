import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/csv/transaction_csv.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../transactions/data/csv_export.dart';
import '../transactions/data/import_service.dart';
import '../transactions/ui/common.dart';
import '../widget/widget_service.dart';
import 'package:path_provider/path_provider.dart';

enum _Step { idle, reading, preview, writing, done }

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  _Step step = _Step.idle;
  String? fileName;
  String? problem; // galat fatal berkas
  TxCsvParseResult? parsed;
  ImportMode mode = ImportMode.merge;
  ImportPlan? plan;
  ImportResult? result;
  int done = 0, total = 0;
  int existingCount = 0;

  ImportService get _service => ImportService(
        ref.read(dbProvider),
        backupDir: _backupDir,
      );
  Directory? _backupDir;

  Future<void> _pick() async {
    setState(() => problem = null);
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(type: FileType.any);
    } catch (_) {
      if (mounted) setState(() => problem = S.readFail);
      return;
    }
    if (f == null || !mounted) return; // dibatalkan
    final path = f.path;
    if (path == null) {
      setState(() => problem = S.readFail);
      return;
    }
    setState(() {
      step = _Step.reading;
      fileName = f!.name;
    });
    try {
      final bytes = await File(path).readAsBytes();
      // di isolate: berkas besar tidak membekukan UI
      final res = await compute(parseTransactionCsvBytes, bytes);
      if (!mounted) return;
      if (res.fatal != null) {
        setState(() {
          step = _Step.idle;
          problem = res.fatal;
        });
        return;
      }
      parsed = res;
      mode = ImportMode.merge;
      final dir = await getApplicationSupportDirectory();
      _backupDir = Directory('${dir.path}/backups');
      existingCount = await ref.read(repoProvider).countTransactions();
      await _replan();
      if (mounted) setState(() => step = _Step.preview);
    } catch (_) {
      if (mounted) {
        setState(() {
          step = _Step.idle;
          problem = S.readFail;
        });
      }
    }
  }

  Future<void> _replan() async {
    final p = await _service.plan(parsed!, mode);
    if (mounted) setState(() => plan = p);
  }

  Future<void> _run() async {
    final p = plan!;
    if (p.mode == ImportMode.replace) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(S.confirmReplaceTitle),
          content: Text('$existingCount transaksi yang ada sekarang akan DIHAPUS dan diganti dengan '
              '${p.toInsert.length} transaksi dari berkas.\n\n${S.modeReplaceHint}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(96, Tk.touch), backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(S.modeReplace),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      step = _Step.writing;
      done = 0;
      total = p.toInsert.length;
    });
    try {
      final r = await _service.execute(p, onProgress: (d, t) {
        if (mounted) setState(() => done = d);
      });
      await WidgetService.refresh(ref.read(repoProvider), ref.read(settingsProvider));
      if (mounted) {
        setState(() {
          result = r;
          step = _Step.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          step = _Step.preview;
          problem = 'Impor dibatalkan, tidak ada data yang berubah. ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final writing = step == _Step.writing;
    return PopScope(
      canPop: !writing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && writing) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(content: Text(S.dontLeave)));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text(S.importTitle), automaticallyImplyLeading: !writing),
        body: SafeArea(
          child: ContentWidth(
            child: switch (step) {
              _Step.idle => _idle(context),
              _Step.reading => _busy(S.reading, null),
              _Step.preview => _preview(context),
              _Step.writing => _busy(S.writing, total == 0 ? null : done / total, detail: '$done / $total'),
              _Step.done => _done(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _busy(String text, double? value, {String? detail}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Tk.s32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: value),
            const SizedBox(height: Tk.s16),
            Text(text),
            if (detail != null) Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );

  Widget _bottomBar(List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s16),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _errorCard(String msg) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Tk.s16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: Tk.s12),
          Expanded(child: Text(msg, style: TextStyle(color: cs.onErrorContainer))),
        ]),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Tk.s16), children: [
          const EmptyState(icon: Icons.upload_file_outlined, title: S.importTitle, message: S.importIntro),
          if (problem != null) ...[const SizedBox(height: Tk.s16), _errorCard('${S.fileError}: $problem')],
        ]),
      ),
      _bottomBar([
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
          onPressed: () => shareCsvTemplate(),
          icon: const Icon(Icons.description_outlined),
          label: const Text(S.shareTemplate),
        ),
        const SizedBox(height: Tk.s8),
        FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text(S.pickCsv)),
      ]),
    ]);
  }

  Widget _row(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ?trailing,
        ]),
      );

  Widget _preview(BuildContext context) {
    final p = plan!;
    final pr = parsed!;
    final style = ref.watch(numberStyleProvider);
    final hidden = ref.watch(hiddenProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final replace = mode == ImportMode.replace;
    final canImport = replace ? pr.records.isNotEmpty : p.toInsert.isNotEmpty;

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s16), children: [
          if (fileName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Tk.s8),
              child: Text(fileName!, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (problem != null) ...[_errorCard(problem!), const SizedBox(height: Tk.s12)],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Tk.s16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.previewTitle, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: Tk.s8),
                _row(S.validRows, '${pr.records.length} dari ${pr.totalRows}'),
                _row(S.willAdd, '${p.toInsert.length}'),
                _row(S.dupSkipped, '${p.duplicates}'),
                _row(
                  S.errorRows,
                  '${p.errors.length}',
                  trailing: p.errors.isEmpty
                      ? null
                      : TextButton(onPressed: () => _showErrors(p.errors), child: const Text(S.showErrors)),
                ),
                _row(S.newCategoriesLabel, p.newCategories.isEmpty ? S.none : '${p.newCategories.length}'),
                if (p.newCategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(p.newCategories.map((c) => c.name).join(', '),
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                if (p.from != null) _row(S.dateRangeLabel, '${fullDayLabel(p.from!)} – ${fullDayLabel(p.to!)}'),
              ]),
            ),
          ),
          const SizedBox(height: Tk.s12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Tk.s16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.totalsPerCurrency, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: Tk.s8),
                if (p.totals.isEmpty) Text(S.none, style: TextStyle(color: cs.onSurfaceVariant)),
                for (final t in p.totals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 44, child: Text(t.currency.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(
                        child: Wrap(spacing: Tk.s12, children: [
                          MoneyText(t.income,
                              style: style, hidden: hidden, prefix: '+', textStyle: TextStyle(color: context.incomeColor)),
                          MoneyText(t.expense,
                              style: style, hidden: hidden, prefix: '-', textStyle: TextStyle(color: context.expenseColor)),
                        ]),
                      ),
                      Text('${t.count}×', style: tt.bodySmall),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: Tk.s12),
          if (replace)
            _errorCard('$existingCount transaksi sekarang akan dihapus. ${S.backupSaved}')
          else
            Text(S.modeMergeHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      _bottomBar([
        SegmentedButton<ImportMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
          segments: const [
            ButtonSegment(value: ImportMode.merge, label: Text(S.modeMerge)),
            ButtonSegment(value: ImportMode.replace, label: Text(S.modeReplace)),
          ],
          selected: {mode},
          onSelectionChanged: (v) async {
            setState(() {
              mode = v.first;
              problem = null;
            });
            await _replan();
          },
        ),
        const SizedBox(height: Tk.s8),
        Row(children: [
          IconButton.outlined(
            tooltip: S.retry,
            constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
            onPressed: () => setState(() {
              step = _Step.idle;
              problem = null;
              parsed = null;
              plan = null;
            }),
            icon: const Icon(Icons.folder_open),
          ),
          const SizedBox(width: Tk.s12),
          Expanded(
            child: FilledButton(
              onPressed: canImport ? _run : null,
              style: replace ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
              child: Text(canImport
                  ? '${S.importAction} ${p.toInsert.length} transaksi'
                  : S.nothingNew),
            ),
          ),
        ]),
      ]),
    ]);
  }

  void _showErrors(List<TxCsvRowError> errors) {
    const maxShown = 200;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .75),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s24),
          itemCount: errors.length > maxShown ? maxShown + 1 : errors.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i == maxShown) {
              return Padding(
                padding: const EdgeInsets.all(Tk.s12),
                child: Text('${errors.length - maxShown} ${S.moreErrors}'),
              );
            }
            final e = errors[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Baris ${e.line} · ${e.column}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(e.message),
            );
          },
        ),
      ),
    );
  }

  Widget _done(BuildContext context) {
    final r = result!;
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Tk.s16), children: [
          const SizedBox(height: Tk.s24),
          Icon(Icons.check_circle_outline, size: 72, color: context.incomeColor),
          const SizedBox(height: Tk.s16),
          Text(S.importDone, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Tk.s8),
          Text('${r.added} ${S.added}, ${r.skipped} ${S.skipped}, ${r.failed} ${S.failed}',
              textAlign: TextAlign.center, style: tt.titleMedium),
          if (r.backupPath != null) ...[
            const SizedBox(height: Tk.s24),
            Text(S.backupSaved, textAlign: TextAlign.center),
          ],
        ]),
      ),
      _bottomBar([
        if (r.backupPath != null) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(r.backupPath!, mimeType: 'text/csv')])),
            icon: const Icon(Icons.ios_share),
            label: const Text(S.shareBackup),
          ),
          const SizedBox(height: Tk.s8),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(S.done)),
      ]),
    ]);
  }
}

