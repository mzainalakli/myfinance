import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../transactions/data/summary.dart';
import 'faktur_parser.dart';

/// Hasil layar scan: faktur baru (isi form) atau faktur yang sudah tercatat (buka catatannya).
sealed class ScanOutcome {
  const ScanOutcome();
}

class ScanNew extends ScanOutcome {
  final FakturData data;
  const ScanNew(this.data);
}

class ScanExisting extends ScanOutcome {
  final TxRow row;
  const ScanExisting(this.row);
}

/// Pembangun tampilan pemindai. Bawaan = kamera sungguhan; tes menyuntikkan pengganti tanpa kamera.
typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onRaw);

const _settingsChannel = MethodChannel('app.myfinance/settings');

/// Buka layar info aplikasi Android (tempat izin kamera diubah). False bila gagal.
Future<bool> openAppSettings() async {
  try {
    return await _settingsChannel.invokeMethod<bool>('openAppSettings') ?? false;
  } catch (_) {
    return false;
  }
}

String fakturErrorText(FakturGagalAlasan a) => switch (a) {
      FakturGagalAlasan.qrKananTerdeteksi => S.scanErrRight,
      FakturGagalAlasan.bukanFaktur => S.scanErrNotInvoice,
      FakturGagalAlasan.formatRusak => S.scanErrBroken,
    };

class ScanPage extends ConsumerStatefulWidget {
  final ScannerViewBuilder? scannerBuilder;
  const ScanPage({super.key, this.scannerBuilder});
  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  MobileScannerController? controller;
  bool handled = false; // hanya satu hasil yang diproses
  String? error;
  String? lastBad;
  DateTime lastBadAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null) {
      // ML Kit versi yang dibundel (default paket; properti useUnbundled TIDAK diset): berfungsi offline.
      controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _onRaw(String raw) async {
    if (handled) return;
    final r = parseFaktur(raw);
    switch (r) {
      case FakturGagal g:
        // kode yang sama terus-menerus terdeteksi: jangan memicu ulang pesan/state tiap frame
        final now = DateTime.now();
        if (raw == lastBad && now.difference(lastBadAt) < const Duration(seconds: 2)) return;
        lastBad = raw;
        lastBadAt = now;
        if (mounted) setState(() => error = fakturErrorText(g.alasan));
      case FakturOk ok:
        handled = true;
        HapticFeedback.mediumImpact();
        await controller?.stop();
        final repo = ref.read(repoProvider);
        final dup = await repo.findByInvoice(ok.data.nomorFaktur);
        if (!mounted) return;
        if (dup == null) {
          Navigator.of(context).pop<ScanOutcome>(ScanNew(ok.data));
          return;
        }
        final row = await repo.rowById(dup.id);
        if (!mounted) return;
        final see = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(S.scanDupTitle),
            content: Text(S.scanDupBody(dayLabel(DateTime.fromMillisecondsSinceEpoch(dup.occurredAt)))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.scanSeeRecord)),
            ],
          ),
        );
        if (!mounted) return;
        if (see == true && row != null) {
          Navigator.of(context).pop<ScanOutcome>(ScanExisting(row));
        } else {
          // Batal: tetap di layar scan, kamera menyala lagi
          setState(() {
            handled = false;
            error = null;
          });
          await controller?.start();
        }
    }
  }

  Widget _camera() {
    final b = widget.scannerBuilder;
    if (b != null) return b(context, _onRaw);
    return MobileScanner(
      controller: controller,
      onDetect: (cap) {
        for (final c in cap.barcodes) {
          final v = c.rawValue;
          if (v != null) {
            _onRaw(v);
            break;
          }
        }
      },
      errorBuilder: (ctx, e) => CameraProblemView(
        code: e.errorCode,
        onRetry: () => controller?.start(),
        onManual: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    const scrim = Color(0xCC000000);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _camera(),
        // bingkai pemandu di tengah
        IgnorePointer(
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(Tk.rLg),
              ),
            ),
          ),
        ),
        // area atas: hanya informasi
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(Tk.s16),
              padding: const EdgeInsets.symmetric(horizontal: Tk.s16, vertical: Tk.s12),
              decoration: BoxDecoration(color: scrim, borderRadius: BorderRadius.circular(Tk.rMd)),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: S.scanHintPre),
                  TextSpan(text: S.scanHintLeft, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: S.scanHintPost),
                ]),
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
        // pesan galat tetap di layar; kamera tetap memindai
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 104),
              child: error == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: const ValueKey('scan-error'),
                      margin: const EdgeInsets.symmetric(horizontal: Tk.s16),
                      padding: const EdgeInsets.symmetric(horizontal: Tk.s16, vertical: Tk.s12),
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Tk.rMd)),
                      child: Text(error!, textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer)),
                    ),
            ),
          ),
        ),
        // aksi utama di sepertiga bawah: senter + tutup
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Tk.s24),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _RoundButton(
                  icon: Icons.flashlight_on_outlined,
                  tooltip: S.scanTorch,
                  onPressed: () => controller?.toggleTorch(),
                ),
                const SizedBox(width: Tk.s32),
                _RoundButton(
                  icon: Icons.close,
                  tooltip: S.scanClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed});
  @override
  Widget build(BuildContext context) => IconButton.filled(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
        style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
        icon: Icon(icon),
      );
}

/// Kamera bermasalah: izin ditolak, tidak ada kamera, atau galat lain. Pengguna tetap bisa mencatat manual.
class CameraProblemView extends StatelessWidget {
  final MobileScannerErrorCode code;
  final VoidCallback onRetry;
  final VoidCallback onManual;
  final Future<bool> Function()? openSettings;
  const CameraProblemView({super.key, required this.code, required this.onRetry, required this.onManual, this.openSettings});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final denied = code == MobileScannerErrorCode.permissionDenied;
    final text = denied
        ? S.camDeniedBody
        : code == MobileScannerErrorCode.unsupported
            ? S.camUnsupported
            : S.camError;
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Tk.s24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.no_photography_outlined, size: 64, color: cs.outline),
                  const SizedBox(height: Tk.s16),
                  Text(denied ? S.camDeniedTitle : S.scanInvoice, style: tt.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: Tk.s8),
                  Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
          // tombol di bawah (zona jempol)
          Padding(
            padding: const EdgeInsets.fromLTRB(Tk.s16, 0, Tk.s16, Tk.s16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (denied) ...[
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
                  onPressed: () => (openSettings ?? openAppSettings)(),
                  child: const Text(S.openSettings),
                ),
                const SizedBox(height: Tk.s8),
              ],
              if (code != MobileScannerErrorCode.unsupported) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
                  onPressed: onRetry,
                  child: const Text(S.camRetry),
                ),
                const SizedBox(height: Tk.s8),
              ],
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Tk.touch)),
                onPressed: onManual,
                child: const Text(S.recordManually),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
