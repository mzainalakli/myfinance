import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final idr = currencyByCode('IDR');
  final usd = currencyByCode('USD');
  final jpy = currencyByCode('JPY');
  final kwd = currencyByCode('KWD');

  test('desimal per mata uang', () {
    expect(idr.decimals, 0);
    expect(usd.decimals, 2);
    expect(jpy.decimals, 0);
    expect(kwd.decimals, 3);
  });

  group('format', () {
    test('IDR tanpa desimal, titik ribuan', () {
      expect(Money(18000, idr).format(), 'Rp 18.000');
      expect(Money(1234567, idr).formatNumber(), '1.234.567');
      expect(Money(0, idr).formatNumber(), '0');
    });
    test('USD 2 desimal', () {
      expect(Money(1250, usd).formatNumber(), '12,50');
      expect(Money(5, usd).formatNumber(), '0,05');
      expect(Money(123456789, usd).formatNumber(style: NumberStyle.en), '1,234,567.89');
    });
    test('negatif dan bertanda', () {
      expect(Money(-1250, usd).format(), '-\$ 12,50');
      expect(Money(1250, usd).format(signed: true), '+\$ 12,50');
    });
    test('KWD 3 desimal', () => expect(Money(1500, kwd).formatNumber(), '1,500'));
    test('plain', () {
      expect(Money(-123456, usd).toPlainString(), '-1234.56');
      expect(Money(7, usd).toPlainString(), '0.07');
      expect(Money(500, jpy).toPlainString(), '500');
    });
  });

  group('parse', () {
    test('id style', () {
      expect(Money.parse('18.000', idr), Money(18000, idr));
      expect(Money.parse('Rp 1.234.567', idr), Money(1234567, idr));
      expect(Money.parse('12,5', usd), Money(1250, usd));
      expect(Money.parse('1.234,56', usd), Money(123456, usd));
      expect(Money.parse('-3,07', usd), Money(-307, usd));
      expect(Money.parse('5', usd), Money(500, usd));
    });
    test('en style', () {
      expect(Money.parse('1,234.56', usd, style: NumberStyle.en), Money(123456, usd));
    });
    test('tolak input tak valid', () {
      expect(Money.parse('', idr), isNull);
      expect(Money.parse('abc', idr), isNull);
      expect(Money.parse('12,345', idr), isNull, reason: 'IDR tak punya desimal');
      expect(Money.parse('12,345', usd), isNull, reason: 'desimal berlebih');
      expect(Money.parse('1.23.4', idr), isNull, reason: 'grup ribuan salah');
      expect(Money.parse('1,2,3', usd), isNull);
      expect(Money.parse('99999999999999999999', idr), isNull);
    });
    test('bolak-balik tanpa kehilangan presisi', () {
      for (final c in [idr, usd, jpy, kwd]) {
        for (final v in [0, 1, 9, 99, 100, 123456, 987654321, Money.maxMinor]) {
          final m = Money(v, c);
          expect(Money.parse(m.formatNumber(), c), m, reason: '${c.code} $v');
        }
      }
    });
  });

  test('operasi hanya untuk mata uang sama', () {
    expect(Money(100, usd) + Money(50, usd), Money(150, usd));
    expect(() => Money(100, usd) + Money(50, idr), throwsArgumentError);
  });

  test('bebas error float: 0.1 + 0.2 dalam sen', () {
    expect((Money(10, usd) + Money(20, usd)).toPlainString(), '0.30');
  });
}
