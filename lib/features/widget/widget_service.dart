import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/app_config.dart';
import '../../core/money/currencies.dart';
import '../../core/money/money.dart';
import '../../core/providers.dart';
import '../transactions/data/repository.dart';
import '../transactions/data/summary.dart';
import '../transactions/data/tx_filter.dart';

/// Mendorong ringkasan "hari ini" ke widget layar utama (SharedPreferences native).
/// Dipanggil setiap selesai menyimpan/mengubah/menghapus dan saat aplikasi dibuka.
class WidgetService {
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Isi data widget. MURNI & teruji: saat disembunyikan, yang dikirim ke widget SUDAH berupa topeng
  /// (angka asli tidak pernah keluar dari aplikasi), bukan sekadar disembunyikan oleh tampilan.
  static Map<String, String> buildPayload(List<CurrencyTotal> totals, AppSettings settings, DateTime now) {
    final cur = currencyByCode(settings.defaultCurrency);
    final main = totals.where((t) => t.currency == cur).firstOrNull;
    final exp = main?.expense ?? Money.zero(cur);
    final inc = main?.income ?? Money.zero(cur);
    final other = totals.where((t) => t.currency != cur).length;
    final style = settings.numberStyle;
    final hidden = settings.balanceHidden;
    return {
      'today_date': _dateKey(now),
      'today_expense': exp.format(style: style, hidden: hidden),
      'today_income': inc.format(style: style, hidden: hidden),
      'today_other': other > 0 ? '+$other mata uang lain' : '',
    };
  }

  static Future<void> refresh(Repository repo, AppSettings settings) async {
    try {
      final now = DateTime.now();
      final totals = await repo.totals(const TxFilter(period: QuickPeriod.today), now: now);
      final payload = buildPayload(totals, settings, now);
      for (final e in payload.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: AppConfig.widgetProvider);
    } catch (e) {
      // Widget bersifat pelengkap: kegagalan tidak boleh menggagalkan penyimpanan.
      debugPrint('Widget refresh gagal: $e');
    }
  }
}
