import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/money/amount_input.dart';
import '../../../core/money/currencies.dart';
import '../../../core/providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/category_style.dart';
import '../../../core/util/dates.dart';
import '../../widget/widget_service.dart';
import '../data/summary.dart';
import 'numpad.dart';
import 'pickers.dart';

/// Buka sheet pencatatan di aplikasi utama.
Future<void> showQuickAddSheet(BuildContext context, {TxType? type, TxRow? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => QuickAddSheet(
      initialType: type,
      editing: editing,
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
  const QuickAddSheet({super.key, this.initialType, this.editing, required this.onDone});

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
      await repo.addTransaction(type: type, money: money, categoryId: effectiveCategory, note: note.text, occurredAt: at);
    } else {
      final old = fromEpochMs(e.tx.occurredAt);
      final keepTime = startOfDay(old) == startOfDay(date);
      await repo.updateTransaction(e.tx.id,
          type: type,
          money: money,
          categoryId: effectiveCategory,
          note: note.text,
          occurredAt: keepTime ? old : DateTime(date.year, date.month, date.day, 12));
    }
    await WidgetService.refresh(repo, ref.read(settingsProvider));
    HapticFeedback.lightImpact();
    widget.onDone();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: addDays(DateTime.now(), 1),
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
    final effective = cats.any((c) => c.id == categoryId) ? categoryId : (cats.isEmpty ? null : cats.first.id);
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
        }),
      ),
    );

    final categoryGrid = Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Tk.s16),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(spacing: Tk.s8, runSpacing: Tk.s8, children: [
            for (final c in cats)
              ChoiceChip(
                avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                label: Text(c.name),
                selected: c.id == effective,
                showCheckmark: false,
                visualDensity: VisualDensity.standard,
                onSelected: (_) => setState(() => categoryId = c.id),
              ),
          ]),
        ),
      ),
    );

    final noteRow = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s8, 0),
      child: Row(children: [
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
      ]),
    );

    final amountRow = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s4),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              input.display(style),
              style: tt.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700, color: input.isEmpty ? cs.outline : accent),
            ),
          ),
        ),
        const SizedBox(width: Tk.s8),
        ActionChip(
          label: Text('${cur.symbol} · ${cur.code}'),
          onPressed: () async {
            final used = ref.read(usedCurrenciesProvider).value ?? const <String>[];
            final c = await showCurrencyPicker(context,
                selected: currencyCode, pinned: [ref.read(settingsProvider).defaultCurrency, ...used]);
            if (c != null) {
              setState(() {
                currencyCode = c.code;
                input = input.withDecimals(c.decimals);
              });
            }
          },
        ),
      ]),
    );

    final saveButton = Padding(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s4, Tk.s16, Tk.s8),
      child: FilledButton(
        onPressed: keyboard ? () => noteFocus.unfocus() : (canSave ? () => _save(effective) : null),
        style: FilledButton.styleFrom(backgroundColor: keyboard ? null : accent, minimumSize: const Size.fromHeight(52)),
        child: Text(keyboard ? S.done : S.save),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: height,
        child: Column(children: [
          header,
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
        ]),
      ),
    );
  }
}
