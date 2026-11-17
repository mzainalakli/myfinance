/// Nama tampilan (tempat 2 dari 3; lihat docs/GANTI_NAMA.md).
/// Jangan hardcode nama aplikasi di tempat lain: baca dari sini.
class AppConfig {
  static const appName = 'MyFinance';

  /// Nama internal, netral. Jangan diganti bersama nama tampilan.
  static const dbFileName = 'myfinance.db';
  static const widgetProvider = 'app.myfinance.MyFinanceWidgetProvider';

  /// Awalan nama file ekspor, turunan dari nama tampilan.
  static String get filePrefix => appName.toLowerCase().replaceAll(' ', '');
}
