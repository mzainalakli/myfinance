import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/category_style.dart';
import '../transactions/ui/common.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});
  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  TxType type = TxType.expense;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repoProvider);
    final all = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final list = all.where((c) => c.type == type).toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text(S.manageCategories)),
      body: SafeArea(
        child: ContentWidth(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: Tk.s16),
            itemCount: list.length,
            onReorderItem: (a, b) async {
              final ids = list.map((c) => c.id).toList();
              ids.insert(b, ids.removeAt(a));
              await repo.reorderCategories(ids);
            },
            itemBuilder: (_, i) {
              final c = list[i];
              return Opacity(
                key: ValueKey(c.id),
                opacity: c.isArchived ? .5 : 1,
                child: ListTile(
                  minTileHeight: 60,
                  leading: CategoryAvatar(icon: c.icon, color: c.color),
                  title: Text(c.name),
                  subtitle: c.isArchived ? const Text(S.archived) : null,
                  onTap: () => _edit(context, c),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: c.isArchived ? S.unarchive : S.archive,
                      icon: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      onPressed: () => repo.setArchived(c.id, !c.isArchived),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(Tk.s12),
                        child: Icon(Icons.drag_handle, color: cs.outline),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.all(Tk.s12),
            child: Row(children: [
              Expanded(
                child: SegmentedButton<TxType>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
                  segments: const [
                    ButtonSegment(value: TxType.expense, label: Text(S.expense)),
                    ButtonSegment(value: TxType.income, label: Text(S.income)),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => setState(() => type = v.first),
                ),
              ),
              const SizedBox(width: Tk.s12),
              IconButton.filled(
                tooltip: S.addCategory,
                constraints: const BoxConstraints(minWidth: Tk.touch, minHeight: Tk.touch),
                onPressed: () => _edit(context, null),
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Category? c) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => _CategoryEditor(category: c, type: type),
      );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  final Category? category;
  final TxType type;
  const _CategoryEditor({this.category, required this.type});
  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final name = TextEditingController(text: widget.category?.name ?? '');
  late String icon = widget.category?.icon ?? 'more';
  late int color = widget.category?.color ?? categoryColors.first;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) return;
    final repo = ref.read(repoProvider);
    final c = widget.category;
    if (c == null) {
      await repo.addCategory(name: n, icon: icon, color: color, type: widget.type);
    } else {
      await repo.updateCategory(c.id, name: n, icon: icon, color: color);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.category == null ? S.addCategory : S.editCategory, style: tt.titleMedium),
          const SizedBox(height: Tk.s12),
          TextField(
            controller: name,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: S.categoryName,
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.rMd)),
            ),
          ),
          const SizedBox(height: Tk.s16),
          Text(S.icon, style: tt.labelLarge),
          const SizedBox(height: Tk.s8),
          Wrap(spacing: Tk.s8, runSpacing: Tk.s8, children: [
            for (final e in categoryIcons.entries)
              InkResponse(
                onTap: () => setState(() => icon = e.key),
                child: Container(
                  width: Tk.touch,
                  height: Tk.touch,
                  decoration: BoxDecoration(
                    color: icon == e.key ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Tk.rMd),
                  ),
                  child: Icon(e.value, color: icon == e.key ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                ),
              ),
          ]),
          const SizedBox(height: Tk.s16),
          Text(S.color, style: tt.labelLarge),
          const SizedBox(height: Tk.s8),
          Wrap(spacing: Tk.s8, runSpacing: Tk.s8, children: [
            for (final c in categoryColors)
              InkResponse(
                onTap: () => setState(() => color = c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                  child: color == c ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
          ]),
          const SizedBox(height: Tk.s24),
          FilledButton(onPressed: _save, child: const Text(S.save)),
        ]),
      ),
    );
  }
}
