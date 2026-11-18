package com.lifelog.lifelog

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class LifeAssistantWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "life_assistant_widget_prefs"

        fun saveAndRefresh(context: Context, courseLine: String, calorieLine: String, stepLine: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString("course", courseLine)
                .putString("calorie", calorieLine)
                .putString("step", stepLine)
                .apply()

            refreshAll(context)
        }

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, LifeAssistantWidgetProvider::class.java))
            for (id in ids) {
                updateWidget(context, mgr, id)
            }
        }

        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val course = prefs.getString("course", "📅 今日暂无课程") ?: "📅 今日暂无课程"
            val calorie = prefs.getString("calorie", "🔥 剩余热量：2000 kcal") ?: "🔥 剩余热量：2000 kcal"
            val step = prefs.getString("step", "👟 今日步数：0 步") ?: "👟 今日步数：0 步"

            val views = RemoteViews(context.packageName, R.layout.life_assistant_widget).apply {
                setTextViewText(R.id.widget_course_text, course)
                setTextViewText(R.id.widget_calorie_text, calorie)
                setTextViewText(R.id.widget_step_text, step)
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pi = PendingIntent.getActivity(context, 0, launchIntent, flags)
                views.setOnClickPendingIntent(R.id.widget_root, pi)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
