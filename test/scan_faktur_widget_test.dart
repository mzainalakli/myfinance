import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:myfinance/core/db/database.dart';
import 'package:myfinance/core/money/currencies.dart';
import 'package:myfinance/core/money/money.dart';
import 'package:myfinance/core/providers.dart';
import 'package:myfinance/features/scan_faktur/faktur_parser.dart';
import 'package:myfinance/features/scan_faktur/scan_page.dart';
import 'package:myfinance/features/transactions/data/repository.dart';
import 'package:myfinance/features/transactions/data/tx_filter.dart';
import 'package:myfinance/features/transactions/ui/quick_add_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const leftQr =
      'HB35094463115111713430000005F000000640000000027258805Zm9vYmFyYmF6cXV4MTIzNDU2:**********:1:1:1:Kopi:1:100';
  const rightQr = '**Roti:1:35:Susu:1:20';

  setUpAll(() => initializeDateFormatting('id_ID'));
  late AppDatabase db;
  late Repository repo;

  Future<void> boot(WidgetTester t, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    await t.runAsync(() => repo.watchAllCategories().first); // buka DB + seed
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(411, 891);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), dbProvider.overrideWithValue(db)],
      child: MaterialApp(home: home),
    ));
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> shutdown(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
    await t.runAsync(() async => db.close());
  }

  void tw(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, (t) async {
        await body(t);
        await shutdown(t);
      });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('layar scan', () {
    // halaman pemanggil: tombol membuka ScanPage dengan pemindai palsu; hasil disimpan
    late ValueChanged<String> feed;
    ScanOutcome? result;
    bool popped = false;

    Future<void> openScan(WidgetTester t) async {
      result = null;
      popped = false;
      await boot(
        t,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<ScanOutcome>(MaterialPageRoute(
                    builder: (_) => ScanPage(scannerBuilder: (c, onRaw) {
                      feed = onRaw;
                      return const ColoredBox(color: Colors.black);
                    }),
                  ));
                  popped = true;
                },
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
    }

    Future<void> scan(WidgetTester t, String raw) async {
      await t.runAsync(() async {
        feed(raw);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pump(const Duration(milliseconds: 100));
    }

    tw('petunjuk, senter dan tutup ada; aksi utama di sepertiga bawah', (t) async {
      await openScan(t);
      expect(find.textContaining('QR kiri', findRichText: true), findsOneWidget);
      final h = t.view.physicalSize.height;
      for (final tip in [sTorch, sClose]) {
        final r = t.getRect(find.byTooltip(tip));
        expect(r.top, greaterThan(h * 2 / 3), reason: tip);
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
      }
      expect(find.byTooltip(sClose), findsOneWidget);
    });

    tw('QR kanan: pesan jelas, tetap di layar scan', (t) async {
      await openScan(t);
      await scan(t, rightQr);
      expect(find.text('Ini QR kanan. Scan QR yang di sebelah kiri.'), findsOneWidget);
      expect(find.byType(ScanPage), findsOneWidget);
      expect(popped, isFalse);
    });

    tw('QR bukan faktur dan QR rusak: pesan tepat, tetap di layar', (t) async {
      await openScan(t);
      await scan(t, 'https://example.com');
      expect(find.text('QR ini bukan faktur elektronik Taiwan.'), findsOneWidget);
      await scan(t, 'HB35094463115111713430000005F00000064'); // berawalan faktur tapi terpotong
      expect(find.textContaining('isinya rusak'), findsOneWidget);
      expect(popped, isFalse);
    });

    tw('QR kiri valid: layar menutup dengan satu hasil; deteksi ganda diabaikan', (t) async {
      await openScan(t);
      await t.runAsync(() async {
        feed(leftQr);
        feed(leftQr); // deteksi ganda berurutan
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await t.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, isA<ScanNew>());
      expect((result as ScanNew).data.totalNt, 100);
      expect(find.byType(ScanPage), findsNothing);
    });

    tw('faktur duplikat: dialog tanggal, "Lihat catatan" mengembalikan catatan yang ada', (t) async {
      await openScan(t);
      final cat = (await t.runAsync(() => repo.watchCategories(TxType.expense).first))!.first;
      await t.runAsync(() => repo.addTransaction(
          type: TxType.expense,
          money: Money(10000, currencyByCode('TWD')),
          categoryId: cat.id,
          occurredAt: DateTime(2026, 11, 17, 12),
          invoiceNo: 'HB35094463'));
      await scan(t, leftQr);
      await t.pumpAndSettle();
      expect(find.text('Faktur sudah dicatat'), findsOneWidget);
      expect(find.textContaining('Faktur ini sudah dicatat pada'), findsOneWidget);
      await t.tap(find.text('Lihat catatan'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(result, isA<ScanExisting>());
      expect((result as ScanExisting).row.tx.invoiceNo, 'HB35094463');
      expect(await t.runAsync(() => repo.countTransactions()), 1, reason: 'tidak ada catatan kedua');
    });

    tw('faktur duplikat + Batal: tetap di layar scan, tidak ada hasil', (t) async {
      await openScan(t);
      final cat = (await t.runAsync(() => repo.watchCategories(TxType.expense).first))!.first;
      await t.runAsync(() => repo.addTransaction(
          type: TxType.expense, money: Money(10000, currencyByCode('TWD')), categoryId: cat.id, invoiceNo: 'HB35094463'));
      await scan(t, leftQr);
      await t.pumpAndSettle();
      await t.tap(find.text('Batal'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.byType(ScanPage), findsOneWidget);
      expect(popped, isFalse);
      // pemindaian berikutnya (faktur lain) tetap bisa diproses
      await scan(t, leftQr.replaceFirst('HB35094463', 'HB35094464'));
      await t.pumpAndSettle();
      expect(result, isA<ScanNew>());
    });
  });

  group('izin kamera', () {
    for (final code in [
      MobileScannerErrorCode.permissionDenied,
      MobileScannerErrorCode.unsupported,
      MobileScannerErrorCode.genericError,
    ]) {
      testWidgets('tanpa izin/kamera ($code): penjelasan tampil, tidak crash, bisa catat manual', (t) async {
        var manual = false, settings = false, retry = false;
        await t.pumpWidget(MaterialApp(
          home: CameraProblemView(
            code: code,
            onRetry: () => retry = true,
            onManual: () => manual = true,
            openSettings: () async => settings = true,
          ),
        ));
        expect(find.text('Catat manual'), findsOneWidget);
        final denied = code == MobileScannerErrorCode.permissionDenied;
        expect(find.text('Izin kamera diperlukan'), denied ? findsOneWidget : findsNothing);
        expect(find.text('Buka pengaturan'), denied ? findsOneWidget : findsNothing);
        if (denied) {
          await t.tap(find.text('Buka pengaturan'));
          expect(settings, isTrue);
        }
        if (code != MobileScannerErrorCode.unsupported) {
          await t.tap(find.text('Coba lagi'));
          expect(retry, isTrue);
        }
        await t.tap(find.text('Catat manual'));
        expect(manual, isTrue);
        // tombol di bawah layar (zona jempol)
        expect(t.getRect(find.text('Catat manual')).top, greaterThan(t.view.physicalSize.height / t.view.devicePixelRatio * .6));
      });
    }
  });

  group('form terisi dari faktur', () {
    FakturData data({String npwp = '27258805', String no = 'HB35094463', DateTime? tgl, int total = 100, List<FakturItem> items = const []}) =>
        FakturData(
            nomorFaktur: no,
            tanggal: tgl ?? DateTime(2026, 11, 17),
            kodeAcak: '1343',
            totalNt: total,
            npwpPenjual: npwp,
            npwpPembeli: '00000000',
            daftarBarang: items);

    Future<void> openSheet(WidgetTester t, FakturData d) async {
      await boot(
        t,
        Scaffold(
          body: QuickAddSheet(
            allowScan: true,
            onDone: () {},
            scanOverride: (_) async => ScanNew(d),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.byTooltip('Scan faktur'));
      await settle(t);
    }

    tw('tombol scan hanya untuk jenis Keluar dan pencatatan baru', (t) async {
      await boot(t, Scaffold(body: QuickAddSheet(allowScan: true, onDone: () {})));
      await settle(t);
      expect(find.byTooltip('Scan faktur'), findsOneWidget);
      await t.tap(find.text('Masuk'));
      await t.pump();
      expect(find.byTooltip('Scan faktur'), findsNothing);
      await t.tap(find.text('Keluar'));
      await t.pump();
      expect(find.byTooltip('Scan faktur'), findsOneWidget);
    });

    tw('tombol scan tidak ada di popup (allowScan=false)', (t) async {
      await boot(t, Scaffold(body: QuickAddSheet(onDone: () {})));
      await settle(t);
      expect(find.byTooltip('Scan faktur'), findsNothing);
    });

    tw('penjual belum dikenal: kategori kosong + disorot, Simpan nonaktif sampai dipilih', (t) async {
      await openSheet(t, data(items: const [FakturItem('Kopi', 1, 100)]));
      expect(find.textContaining('HB35094463'), findsOneWidget);
      expect(find.textContaining('Pilih kategori'), findsOneWidget);
      // catatan dari barang pertama
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'Kopi');
      // tidak ada chip kategori terpilih
      expect(t.widgetList<ChoiceChip>(find.byType(ChoiceChip)).any((c) => c.selected), isFalse);
      final save = find.widgetWithText(FilledButton, 'Simpan');
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      // pilih kategori -> bisa disimpan
      await t.tap(find.widgetWithText(ChoiceChip, 'Belanja'));
      await t.pump();
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      expect(find.textContaining('Pilih kategori'), findsNothing);
    });

    tw('simpan: nominal TWD sesuai tabel ISO, tanggal faktur 12:00, nomor faktur + penjual tersimpan', (t) async {
      await openSheet(t, data(tgl: DateTime(2026, 11, 17)));
      await t.tap(find.widgetWithText(ChoiceChip, 'Belanja'));
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.widgetWithText(FilledButton, 'Simpan'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump(const Duration(milliseconds: 100));
      final rows = (await t.runAsync(() => repo.rows(TxFilter.all)))!;
      expect(rows.length, 1);
      final tx = rows.single.tx;
      expect(tx.currencyCode, 'TWD');
      expect(currencyByCode('TWD').decimals, 2);
      expect(tx.amountMinor, 10000, reason: '100 NT\$ x 10^2 (desimal dari tabel ISO)');
      expect(tx.type, TxType.expense);
      expect(tx.invoiceNo, 'HB35094463');
      final at = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
      expect([at.year, at.month, at.day, at.hour, at.minute], [2026, 11, 17, 12, 0]);
      expect(rows.single.category.name, 'Belanja');
      final seller = (await t.runAsync(() => repo.sellerFor('27258805')))!;
      expect(seller.categoryId, rows.single.category.id);
    });

    tw('penjual dikenal: kategori + nama terisi; nominal dan tanggal masih bisa diedit', (t) async {
      await boot(t, Scaffold(body: QuickAddSheet(allowScan: true, onDone: () {}, scanOverride: (_) async => ScanNew(data(no: 'HB35094499', total: 250)))));
      final cat = (await t.runAsync(() => repo.watchCategories(TxType.expense).first))!.firstWhere((c) => c.name == 'Makan & Minum');
      await t.runAsync(() => repo.addTransaction(
          type: TxType.expense, money: Money(100, currencyByCode('TWD')), categoryId: cat.id, note: '7-ELEVEN', invoiceNo: 'ZZ00000001', sellerNpwp: '27258805'));
      await settle(t);
      await t.tap(find.byTooltip('Scan faktur'));
      await settle(t);
      expect(t.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where((c) => c.selected).length, 1);
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Makan & Minum')).selected, isTrue);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '7-ELEVEN');
      expect(find.textContaining('Pilih kategori'), findsNothing);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan')).onPressed, isNotNull);
      // edit nominal: terisi 250 lalu bisa diubah lewat numpad
      expect(find.text('250'), findsOneWidget, reason: 'total faktur tampil sebagai nominal');
      await t.tap(find.byIcon(Icons.backspace_outlined));
      await t.pump();
      expect(find.text('25'), findsOneWidget, reason: 'nominal bisa diedit');
    });

    tw('faktur tanggal hari ini memakai jam sekarang; ganti ke Masuk melepas faktur', (t) async {
      final today = DateTime.now();
      await openSheet(t, data(tgl: DateTime(today.year, today.month, today.day)));
      expect(find.textContaining('HB35094463'), findsOneWidget);
      await t.tap(find.text('Masuk'));
      await t.pump();
      expect(find.textContaining('HB35094463'), findsNothing, reason: 'faktur hanya untuk pengeluaran');
    });
  });
}

const sTorch = 'Senter';
const sClose = 'Tutup';
