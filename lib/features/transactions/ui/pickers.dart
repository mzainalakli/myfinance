import 'package:flutter/material.dart';

import '../../../core/money/currencies.dart';
import '../../../core/money/currency.dart';
import '../../../core/strings.dart';
import '../../../core/theme/tokens.dart';

/// Pemilih mata uang sebagai bottom sheet (bukan dropdown di atas).
Future<Currency?> showCurrencyPicker(BuildContext context, {String? selected, Iterable<String> pinned = const []}) {
  return showModalBottomSheet<Currency>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CurrencySheet(selected: selected, pinned: pinned.toList()),
  );
}

class _CurrencySheet extends StatefulWidget {
  final String? selected;
  final List<String> pinned;
  const _CurrencySheet({this.selected, required this.pinned});
  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final all = allCurrencies;
    final lower = q.toLowerCase();
    var list = all
        .where((c) => lower.isEmpty || c.code.toLowerCase().contains(lower) || c.name.toLowerCase().contains(lower))
        .toList();
    if (lower.isEmpty) {
      final pin = widget.pinned.toSet();
      list.sort((a, b) {
        final pa = pin.contains(a.code) ? 0 : 1, pb = pin.contains(b.code) ? 0 : 1;
        return pa != pb ? pa - pb : 0;
      });
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(children: [
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  minTileHeight: Tk.touch,
                  leading: SizedBox(width: 48, child: Text(c.symbol, style: const TextStyle(fontWeight: FontWeight.w700))),
                  title: Text(c.code),
                  subtitle: Text(c.name),
                  selected: c.code == widget.selected,
                  trailing: c.code == widget.selected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s16),
            child: TextField(
              decoration: InputDecoration(
                hintText: S.searchCurrency,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.rMd)),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
        ]),
      ),
    );
  }
}
