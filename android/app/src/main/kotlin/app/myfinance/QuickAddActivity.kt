package app.myfinance

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * Popup catat cepat: Activity Flutter transparan dengan entrypoint Dart terpisah
 * (`quickAddMain`). Jenis transaksi dikirim sebagai rute awal `/quick/<type>`.
 */
class QuickAddActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "quickAddMain"

    override fun getInitialRoute(): String =
        "/quick/" + (intent?.getStringExtra(EXTRA_TYPE) ?: "expense")

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    companion object {
        const val EXTRA_TYPE = "type"

        fun intent(context: Context, type: String): Intent =
            Intent(context, QuickAddActivity::class.java)
                .putExtra(EXTRA_TYPE, type)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    }
}
