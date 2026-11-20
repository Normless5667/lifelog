package com.lifelog.lifelog

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * 跑步 GPS 轨迹前台服务：
 * - 在 Android 8~15 上以前台定位服务运行，锁屏或切后台时 GPS 持续记录不断轨
 * - 通知栏显示「正在记录跑步」常驻低打扰通知，实时刷新距离/时长/配速
 * - 持有带上限的 PARTIAL_WAKE_LOCK 防止 CPU 休眠导致断轨，停止时立即释放
 */
class RunningForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseWakeLock()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                ensureChannel()
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIF_ID, buildNotification(title, body))
                return START_STICKY
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent?.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                ensureChannel()
                acquireWakeLock()
                val notification = buildNotification(title, body)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIF_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                    )
                } else {
                    startForeground(NOTIF_ID, notification)
                }
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "LifeLog::RunningGpsWakeLock"
                ).apply { setReferenceCounted(false) }
            }
            if (wakeLock?.isHeld != true) {
                // 4 小时安全超时，避免异常退出永久持锁
                wakeLock?.acquire(4 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "跑步 GPS 轨迹记录",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "跑步记录进行中的后台 GPS 定位常驻通知（静音低打扰）"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            NOTIF_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "running_tracking_v1"
        const val NOTIF_ID = 3101
        const val ACTION_START = "com.lifelog.lifelog.RUNNING_START"
        const val ACTION_UPDATE = "com.lifelog.lifelog.RUNNING_UPDATE"
        const val ACTION_STOP = "com.lifelog.lifelog.RUNNING_STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val DEFAULT_TITLE = "正在记录跑步"
        const val DEFAULT_BODY = "GPS 轨迹追踪中…"
    }
}
