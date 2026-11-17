import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/transactions/data/repository.dart';
import '../features/transactions/data/summary.dart';
import '../features/transactions/data/tx_filter.dart';
import 'db/database.dart';
import 'money/money.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openAppConnection());
  ref.onDispose(db.close);
  return db;
});

final repoProvider = Provider<Repository>((ref) => Repository(ref.watch(dbProvider)));

// ---------- pengaturan ----------

class AppSettings {
  final String defaultCurrency;
  final TxType defaultType;
  final ThemeMode themeMode;
  final NumberStyle numberStyle;
  const AppSettings({
    this.defaultCurrency = 'IDR',
    this.defaultType = TxType.expense,
    this.themeMode = ThemeMode.system,
    this.numberStyle = NumberStyle.id,
  });

  AppSettings copyWith({String? defaultCurrency, TxType? defaultType, ThemeMode? themeMode, NumberStyle? numberStyle}) =>
      AppSettings(
        defaultCurrency: defaultCurrency ?? this.defaultCurrency,
        defaultType: defaultType ?? this.defaultType,
        themeMode: themeMode ?? this.themeMode,
        numberStyle: numberStyle ?? this.numberStyle,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kCur = 'default_currency';
  static const _kType = 'default_type';
  static const _kTheme = 'theme_mode';
  static const _kNum = 'number_style';

  @override
  AppSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    return AppSettings(
      defaultCurrency: p.getString(_kCur) ?? 'IDR',
      defaultType: TxType.values.asNameMap()[p.getString(_kType)] ?? TxType.expense,
      themeMode: ThemeMode.values.asNameMap()[p.getString(_kTheme)] ?? ThemeMode.system,
      numberStyle: NumberStyle.values.asNameMap()[p.getString(_kNum)] ?? NumberStyle.id,
    );
  }

  Future<void> setCurrency(String c) async {
    state = state.copyWith(defaultCurrency: c);
    await ref.read(sharedPrefsProvider).setString(_kCur, c);
  }

  Future<void> setType(TxType t) async {
    state = state.copyWith(defaultType: t);
    await ref.read(sharedPrefsProvider).setString(_kType, t.name);
  }

  Future<void> setTheme(ThemeMode m) async {
    state = state.copyWith(themeMode: m);
    await ref.read(sharedPrefsProvider).setString(_kTheme, m.name);
  }

  Future<void> setNumberStyle(NumberStyle s) async {
    state = state.copyWith(numberStyle: s);
    await ref.read(sharedPrefsProvider).setString(_kNum, s.name);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
final numberStyleProvider = Provider<NumberStyle>((ref) => ref.watch(settingsProvider.select((s) => s.numberStyle)));

// ---------- filter bersama (Riwayat + Statistik) ----------

class FilterNotifier extends Notifier<TxFilter> {
  @override
  TxFilter build() => const TxFilter();
  void set(TxFilter f) => state = f;
  void setPeriod(QuickPeriod p) => state = state.copyWith(period: p, customRange: null);
}

final filterProvider = NotifierProvider<FilterNotifier, TxFilter>(FilterNotifier.new);

// ---------- data ----------

final rowsProvider = StreamProvider.family<List<TxRow>, TxFilter>(
    (ref, f) => ref.watch(repoProvider).watchRows(f));

final recentRowsProvider = StreamProvider<List<TxRow>>(
    (ref) => ref.watch(repoProvider).watchRows(TxFilter.all, limit: 5));

final monthRowsProvider = StreamProvider<List<TxRow>>(
    (ref) => ref.watch(repoProvider).watchRows(const TxFilter(period: QuickPeriod.month)));

final categoriesByUsageProvider = StreamProvider.family<List<Category>, TxType>(
    (ref, t) => ref.watch(repoProvider).watchCategoriesByUsage(t));

final allCategoriesProvider =
    StreamProvider<List<Category>>((ref) => ref.watch(repoProvider).watchAllCategories());

final usedCurrenciesProvider =
    StreamProvider<List<String>>((ref) => ref.watch(repoProvider).watchUsedCurrencies());
