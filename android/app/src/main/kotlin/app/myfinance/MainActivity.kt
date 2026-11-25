package app.myfinance

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Buka layar info aplikasi (untuk memberi izin kamera yang ditolak permanen). Tanpa dependensi tambahan.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.myfinance/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openAppSettings") {
                    val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(i)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
