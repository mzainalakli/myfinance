import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/money/amount_input.dart';
import '../../../core/money/currencies.dart';
import '../../../core/money/money.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/category_style.dart';
import '../../../core/util/dates.dart';
import '../../scan_faktur/faktur_parser.dart';
import '../../scan_faktur/scan_page.dart';
import '../../widget/widget_service.dart';
import '../data/repository.dart';
import '../data/summary.dart';
import 'numpad.dart';
import 'pickers.dart';

/// Buka sheet pencatatan di aplikasi utama.
Future<void> showQuickAddSheet(BuildContext context, {TxType? type, TxRow? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => QuickAddSheet(
      initialType: type,
      editing: editing,
      allowScan: editing == null, // kamera hanya di aplikasi utama, bukan di popup widget
      onDone: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// Sheet pencatatan: Keluar/Masuk, kategori, catatan, nominal + mata uang, numpad, Simpan.
/// Dipakai bersama oleh aplikasi utama dan popup widget.
class QuickAddSheet extends ConsumerStatefulWidget {
  final TxType? initialType;
  final TxRow? editing;
  final VoidCallback onDone;

  /// Tampilkan tombol "Scan faktur" (hanya aplikasi utama, pencatatan baru, jenis Keluar).
  final bool allowScan;

  /// Pengganti layar scan untuk pengujian (bawaan: [ScanPage] dengan kamera).
  final Future<ScanOutcome?> Function(BuildContext context)? scanOverride;
  const QuickAddSheet({
    super.key,
    this.initialType,
    this.editing,
    required this.onDone,
    this.allowScan = false,
    this.scanOverride,
  });

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  late TxType type;
  int? categoryId;
  late AmountInput input;
  late String currencyCode;
  late DateTime date;
  final note = TextEditingController();
  final noteFocus = FocusNode();
  bool saving = false;

  /// Faktur hasil scan yang melekat pada catatan ini (nomor disimpan bersama transaksi).
  FakturData? invoice;

  /// Penjual belum dikenal: kategori sengaja kosong dan disorot sampai pengguna memilih.
  bool awaitingCategory = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    final e = widget.editing;
    if (e != null) {
      type = e.tx.type;
      categoryId = e.tx.categoryId;
      currencyCode = e.tx.currencyCode;
      input = AmountInput.fromMinor(e.tx.amountMinor, currencyByCode(currencyCode).decimals);
      date = fromEpochMs(e.tx.occurredAt);
      note.text = e.tx.note;
    } else {
      type = widget.initialType ?? s.defaultType;
      currencyCode = s.defaultCurrency;
      input = AmountInput.empty(currencyByCode(currencyCode).decimals);
      date = DateTime.now();
    }
    noteFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    note.dispose();
    noteFocus.dispose();
    super.dispose();
  }

  Future<void> _save(int? effectiveCategory) async {
    if (saving || input.isZero || effectiveCategory == null) return;
    setState(() => saving = true);
    final repo = ref.read(repoProvider);
    final money = input.toMoney(currencyByCode(currencyCode));
    final e = widget.editing;
    if (e == null) {
      final now = DateTime.now();
      // Tanggal hari ini: pakai jam sekarang agar urutan di dalam hari benar.
      final at = startOfDay(date) == startOfDay(now) ? now : DateTime(date.year, date.month, date.day, 12);
      try {
        await repo.addTransaction(
          type: type,
          money: money,
          categoryId: effectiveCategory,
          note: note.text,
          occurredAt: at,
          invoiceNo: invoice?.nomorFaktur,
          sellerNpwp: invoice?.npwpPenjual,
        );
      } on DuplicateInvoiceException {
        if (mounted) {
          setState(() => saving = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.invoiceDuplicateSave)));
        }
        return;
      }
    } else {
      final old = fromEpochMs(e.tx.occurredAt);
      final keepTime = startOfDay(old) == startOfDay(date);
      await repo.updateTransaction(
        e.tx.id,
        type: type,
        money: money,
        categoryId: effectiveCategory,
        note: note.text,
        occurredAt: keepTime ? old : DateTime(date.year, date.month, date.day, 12),
      );
    }
    await WidgetService.refresh(repo, ref.read(settingsProvider));
    HapticFeedback.lightImpact();
    widget.onDone();
  }

  Future<void> _scan() async {
    final nav = Navigator.of(context, rootNavigator: true);
    final out =
        await (widget.scanOverride?.call(context) ??
            nav.push<ScanOutcome>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScanPage())));
    if (!mounted || out == null) return;
    switch (out) {
      case ScanExisting e:
        // faktur sudah tercatat: tutup sheet ini, buka catatan yang ada
        widget.onDone();
        if (nav.mounted) showQuickAddSheet(nav.context, editing: e.row);
      case ScanNew n:
        await _applyInvoice(n.data);
    }
  }

  /// Isi form dari faktur: Keluar, TWD, total, tanggal, kategori/catatan dari ingatan penjual.
  Future<void> _applyInvoice(FakturData d) async {
    final repo = ref.read(repoProvider);
    final twd = currencyByCode('TWD');
    var minor = d.totalNt;
    for (var i = 0; i < twd.decimals; i++) {
      minor *= 10; // desimal dari tabel ISO 4217, tidak di-hardcode
    }
    if (minor > Money.maxMinor) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.invoiceTooBig)));
      return;
    }
    final cat = await repo.rememberedCategory(d.npwpPenjual);
    final seller = await repo.sellerFor(d.npwpPenjual);
    if (!mounted) return;
    final name = (seller?.name?.isNotEmpty ?? false)
        ? seller!.name!
        : (d.daftarBarang.isNotEmpty ? d.daftarBarang.first.nama : '');
    setState(() {
      invoice = d;
      type = TxType.expense;
      currencyCode = twd.code;
      input = AmountInput.fromMinor(minor, twd.decimals);
      date = d.tanggal;
      categoryId = cat?.id;
      awaitingCategory = cat == null;
      note.text = name;
    });
  }

  Future<void> _pickDate() async {
    final last = addDays(DateTime.now(), 1);
    final d = await showDatePicker(
      context: context,
      initialDate: date.isAfter(last) ? last : date,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (d != null) setState(() => date = d);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final keyboard = kb > 0 || noteFocus.hasFocus;
    final style = ref.watch(numberStyleProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final cur = currencyByCode(currencyCode);
    final accent = type == TxType.income ? context.incomeColor : context.expenseColor;

    var cats = ref.watch(categoriesByUsageProvider(type)).value ?? const <Category>[];
    final e = widget.editing;
    if (e != null && e.tx.type == type && !cats.any((c) => c.id == e.category.id)) {
      cats = [e.category, ...cats]; // kategori terarsip tetap tampil saat mengubah
    }
    final effective = awaitingCategory
        ? null
        : (cats.any((c) => c.id == categoryId) ? categoryId : (cats.isEmpty ? null : cats.first.id));
    final canSave = !input.isZero && effective != null && !saving;

    final avail = mq.size.height - mq.padding.top - kb - 8;
    final height = math.min(avail, 720.0);
    final bottomSafe = kb > 0 ? 0.0 : mq.viewPadding.bottom;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s8),
      child: SegmentedButton<TxType>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        segments: const [
          ButtonSegment(value: TxType.expense, label: Text(S.expense)),
          ButtonSegment(value: TxType.income, label: Text(S.income)),
        ],
        selected: {type},
        onSelectionChanged: (s) => setState(() {
          type = s.first;
          categoryId = null;
          if (type == TxType.income) {
            invoice = null; // faktur hanya untuk pengeluaran
            awaitingCategory = false;
          }
        }),
      ),
    );

    final categoryGrid = Flexible(
      child: Container(
        key: const ValueKey('category-area'),
        margin: const EdgeInsets.symmetric(horizontal: Tk.s8),
        decoration: awaitingCategory
            ? BoxDecoration(
                border: Border.all(color: cs.primary, width: 2),
                borderRadius: BorderRadius.circular(Tk.rMd),
              )
            : null,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Tk.s16),
          child: Align(
            alignment: Alignment.topLeft,
            child: Wrap(
              spacing: Tk.s8,
              runSpacing: Tk.s8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                    label: Text(c.name),
                    selected: c.id == effective,
                    showCheckmark: false,
                    visualDensity: VisualDensity.standard,
                    onSelected: (_) => setState(() {
                      categoryId = c.id;
                      awaitingCategory = false;
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final invoiceRow = invoice == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.receipt_long, size: 18),
                label: Text(
                  awaitingCategory
                      ? '${S.invoiceChip} ${invoice!.nomorFaktur} · ${S.pickCategory}'
                      : '${S.invoiceChip} ${invoice!.nomorFaktur}',
                ),
                onDeleted: () => setState(() {
                  invoice = null;
                  awaitingCategory = false;
                }),
              ),
            ),
          );

    final noteRow = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s8, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: note,
              focusNode: noteFocus,
              maxLines: 1,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => noteFocus.unfocus(),
              onTapOutside: (_) => noteFocus.unfocus(),
              decoration: InputDecoration(
                hintText: S.note,
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: Tk.s12, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.rMd)),
              ),
            ),
          ),
          IconButton(
            tooltip: S.date,
            onPressed: _pickDate,
            icon: Badge(
              isLabelVisible: startOfDay(date) != startOfDay(DateTime.now()),
              smallSize: 8,
              child: const Icon(Icons.event),
            ),
            constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
          ),
        ],
      ),
    );

    final amountRow = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s4),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                input.display(style),
                style: tt.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: input.isEmpty ? cs.outline : accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: Tk.s8),
          if (widget.allowScan && type == TxType.expense && widget.editing == null)
            IconButton(
              tooltip: S.scanInvoice,
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
            ),
          ActionChip(
            label: Text('${cur.symbol} · ${cur.code}'),
            onPressed: () async {
              final used = ref.read(usedCurrenciesProvider).value ?? const <String>[];
              final c = await showCurrencyPicker(
                context,
                selected: currencyCode,
                pinned: [ref.read(settingsProvider).defaultCurrency, ...used],
              );
              if (c != null) {
                setState(() {
                  currencyCode = c.code;
                  input = input.withDecimals(c.decimals);
                });
              }
            },
          ),
        ],
      ),
    );

    final saveButton = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s4, Tk.s16, Tk.s8),
      child: FilledButton(
        onPressed: keyboard ? () => noteFocus.unfocus() : (canSave ? () => _save(effective) : null),
        style: FilledButton.styleFrom(
          backgroundColor: keyboard ? null : accent,
          minimumSize: const Size.fromHeight(52),
        ),
        child: Text(keyboard ? S.done : S.save),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            header,
            invoiceRow,
            categoryGrid,
            noteRow,
            if (!keyboard) amountRow,
            saveButton,
            if (!keyboard)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Tk.s12),
                child: Numpad(
                  showComma: cur.decimals > 0,
                  onDigits: (d) => setState(() => input = input.digits(d)),
                  onComma: () => setState(() => input = input.comma()),
                  onDelete: () => setState(() => input = input.backspace()),
                  onClear: () => setState(() => input = input.clear()),
                ),
              ),
            SizedBox(height: bottomSafe + Tk.s8),
          ],
        ),
      ),
    );
  }
}
