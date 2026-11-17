package app.myfinance

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

/**
 * Widget 2x1 / 4x1: tombol "+ Keluar", "+ Masuk" (membuka popup) + ringkasan hari ini.
 * Data ringkasan ditulis Dart lewat home_widget ke "HomeWidgetPreferences".
 */
class MyFinanceWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context, manager, id))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle?
    ) {
        manager.updateAppWidget(id, build(context, manager, id))
    }

    private fun build(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val minWidthDp = manager.getAppWidgetOptions(id)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val wide = minWidthDp >= 180
        val views = RemoteViews(
            context.packageName,
            if (wide) R.layout.widget_wide else R.layout.widget_compact
        )

        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val fresh = prefs.getString("today_date", null) == todayKey()
        // Data kemarin dianggap basi: tampilkan nol sampai aplikasi memperbarui.
        val expense = if (fresh) prefs.getString("today_expense", null) else null
        val income = if (fresh) prefs.getString("today_income", null) else null
        val other = if (fresh) prefs.getString("today_other", "") ?: "" else ""
        val none = context.getString(R.string.widget_none)

        views.setTextViewText(
            R.id.txt_expense,
            context.getString(R.string.widget_expense_fmt, expense ?: none)
        )
        if (wide) {
            views.setTextViewText(
                R.id.txt_income,
                context.getString(R.string.widget_income_fmt, income ?: none)
            )
            views.setTextViewText(R.id.txt_other, other)
            views.setViewVisibility(R.id.txt_other, if (other.isEmpty()) View.GONE else View.VISIBLE)
        }

        views.setOnClickPendingIntent(R.id.btn_expense, popup(context, "expense", 1))
        views.setOnClickPendingIntent(R.id.btn_income, popup(context, "income", 2))
        return views
    }

    private fun popup(context: Context, type: String, code: Int): PendingIntent =
        PendingIntent.getActivity(
            context, code, QuickAddActivity.intent(context, type),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun todayKey(): String {
        val c = Calendar.getInstance()
        return String.format(
            "%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH)
        )
    }
}
