import 'package:myfinance/core/money/amount_input.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

AmountInput type(AmountInput a, String keys) {
  for (final k in keys.split(' ')) {
    a = switch (k) {
      ',' => a.comma(),
      '<' => a.backspace(),
      'C' => a.clear(),
      _ => a.digits(k),
    };
  }
  return a;
}

void main() {
  const style = NumberStyle.id;
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');
  final jpy = currencyByCode('JPY');

  group('IDR (0 desimal)', () {
    final e = AmountInput.empty(idr.decimals);
    test('kosong tampil 0 (placeholder)', () {
      expect(e.display(style), '0');
      expect(e.isEmpty, isTrue);
      expect(e.isZero, isTrue);
    });
    test('mengetik 1,0 langsung tampil 10', () {
      final a = type(e, '1 0');
      expect(a.display(style), '10');
      expect(a.toMinorUnits(), 10);
    });
    test('000 menambah nol: 10.000', () {
      final a = type(e, '1 0 000');
      expect(a.display(style), '10.000');
      expect(a.toMinorUnits(), 10000);
    });
    test('pemisah ribuan live', () => expect(type(e, '1 2 5 0 0 0 0').display(style), '1.250.000'));
    test('awalan nol tidak menumpuk', () {
      expect(type(e, '0 0 7').display(style), '7');
      expect(type(e, '000 5').display(style), '5');
      expect(type(e, '0').isEmpty, isTrue);
    });
    test('koma diabaikan', () {
      final a = type(e, '1 2 ,');
      expect(a.display(style), '12');
      expect(a.canComma, isFalse);
    });
    test('backspace dan hapus semua', () {
      var a = type(e, '1 2 3');
      expect(type(a, '<').display(style), '12');
      expect(type(a, '< < <').display(style), '0');
      expect(type(a, '< < < <').display(style), '0');
      expect(type(a, 'C').isEmpty, isTrue);
    });
  });

  group('USD (2 desimal)', () {
    final e = AmountInput.empty(usd.decimals);
    test('desimal tidak muncul sebelum koma', () {
      final a = type(e, '1 0');
      expect(a.display(style), '10');
      expect(a.toMinorUnits(), 1000, reason: '10 USD = 1000 sen');
    });
    test('1 2 , 5 → 12,5 → 1250 sen', () {
      final a = type(e, '1 2 , 5');
      expect(a.display(style), '12,5');
      expect(a.toMinorUnits(), 1250);
    });
    test('digit desimal ke-3 diabaikan', () {
      final a = type(e, '1 2 , 5 7 9');
      expect(a.display(style), '12,57');
      expect(a.toMinorUnits(), 1257);
    });
    test('koma dua kali diabaikan', () => expect(type(e, '1 , , 5').display(style), '1,5'));
    test('koma tanpa desimal: 12, lalu simpan = 12,00', () {
      final a = type(e, '1 2 ,');
      expect(a.display(style), '12,');
      expect(a.toMinorUnits(), 1200);
    });
    test('koma di awal: 0,', () {
      final a = type(e, ',');
      expect(a.display(style), '0,');
      expect(type(a, '5').toMinorUnits(), 50);
    });
    test('backspace menghapus desimal lalu koma', () {
      var a = type(e, '1 2 , 5');
      a = a.backspace();
      expect(a.display(style), '12,');
      a = a.backspace();
      expect(a.display(style), '12');
      a = a.backspace();
      expect(a.display(style), '1');
    });
    test('gaya en', () => expect(type(e, '1 2 3 4 , 5').display(NumberStyle.en), '1,234.5'));
    test('toMoney', () => expect(type(e, '3 , 0 7').toMoney(usd), Money(307, usd)));
    test('fromMinor untuk edit', () {
      expect(AmountInput.fromMinor(1250, 2).display(style), '12,5');
      expect(AmountInput.fromMinor(1200, 2).display(style), '12');
      expect(AmountInput.fromMinor(5, 2).display(style), '0,05');
      expect(AmountInput.fromMinor(5, 2).toMinorUnits(), 5);
      expect(AmountInput.fromMinor(18000, 0).display(style), '18.000');
    });
  });

  group('JPY', () {
    test('tidak ada koma', () {
      final a = AmountInput.empty(jpy.decimals);
      expect(a.canComma, isFalse);
      expect(type(a, '5 , 0').toMinorUnits(), 50);
    });
  });

  group('batas', () {
    test('12 digit bulat, sisanya diabaikan', () {
      final a = type(AmountInput.empty(0), '1 2 3 4 5 6 7 8 9 0 1 2 3');
      expect(a.whole.length, 12);
      expect(a.display(style), '123.456.789.012');
    });
    test('000 semua-atau-tidak di dekat batas', () {
      final a = type(AmountInput.empty(0), '1 2 3 4 5 6 7 8 9 0 1');
      expect(a.digits('000'), a, reason: 'hanya muat 1 digit lagi → tidak ada yang masuk');
    });
    test('maksimum tetap muat di Money untuk semua jumlah desimal', () {
      for (final d in [0, 2, 3]) {
        final a = type(AmountInput.empty(d), '9 9 9 9 9 9 9 9 9 9 9 9${d > 0 ? ' ,' : ''}${d == 2 ? ' 9 9' : d == 3 ? ' 9 9 9' : ''}');
        expect(a.toMinorUnits(), lessThanOrEqualTo(Money.maxMinor), reason: 'd=$d');
        expect(a.toMinorUnits(), greaterThan(0));
      }
    });
  });

  group('ganti mata uang saat terisi', () {
    test('IDR → USD: bagian bulat dipertahankan', () {
      final a = type(AmountInput.empty(0), '1 2 5 0 0 0').withDecimals(2);
      expect(a.display(style), '125.000');
      expect(a.toMinorUnits(), 12500000);
      expect(a.canComma, isTrue);
    });
    test('USD → JPY: desimal dipotong', () {
      final a = type(AmountInput.empty(2), '1 2 , 5').withDecimals(0);
      expect(a.display(style), '12');
      expect(a.hasComma, isFalse);
      expect(a.toMinorUnits(), 12);
    });
    test('KWD(3) → USD(2): desimal berlebih dipotong', () {
      final a = type(AmountInput.empty(3), '1 , 2 3 4').withDecimals(2);
      expect(a.display(style), '1,23');
    });
    test('USD → KWD: tetap', () => expect(type(AmountInput.empty(2), '1 , 5').withDecimals(3).toMinorUnits(), 1500));
  });

  test('mata uang default awal = IDR, 0 desimal (tidak ada desimal tersembunyi)', () {
    const s = AppSettings();
    expect(s.defaultCurrency, 'IDR');
    expect(currencyByCode(s.defaultCurrency).decimals, 0);
    expect(AmountInput.empty(currencyByCode(s.defaultCurrency).decimals).canComma, isFalse);
  });
}
