package com.lifelog.lifelog

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class CourseReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "上课提醒"
        val body = intent.getStringExtra("body") ?: "马上要上课啦"
        val id = intent.getIntExtra("id", 1001)

        val pattern = longArrayOf(0, 500, 200, 500, 200, 600)

        // 1) 直接触发系统硬件震动（绕过 ColorOS 等对通知渠道的静默降级）
        try {
            val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            if (vibrator != null && vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1), attrs)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, -1)
                }
            }
        } catch (_: Exception) {}

        // 2) 使用全新高优渠道 ID (course_reminders_v2)，因为 Android 一旦创建过旧渠道就不会再更新其震动属性
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "course_reminders_v2"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val ch = NotificationChannel(
                channelId,
                "生活助手·强提醒通知",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "上课、校车、天气与组间休息到时强震动横幅提醒（请在系统设置中保持重要通知与震动开启）"
                enableVibration(true)
                vibrationPattern = pattern
                enableLights(true)
                setSound(soundUri, audioAttrs)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentPi = if (launchIntent != null) {
            PendingIntent.getActivity(context, id, launchIntent, piFlags)
        } else null

        val defaultSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val notifBuilder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setSound(defaultSound)
            .setVibrate(pattern)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)

        if (contentPi != null) {
            notifBuilder.setContentIntent(contentPi)
            notifBuilder.setFullScreenIntent(contentPi, true)
        }

        nm.notify(id, notifBuilder.build())
    }
}
