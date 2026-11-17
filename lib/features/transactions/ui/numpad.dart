import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';

/// Numpad kustom: 1-9, 000, 0, hapus. Tidak memunculkan keyboard sistem.
class Numpad extends StatelessWidget {
  final void Function(String digits) onDigits;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final double keyHeight;
  const Numpad({
    super.key,
    required this.onDigits,
    required this.onDelete,
    required this.onClear,
    this.keyHeight = Tk.touch,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {Widget? child, required VoidCallback onTap, VoidCallback? onLong}) {
      final cs = Theme.of(context).colorScheme;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Tk.rMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(Tk.rMd),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              onLongPress: onLong,
              child: SizedBox(
                height: keyHeight - 6,
                child: Center(
                  child: child ?? Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<String> d) => Row(children: [for (final x in d) key(x, onTap: () => onDigits(x))]);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      row(['1', '2', '3']),
      row(['4', '5', '6']),
      row(['7', '8', '9']),
      Row(children: [
        key('000', onTap: () => onDigits('000')),
        key('0', onTap: () => onDigits('0')),
        key('', child: const Icon(Icons.backspace_outlined), onTap: onDelete, onLong: onClear),
      ]),
    ]);
  }
}
