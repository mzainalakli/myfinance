import 'currency.dart';

/// Gaya penulisan angka.
enum NumberStyle {
  /// 1.234,56
  id('1.234,56', '.', ','),
  /// 1,234.56
  en('1,234.56', ',', '.');

  final String label;
  final String group;
  final String decimal;
  const NumberStyle(this.label, this.group, this.decimal);
}

/// Nominal uang: integer satuan terkecil + mata uang. Tidak pernah memakai double.
class Money {
  /// Batas wajar agar aman di int 64-bit dan terbaca (sekitar 10 triliun unit utama).
  static const int maxMinor = 999999999999999;

  final int minor;
  final Currency currency;
  const Money(this.minor, this.currency);

  const Money.zero(Currency c) : this(0, c);

  int get _factor {
    var f = 1;
    for (var i = 0; i < currency.decimals; i++) {
      f *= 10;
    }
    return f;
  }

  bool get isNegative => minor < 0;

  Money operator +(Money o) {
    _same(o);
    return Money(minor + o.minor, currency);
  }

  Money operator -(Money o) {
    _same(o);
    return Money(minor - o.minor, currency);
  }

  void _same(Money o) {
    if (o.currency != currency) {
      throw ArgumentError('Mata uang berbeda: ${currency.code} vs ${o.currency.code}');
    }
  }

  /// Bagian digit dengan pemisah ribuan & desimal, tanpa simbol/tanda.
  String formatNumber({NumberStyle style = NumberStyle.id, bool trimZeroDecimals = false}) {
    final abs = minor.abs();
    final whole = abs ~/ _factor;
    final frac = abs % _factor;
    final grouped = _group(whole.toString(), style.group);
    if (currency.decimals == 0) return grouped;
    final fracStr = frac.toString().padLeft(currency.decimals, '0');
    if (trimZeroDecimals && frac == 0) return grouped;
    return '$grouped${style.decimal}$fracStr';
  }

  /// Contoh: `Rp 18.000`, `-US$ 12,50` (simbol dipisah spasi, tanda di depan).
  String format({NumberStyle style = NumberStyle.id, bool showSymbol = true, bool signed = false}) {
    final sign = minor < 0 ? '-' : (signed && minor > 0 ? '+' : '');
    final num = formatNumber(style: style);
    return showSymbol ? '$sign${currency.symbol} $num' : '$sign$num';
  }

  /// Bentuk polos untuk ekspor: `-1234.56`, titik desimal, tanpa pemisah ribuan.
  String toPlainString() {
    final abs = minor.abs();
    final whole = abs ~/ _factor;
    final sign = minor < 0 ? '-' : '';
    if (currency.decimals == 0) return '$sign$whole';
    final frac = (abs % _factor).toString().padLeft(currency.decimals, '0');
    return '$sign$whole.$frac';
  }

  /// Parse teks ke [Money]. Menerima simbol/spasi di sekitar angka.
  /// Pemisah mengikuti [style]; jika hanya ada satu jenis pemisah yang cocok dengan
  /// pemisah ribuan dan diikuti tepat 3 digit, dianggap ribuan. Mengembalikan null bila
  /// tidak valid (huruf, desimal berlebih, di luar batas).
  static Money? parse(String input, Currency currency, {NumberStyle style = NumberStyle.id}) {
    var s = input.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    // buang simbol di depan
    final sym = currency.symbol.replaceAll(' ', '');
    if (s.startsWith(sym) && sym.isNotEmpty) s = s.substring(sym.length);
    if (s.startsWith(currency.code)) s = s.substring(currency.code.length);
    if (s.isEmpty) return null;
    if (!RegExp('^[0-9${RegExp.escape(style.group)}${RegExp.escape(style.decimal)}]+\$').hasMatch(s)) {
      return null;
    }
    final parts = s.split(style.decimal);
    if (parts.length > 2) return null;
    final wholeRaw = parts[0];
    final fracRaw = parts.length == 2 ? parts[1] : '';
    if (fracRaw.contains(style.group)) return null;
    if (wholeRaw.isEmpty && fracRaw.isEmpty) return null;
    // validasi pengelompokan ribuan: tiap grup setelah yang pertama tepat 3 digit
    final groups = wholeRaw.split(style.group);
    if (groups.length > 1) {
      if (groups.first.isEmpty || groups.first.length > 3) return null;
      for (final g in groups.skip(1)) {
        if (g.length != 3) return null;
      }
    }
    final whole = groups.join();
    if (fracRaw.length > currency.decimals) return null;
    final fracPadded = fracRaw.padRight(currency.decimals, '0');
    final digits = '${whole.isEmpty ? '0' : whole}$fracPadded';
    if (digits.length > 18) return null;
    final v = int.tryParse(digits);
    if (v == null || v > maxMinor) return null;
    return Money(neg ? -v : v, currency);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;
  @override
  int get hashCode => Object.hash(minor, currency);
  @override
  String toString() => 'Money(${toPlainString()} ${currency.code})';

  static String _group(String digits, String sep) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(sep);
      b.write(digits[i]);
    }
    return b.toString();
  }
}
