import 'currency.dart';
import 'money.dart';

/// State-machine murni untuk input nominal di numpad (tanpa widget).
///
/// Angka mengisi bagian bulat secara natural; desimal baru muncul setelah [comma]
/// ditekan dan hanya untuk mata uang yang punya desimal. Konversi akhir ke satuan
/// terkecil lewat [toMoney] (tanpa double).
class AmountInput {
  /// Panjang maksimum bagian bulat. 12 digit × 10^3 (KWD) = 999.999.999.999.999 = [Money.maxMinor].
  static const int maxWholeDigits = 12;

  final int decimals;
  final String whole; // digit tanpa awalan nol; '' berarti 0
  final bool hasComma;
  final String frac; // digit desimal yang sudah diketik (<= decimals)

  const AmountInput(this.decimals, {this.whole = '', this.hasComma = false, this.frac = ''});

  const AmountInput.empty(int decimals) : this(decimals);

  /// Untuk mengedit transaksi lama: 1250 sen → "12,5"; 1200 sen → "12".
  factory AmountInput.fromMinor(int minor, int decimals) {
    final abs = minor.abs();
    var f = 1;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    final w = (abs ~/ f).toString();
    var fr = decimals == 0 ? '' : (abs % f).toString().padLeft(decimals, '0');
    fr = fr.replaceFirst(RegExp(r'0+$'), '');
    return AmountInput(decimals, whole: w == '0' ? '' : w, hasComma: fr.isNotEmpty, frac: fr);
  }

  bool get canComma => decimals > 0;
  bool get isEmpty => whole.isEmpty && !hasComma && frac.isEmpty;
  bool get isZero => toMinorUnits() == 0;

  /// Satu digit '0'..'9'. Diabaikan bila melebihi batas.
  AmountInput digit(String d) {
    assert(d.length == 1 && d.codeUnitAt(0) >= 48 && d.codeUnitAt(0) <= 57);
    if (hasComma) {
      if (frac.length >= decimals) return this;
      return AmountInput(decimals, whole: whole, hasComma: true, frac: frac + d);
    }
    var w = whole + d;
    w = w.replaceFirst(RegExp(r'^0+'), '');
    if (w.length > maxWholeDigits) return this;
    return AmountInput(decimals, whole: w);
  }

  /// Banyak digit sekaligus (mis. tombol "000"). Semua-atau-tidak: tidak ada setengah masuk.
  AmountInput digits(String ds) {
    var s = this;
    for (final ch in ds.split('')) {
      final n = s.digit(ch);
      if (identical(n, s)) return this;
      s = n;
    }
    return s;
  }

  /// Koma desimal; diabaikan bila mata uang tanpa desimal atau koma sudah ada.
  AmountInput comma() {
    if (!canComma || hasComma) return this;
    return AmountInput(decimals, whole: whole, hasComma: true);
  }

  /// Hapus satu karakter dari belakang (termasuk koma).
  AmountInput backspace() {
    if (hasComma) {
      if (frac.isNotEmpty) return AmountInput(decimals, whole: whole, hasComma: true, frac: frac.substring(0, frac.length - 1));
      return AmountInput(decimals, whole: whole);
    }
    if (whole.isEmpty) return this;
    return AmountInput(decimals, whole: whole.substring(0, whole.length - 1));
  }

  AmountInput clear() => AmountInput.empty(decimals);

  /// Ganti mata uang: bagian bulat dipertahankan, desimal berlebih dipotong.
  AmountInput withDecimals(int newDecimals) {
    if (newDecimals == decimals) return this;
    if (newDecimals == 0) return AmountInput(0, whole: whole);
    final fr = frac.length > newDecimals ? frac.substring(0, newDecimals) : frac;
    return AmountInput(newDecimals, whole: whole, hasComma: hasComma && true, frac: fr);
  }

  /// Teks tampilan live, mis. `1.250.000`, `12,5`, `12,` atau `0`.
  String display(NumberStyle style) {
    final w = whole.isEmpty ? '0' : _group(whole, style.group);
    if (!hasComma) return w;
    return '$w${style.decimal}$frac';
  }

  /// Nilai dalam satuan terkecil, tanpa double: "10" USD → 1000.
  int toMinorUnits() {
    final w = whole.isEmpty ? 0 : int.parse(whole);
    var f = 1;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    final fr = decimals == 0 ? 0 : (frac.isEmpty ? 0 : int.parse(frac.padRight(decimals, '0')));
    return w * f + fr;
  }

  Money toMoney(Currency c) => Money(toMinorUnits(), c);

  static String _group(String digits, String sep) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(sep);
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is AmountInput &&
      other.decimals == decimals &&
      other.whole == whole &&
      other.hasComma == hasComma &&
      other.frac == frac;
  @override
  int get hashCode => Object.hash(decimals, whole, hasComma, frac);
}
