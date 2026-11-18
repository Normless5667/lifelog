package com.lifelog.lifelog

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val channelName = "com.lifelog/reminders"
    private val notifChannelId = "course_reminders_v2"
    private val restAlarmReqCode = 2001
    private val pickJsonReqCode = 905
    private var pendingJsonResult: MethodChannel.Result? = null
    private var reminderChannel: MethodChannel? = null
    private var sensorManager: SensorManager? = null
    private var stepSensorSupported: Boolean = false
    private var stepListenerRegistered: Boolean = false
    private var latestRawStepCounter: Int = -1
    private var lastStepEventHandledMs: Long = 0L
    private var lastStepWidgetSyncMs: Long = 0L

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        LifeAssistantWidgetProvider.refreshAll(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        LifeAssistantWidgetProvider.refreshAll(this)
    }

    override fun onResume() {
        super.onResume()
        initStepSensor()
    }

    override fun onStop() {
        unregisterStepSensor()
        try {
            reminderChannel?.invokeMethod("syncWidgetOnStop", null)
        } catch (_: Exception) {}
        LifeAssistantWidgetProvider.refreshAll(this)
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureChannelCreated()
        initStepSensor()
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        reminderChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                                != PackageManager.PERMISSION_GRANTED
                            ) {
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    901
                                )
                            }
                        }
                        ensureChannelCreated()
                        result.success(true)
                    }
                    "checkNotificationStatus" -> {
                        ensureChannelCreated()
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val enabled = nm.areNotificationsEnabled()
                        var importance = 4
                        var vibrate = true
                        var sound = true
                        var channelNameStr = "生活助手·强提醒通知"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val ch = nm.getNotificationChannel(notifChannelId)
                            if (ch != null) {
                                importance = ch.importance
                                vibrate = ch.shouldVibrate()
                                sound = ch.sound != null
                                channelNameStr = ch.name?.toString() ?: channelNameStr
                            }
                        }
                        val exactAlarm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.canScheduleExactAlarms()
                        } else true
                        val brand = "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
                        result.success(
                            mapOf(
                                "enabled" to enabled,
                                "importance" to importance,
                                "vibrate" to vibrate,
                                "sound" to sound,
                                "exactAlarm" to exactAlarm,
                                "channelId" to notifChannelId,
                                "channelName" to channelNameStr,
                                "device" to brand
                            )
                        )
                    }
                    "openAppNotificationSettings" -> {
                        ensureChannelCreated()
                        try {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                        } catch (_: Exception) {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(fallback)
                        }
                        result.success(true)
                    }
                    "openNotificationSettings" -> {
                        ensureChannelCreated()
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                    putExtra(Settings.EXTRA_CHANNEL_ID, notifChannelId)
                                }
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            }
                            startActivity(intent)
                        } catch (_: Exception) {
                            val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(fallback)
                        }
                        result.success(true)
                    }
                    "scheduleAll" -> {
                        val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        scheduleAlarms(items)
                        result.success(items.size)
                    }
                    "testNotification" -> {
                        val i = Intent(this, CourseReminderReceiver::class.java).apply {
                            putExtra("id", 99999)
                            putExtra("title", "🔔 上课提醒测试（强震动+横幅）")
                            putExtra("body", "Database Principles and Applications · 09:00 @ E.3-8 Classroom")
                        }
                        sendBroadcast(i)
                        result.success(true)
                    }
                    "setSystemClockAlarm" -> {
                        val hour = call.argument<Int>("hour") ?: 8
                        val minute = call.argument<Int>("minute") ?: 45
                        val message = call.argument<String>("message") ?: "上课提醒"
                        val skipUi = call.argument<Boolean>("skipUi") ?: false
                        try {
                            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(AlarmClock.EXTRA_HOUR, hour)
                                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                                putExtra(AlarmClock.EXTRA_VIBRATE, true)
                                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ALARM_ERR", e.message, null)
                        }
                    }
                    "scheduleRestAlarm" -> {
                        val seconds = call.argument<Int>("seconds") ?: 90
                        val title = call.argument<String>("title") ?: "⏱️ 组间休息结束！"
                        val body = call.argument<String>("body") ?: "准备开始下一组训练吧 💪"
                        val triggerAt = System.currentTimeMillis() + seconds * 1000L
                        scheduleSingleAlarm(restAlarmReqCode, triggerAt, title, body)
                        result.success(true)
                    }
                    "cancelRestAlarm" -> {
                        cancelSingleAlarm(restAlarmReqCode)
                        result.success(true)
                    }
                    "vibrateShort" -> {
                        triggerVibration(longArrayOf(0, 400, 150, 500))
                        result.success(true)
                    }
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    "requestStepPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION)
                                != PackageManager.PERMISSION_GRANTED
                            ) {
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                                    902
                                )
                            }
                        }
                        initStepSensor()
                        result.success(true)
                    }
                    "getStepSensorState" -> {
                        initStepSensor()
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) ==
                                PackageManager.PERMISSION_GRANTED
                        } else true
                        result.success(
                            mapOf(
                                "supported" to stepSensorSupported,
                                "granted" to granted,
                                "rawSteps" to latestRawStepCounter
                            )
                        )
                    }
                    "updateHomeWidget" -> {
                        val course = call.argument<String>("course") ?: "📅 今日暂无课程"
                        val calorie = call.argument<String>("calorie") ?: "🔥 剩余热量：2000 kcal"
                        val step = call.argument<String>("step") ?: "👟 今日步数：0 步"
                        LifeAssistantWidgetProvider.saveAndRefresh(this, course, calorie, step)
                        result.success(true)
                    }
                    "requestPinHomeWidget" -> {
                        var pinned = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                            if (mgr.isRequestPinAppWidgetSupported) {
                                val provider = android.content.ComponentName(this, LifeAssistantWidgetProvider::class.java)
                                pinned = mgr.requestPinAppWidget(provider, null, null)
                            }
                        }
                        result.success(pinned)
                    }
                    "pickJsonFile" -> {
                        pendingJsonResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, pickJsonReqCode)
                    }
                    "openSystemWeather" -> {
                        result.success(openSystemWeatherApp())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureChannelCreated() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val pattern = longArrayOf(0, 500, 200, 500, 200, 600)
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val ch = NotificationChannel(
                notifChannelId,
                "生活助手·强提醒通知",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "上课、校车、天气与组间休息到时强震动横幅提醒（请在系统设置中保持重要通知与震动开启）"
                enableVibration(true)
                vibrationPattern = pattern
                enableLights(true)
                setSound(soundUri, audioAttrs)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun triggerVibration(pattern: LongArray) {
        try {
            val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
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
    }

    private fun scheduleSingleAlarm(reqCode: Int, triggerAt: Long, title: String, body: String) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val intent = Intent(this, CourseReminderReceiver::class.java).apply {
            putExtra("id", reqCode)
            putExtra("title", title)
            putExtra("body", body)
        }
        val pi = PendingIntent.getBroadcast(this, reqCode, intent, flags)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        }
    }

    private fun cancelSingleAlarm(reqCode: Int) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val cancelIntent = Intent(this, CourseReminderReceiver::class.java)
        val pi = PendingIntent.getBroadcast(this, reqCode, cancelIntent, flags)
        am.cancel(pi)
    }

    private fun scheduleAlarms(items: List<Map<String, Any>>) {
        for (reqCode in 1000..1150) {
            cancelSingleAlarm(reqCode)
        }
        val now = System.currentTimeMillis()
        for ((idx, item) in items.withIndex()) {
            val reqCode = 1000 + idx
            if (reqCode > 1250) break
            val triggerAt = (item["triggerAt"] as? Number)?.toLong() ?: continue
            if (triggerAt <= now) continue
            val title = item["title"]?.toString() ?: "上课提醒"
            val body = item["body"]?.toString() ?: ""
            scheduleSingleAlarm(reqCode, triggerAt, title, body)
        }
    }

    private fun initStepSensor() {
        try {
            if (sensorManager == null) {
                sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            }
            val sm = sensorManager ?: return
            val stepSensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            if (stepSensor != null) {
                stepSensorSupported = true
                if (!stepListenerRegistered) {
                    // 使用 SENSOR_DELAY_NORMAL + 30 秒硬件批处理延迟，大幅减少传感器中断唤醒
                    sm.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_NORMAL, 30_000_000)
                    stepListenerRegistered = true
                }
            } else {
                stepSensorSupported = false
            }
        } catch (_: Exception) {
            stepSensorSupported = false
        }
    }

    private fun unregisterStepSensor() {
        try {
            if (stepListenerRegistered) {
                sensorManager?.unregisterListener(this)
                stepListenerRegistered = false
            }
        } catch (_: Exception) {}
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER && event.values.isNotEmpty()) {
            val raw = event.values[0].toInt()
            // 首次读取立即记录，后续节流到至少 30 秒处理一次，杜绝高频唤醒
            val now = System.currentTimeMillis()
            if (latestRawStepCounter < 0 || now - lastStepEventHandledMs >= 30_000L) {
                latestRawStepCounter = raw
                lastStepEventHandledMs = now
            }
            if (now - lastStepWidgetSyncMs >= 5 * 60 * 1000L) {
                lastStepWidgetSyncMs = now
                try {
                    reminderChannel?.invokeMethod("onStepSensorThrottled", latestRawStepCounter)
                } catch (_: Exception) {}
            }
        }
    }

    private fun openSystemWeatherApp(): Boolean {
        val catIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_APP_WEATHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            if (catIntent.resolveActivity(packageManager) != null) {
                startActivity(catIntent)
                return true
            }
        } catch (_: Exception) {}

        val oemPackages = listOf(
            "com.coloros.weather2",
            "com.heytap.weather",
            "com.coloros.weather",
            "net.oneplus.weather",
            "com.miui.weather2",
            "com.vivo.weather",
            "com.huawei.android.totemweather",
            "com.hihonor.android.totemweather",
            "com.sec.android.daemonapp",
            "com.google.android.apps.weather",
            "com.meizu.flyme.weather",
            "com.lenovo.weather"
        )
        for (pkg in oemPackages) {
            try {
                val launch = packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    return true
                }
            } catch (_: Exception) {}
        }
        return false
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickJsonReqCode) {
            val res = pendingJsonResult
            pendingJsonResult = null
            if (res == null) return
            if (resultCode != RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            try {
                val uri = data.data!!
                val text = contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                res.success(text)
            } catch (e: Exception) {
                res.error("READ_ERR", e.message, null)
            }
        }
    }
}
