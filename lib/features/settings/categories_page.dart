import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/category_style.dart';
import '../transactions/data/repository.dart';
import '../transactions/ui/common.dart';

String categoryErrorText(CategoryError e) => switch (e) {
      CategoryError.emptyName => S.errEmptyName,
      CategoryError.nameTooLong => S.errNameTooLong,
      CategoryError.duplicateName => S.errDuplicate,
      CategoryError.typeLocked => S.kindLocked,
      CategoryError.lastOfType => S.errLastOfType,
      CategoryError.hasTransactions => S.errHasTx,
      CategoryError.invalidTarget => S.errInvalidTarget,
      CategoryError.notFound => S.errNotFound,
    };

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});
  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  bool archivedOpen = false;

  void _msg(String text, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text), action: action));

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on CategoryException catch (e) {
      if (mounted) _msg(categoryErrorText(e.error));
    }
  }

  Future<void> _edit(Category? c, {TxType type = TxType.expense}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => _CategoryEditor(category: c, type: type),
      );

  Future<void> _delete(Category c, int count) async {
    final repo = ref.read(repoProvider);
    if (await repo.isLastActive(c)) {
      if (mounted) _msg(S.errLastOfType);
      return;
    }
    if (count == 0) {
      await _guard(() async {
        final d = await repo.deleteCategory(c.id);
        _msg(S.catDeleted,
            action: SnackBarAction(label: S.undo, onPressed: () => repo.restoreCategory(d)));
      });
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _DeleteChoiceSheet(category: c, count: count),
    );
    if (choice == 'archive') {
      await _guard(() async {
        await repo.archiveCategory(c.id);
        _msg(S.catArchivedMsg,
            action: SnackBarAction(label: S.undo, onPressed: () => repo.unarchiveCategory(c.id)));
      });
    } else if (choice == 'move') {
      if (!mounted) return;
      final all = ref.read(allCategoriesProvider).value ?? const <Category>[];
      final targets = all.where((x) => x.type == c.type && !x.isArchived && x.id != c.id).toList();
      final target = await showModalBottomSheet<Category>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => _TargetPicker(targets: targets),
      );
      if (target == null) return;
      await _guard(() async {
        final n = await repo.moveTransactionsAndDelete(c.id, target.id);
        _msg(S.catMoved(n));
      });
    }
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _section(TxType type, List<Category> list, Map<int, int> counts) {
    final repo = ref.read(repoProvider);
    final cs = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: list.length,
      onReorderItem: (a, b) async {
        final ids = list.map((c) => c.id).toList();
        ids.insert(b, ids.removeAt(a));
        await repo.reorderCategories(ids);
      },
      itemBuilder: (_, i) {
        final c = list[i];
        final n = counts[c.id] ?? 0;
        return Slidable(
          key: ValueKey(c.id),
          startActionPane: ActionPane(motion: const DrawerMotion(), extentRatio: .25, children: [
            SlidableAction(
              onPressed: (_) => _edit(c, type: c.type),
              icon: Icons.edit,
              label: S.edit,
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
          ]),
          endActionPane: ActionPane(motion: const DrawerMotion(), extentRatio: .25, children: [
            SlidableAction(
              onPressed: (_) => _delete(c, n),
              icon: Icons.delete_outline,
              label: S.delete,
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
            ),
          ]),
          child: ListTile(
            minTileHeight: 60,
            leading: CategoryAvatar(icon: c.icon, color: c.color),
            title: Text(c.name),
            subtitle: Text(n == 0 ? S.unusedCategory : S.txCount(n)),
            onTap: () => _edit(c, type: c.type),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Padding(
                padding: const EdgeInsets.all(Tk.s12),
                child: Icon(Icons.drag_handle, color: cs.outline),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repoProvider);
    final all = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final counts = ref.watch(categoryCountsProvider).value ?? const <int, int>{};
    List<Category> active(TxType t) => all.where((c) => c.type == t && !c.isArchived).toList();
    final archived = all.where((c) => c.isArchived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text(S.manageCategories)),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Tk.s16),
            children: [
              _header(S.expenseHeader),
              _section(TxType.expense, active(TxType.expense), counts),
              _header(S.incomeHeader),
              _section(TxType.income, active(TxType.income), counts),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: Tk.s8),
                ListTile(
                  minTileHeight: Tk.touch,
                  title: Text('${S.archived} (${archived.length})'),
                  trailing: Icon(archivedOpen ? Icons.expand_less : Icons.expand_more),
                  onTap: () => setState(() => archivedOpen = !archivedOpen),
                ),
                if (archivedOpen)
                  for (final c in archived)
                    ListTile(
                      key: ValueKey('arch-${c.id}'),
                      minTileHeight: 60,
                      leading: Opacity(opacity: .6, child: CategoryAvatar(icon: c.icon, color: c.color)),
                      title: Text(c.name),
                      subtitle: Text(
                          '${c.type == TxType.expense ? S.expenseHeader : S.incomeHeader} · ${S.txCount(counts[c.id] ?? 0)}'),
                      onTap: () => _edit(c, type: c.type),
                      trailing: TextButton(
                        onPressed: () => _guard(() async {
                          await repo.unarchiveCategory(c.id);
                          _msg(S.catRestoredMsg);
                        }),
                        child: const Text(S.restore),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.all(Tk.s12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text(S.addCategory),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteChoiceSheet extends StatelessWidget {
  final Category category;
  final int count;
  const _DeleteChoiceSheet({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s16, Tk.s16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.usedBy(category.name, count), style: tt.titleMedium),
        const SizedBox(height: Tk.s4),
        Text(S.usedByHint, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Tk.s16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
          onPressed: () => Navigator.pop(context, 'archive'),
          child: const Text(S.archiveRecommended),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s4, Tk.s4, Tk.s4, Tk.s12),
          child: Text(S.archiveHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
          onPressed: () => Navigator.pop(context, 'move'),
          child: const Text(S.moveAndDelete),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tk.s4, Tk.s4, Tk.s4, Tk.s12),
          child: Text(S.moveHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
      ]),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  final List<Category> targets;
  const _TargetPicker({required this.targets});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(Tk.s16),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(S.chooseTarget, style: Theme.of(context).textTheme.titleMedium)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in targets)
                ListTile(
                  minTileHeight: Tk.touch,
                  leading: CategoryAvatar(icon: c.icon, color: c.color),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(context, c),
                ),
            ]),
          ),
        ]),
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
  late TxType kind = widget.category?.type ?? widget.type;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repoProvider);
    final c = widget.category;
    try {
      if (c == null) {
        await repo.addCategory(name: name.text, icon: icon, color: color, type: kind);
      } else {
        await repo.updateCategory(c.id, name: name.text, icon: icon, color: color, type: kind);
      }
      if (mounted) Navigator.pop(context);
    } on CategoryException catch (e) {
      if (mounted) setState(() => error = categoryErrorText(e.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c = widget.category;
    final locked = c != null && (ref.watch(categoryCountsProvider).value?[c.id] ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.category == null ? S.addCategory : S.editCategory, style: tt.titleMedium),
          const SizedBox(height: Tk.s12),
          Text(S.kind, style: tt.labelLarge),
          const SizedBox(height: Tk.s8),
          SegmentedButton<TxType>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text(S.expense)),
              ButtonSegment(value: TxType.income, label: Text(S.income)),
            ],
            selected: {kind},
            onSelectionChanged: locked ? null : (v) => setState(() => kind = v.first),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s4),
              child: Text(S.kindLocked, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: Tk.s16),
          TextField(
            controller: name,
            maxLength: 40,
            onChanged: (_) => error == null ? null : setState(() => error = null),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: S.categoryName,
              counterText: '',
              errorText: error,
              errorMaxLines: 3,
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
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
            onPressed: _save,
            child: const Text(S.save),
          ),
        ]),
      ),
    );
  }
}
