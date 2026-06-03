package com.example.lifeease

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone

private const val CHANNEL = "lifeease/reminder_native"
private const val PREFS_NAME = "lifeease_native_reminder_speech"
private const val STORED_ALARMS_KEY = "scheduled_alarm_ids"
private const val PENDING_ACTIONS_KEY = "pending_actions"
private const val EXTRA_ALARM_ID = "alarmId"
private const val EXTRA_REMINDER_ID = "reminderId"
private const val EXTRA_TRIGGER_AT_MILLIS = "triggerAtMillis"
private const val EXTRA_TITLE = "title"
private const val EXTRA_BODY = "body"
private const val EXTRA_TEXT = "text"
private const val EXTRA_LANGUAGE_CODE = "languageCode"
private const val EXTRA_ACTION_ID = "actionId"
private const val LOCATION_PERMISSION_REQUEST = 4101
private const val REMINDER_CHANNEL_ID = "lifeease_reminders_silent_v1"
private const val REMINDER_CHANNEL_NAME = "Reminder Alerts"
private const val ACTION_MARK_DONE = "mark_done"
private const val ACTION_SKIP_OCCURRENCE = "skip_occurrence"

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTimeZoneName" -> result.success(deviceTimeZoneId())
                "getCurrentLocation" -> currentLocation(result)
                "requestReminderReliabilityAccess" -> {
                    requestReminderReliabilityAccess()
                    result.success(null)
                }
                "drainNativeReminderActions" -> {
                    result.success(ReminderNativeActionStore.drain(applicationContext))
                }
                "speakReminderNow" -> {
                    val alarmId = call.argument<Int>(EXTRA_ALARM_ID)
                    val text = call.argument<String>(EXTRA_TEXT)
                    val languageCode = call.argument<String>(EXTRA_LANGUAGE_CODE) ?: "en"

                    if (alarmId == null || text.isNullOrBlank()) {
                        result.error("invalid_args", "Missing reminder speech arguments.", null)
                        return@setMethodCallHandler
                    }

                    ReminderSpeechPlayer.speak(
                        context = applicationContext,
                        alarmId = alarmId,
                        text = text,
                        languageCode = languageCode,
                    )
                    result.success(null)
                }
                "scheduleSpeechAlarm" -> {
                    val alarmId = call.argument<Int>(EXTRA_ALARM_ID)
                    val triggerAtMillis = call.argument<Number>(EXTRA_TRIGGER_AT_MILLIS)?.toLong()
                    val reminderId = call.argument<String>(EXTRA_REMINDER_ID).orEmpty()
                    val title = call.argument<String>(EXTRA_TITLE) ?: "LifeEase Reminder"
                    val body = call.argument<String>(EXTRA_BODY).orEmpty()
                    val text = call.argument<String>(EXTRA_TEXT)
                    val languageCode = call.argument<String>(EXTRA_LANGUAGE_CODE) ?: "en"

                    if (alarmId == null || triggerAtMillis == null || text.isNullOrBlank()) {
                        result.error("invalid_args", "Missing reminder speech alarm arguments.", null)
                        return@setMethodCallHandler
                    }

                    ReminderSpeechScheduler.schedule(
                        context = applicationContext,
                        alarmId = alarmId,
                        triggerAtMillis = triggerAtMillis,
                        reminderId = reminderId,
                        title = title,
                        body = body,
                        text = text,
                        languageCode = languageCode,
                    )
                    result.success(null)
                }
                "cancelSpeechAlarm" -> {
                    val alarmId = call.argument<Int>(EXTRA_ALARM_ID)
                    if (alarmId == null) {
                        result.error("invalid_args", "Missing reminder speech alarm id.", null)
                        return@setMethodCallHandler
                    }

                    ReminderSpeechScheduler.cancel(applicationContext, alarmId)
                    result.success(null)
                }
                "playAudioFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("invalid_args", "Missing audio file path.", null)
                        return@setMethodCallHandler
                    }
                    ReminderSpeechPlayer.stop(null)
                    val durationMs = ReminderAudioPlayer.play(applicationContext, filePath)
                    result.success(durationMs)
                }
                "stopAudio" -> {
                    ReminderAudioPlayer.stop()
                    ReminderSpeechPlayer.stop(null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deviceTimeZoneId(): String {
        val zoneId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ZoneId.systemDefault().id
        } else {
            TimeZone.getDefault().id
        }

        return when (zoneId.uppercase(Locale.US)) {
            "GMT", "UTC", "UT" -> "UTC"
            else -> zoneId
        }
    }

    private fun currentLocation(result: MethodChannel.Result) {
        val fineGranted = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted && !coarseGranted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
                LOCATION_PERMISSION_REQUEST,
            )
            result.error("permission_required", "Location permission is required.", null)
            return
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = manager.getProviders(true)
        val bestLocation = providers
            .mapNotNull { provider -> lastKnownLocation(manager, provider) }
            .maxByOrNull { it.time }

        if (bestLocation == null) {
            result.error("location_unavailable", "No current location is available.", null)
            return
        }

        result.success(
            mapOf(
                "latitude" to bestLocation.latitude,
                "longitude" to bestLocation.longitude,
            ),
        )
    }

    private fun lastKnownLocation(manager: LocationManager, provider: String): Location? {
        return try {
            manager.getLastKnownLocation(provider)
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun requestReminderReliabilityAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                try {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                            data = Uri.parse("package:$packageName")
                        },
                    )
                } catch (_: Exception) {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    })
                }
                return
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        },
                    )
                } catch (_: Exception) {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        }
    }
}

class ReminderSpeechReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, 0)
        val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID).orEmpty()
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "LifeEase Reminder"
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        val languageCode = intent.getStringExtra(EXTRA_LANGUAGE_CODE) ?: "en"
        if (alarmId == 0 || text.isBlank()) return

        ReminderSpeechScheduler.removeStoredAlarm(context, alarmId)
        ReminderNotificationFallback.show(
            context = context.applicationContext,
            alarmId = alarmId,
            reminderId = reminderId,
            title = title,
            body = body.ifBlank { text },
        )
        ReminderSpeechPlayer.speak(
            context = context.applicationContext,
            alarmId = alarmId,
            text = text,
            languageCode = languageCode,
        )
    }
}

class ReminderSpeechRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderSpeechScheduler.rescheduleStoredAlarms(context.applicationContext)
    }
}

class ReminderNativeActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, 0)
        val reminderId = intent.getStringExtra(EXTRA_REMINDER_ID).orEmpty()
        val actionId = intent.getStringExtra(EXTRA_ACTION_ID).orEmpty()
        if (alarmId == 0 || reminderId.isBlank() || actionId.isBlank()) return

        ReminderSpeechScheduler.cancel(context.applicationContext, alarmId)
        NotificationManagerCompat.from(context.applicationContext).cancel(alarmId)
        ReminderNativeActionStore.add(
            context = context.applicationContext,
            alarmId = alarmId,
            reminderId = reminderId,
            actionId = actionId,
        )
    }
}

private object ReminderNativeActionStore {
    fun add(context: Context, alarmId: Int, reminderId: String, actionId: String) {
        val prefs = prefs(context)
        val actions = JSONArray(prefs.getString(PENDING_ACTIONS_KEY, "[]") ?: "[]")
        actions.put(
            JSONObject()
                .put(EXTRA_ALARM_ID, alarmId)
                .put(EXTRA_REMINDER_ID, reminderId)
                .put(EXTRA_ACTION_ID, actionId)
                .put("handledAtMillis", System.currentTimeMillis()),
        )
        prefs.edit().putString(PENDING_ACTIONS_KEY, actions.toString()).apply()
    }

    fun drain(context: Context): List<Map<String, Any>> {
        val prefs = prefs(context)
        val rawActions = prefs.getString(PENDING_ACTIONS_KEY, "[]") ?: "[]"
        prefs.edit().remove(PENDING_ACTIONS_KEY).apply()

        val actions = JSONArray(rawActions)
        val drained = mutableListOf<Map<String, Any>>()
        for (index in 0 until actions.length()) {
            val action = actions.optJSONObject(index) ?: continue
            drained.add(
                mapOf(
                    EXTRA_ALARM_ID to action.optInt(EXTRA_ALARM_ID),
                    EXTRA_REMINDER_ID to action.optString(EXTRA_REMINDER_ID),
                    EXTRA_ACTION_ID to action.optString(EXTRA_ACTION_ID),
                ),
            )
        }
        return drained
    }

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
}

private object ReminderSpeechScheduler {
    fun schedule(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        reminderId: String,
        title: String,
        body: String,
        text: String,
        languageCode: String,
    ) {
        if (triggerAtMillis <= System.currentTimeMillis()) return

        val intent = speechIntent(context, alarmId).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_REMINDER_ID, reminderId)
            putExtra(EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_TEXT, text)
            putExtra(EXTRA_LANGUAGE_CODE, languageCode)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val showIntent = PendingIntent.getActivity(
                context,
                alarmId,
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent),
                pendingIntent,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }

        storeAlarm(context, alarmId, triggerAtMillis, reminderId, title, body, text, languageCode)
    }

    fun cancel(context: Context, alarmId: Int) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            speechIntent(context, alarmId),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }

        removeStoredAlarm(context, alarmId)
        ReminderSpeechPlayer.stop(alarmId)
        ReminderAudioPlayer.stop()
    }

    fun rescheduleStoredAlarms(context: Context) {
        val prefs = prefs(context)
        val now = System.currentTimeMillis()
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toList()
        for (alarmIdText in alarmIds) {
            val alarmId = alarmIdText.toIntOrNull() ?: continue
            val triggerAtMillis = prefs.getLong(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS), 0L)
            val reminderId = prefs.getString(alarmKey(alarmId, EXTRA_REMINDER_ID), "") ?: ""
            val title = prefs.getString(alarmKey(alarmId, EXTRA_TITLE), "LifeEase Reminder")
                ?: "LifeEase Reminder"
            val body = prefs.getString(alarmKey(alarmId, EXTRA_BODY), "") ?: ""
            val text = prefs.getString(alarmKey(alarmId, EXTRA_TEXT), null)
            val languageCode = prefs.getString(alarmKey(alarmId, EXTRA_LANGUAGE_CODE), "en") ?: "en"

            if (triggerAtMillis <= now || text.isNullOrBlank()) {
                removeStoredAlarm(context, alarmId)
                continue
            }

            schedule(context, alarmId, triggerAtMillis, reminderId, title, body, text, languageCode)
        }
    }

    fun removeStoredAlarm(context: Context, alarmId: Int) {
        val prefs = prefs(context)
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toMutableSet()
        alarmIds.remove(alarmId.toString())
        prefs.edit()
            .putStringSet(STORED_ALARMS_KEY, alarmIds)
            .remove(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS))
            .remove(alarmKey(alarmId, EXTRA_REMINDER_ID))
            .remove(alarmKey(alarmId, EXTRA_TITLE))
            .remove(alarmKey(alarmId, EXTRA_BODY))
            .remove(alarmKey(alarmId, EXTRA_TEXT))
            .remove(alarmKey(alarmId, EXTRA_LANGUAGE_CODE))
            .apply()
    }

    private fun storeAlarm(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        reminderId: String,
        title: String,
        body: String,
        text: String,
        languageCode: String,
    ) {
        val prefs = prefs(context)
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toMutableSet()
        alarmIds.add(alarmId.toString())
        prefs.edit()
            .putStringSet(STORED_ALARMS_KEY, alarmIds)
            .putLong(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS), triggerAtMillis)
            .putString(alarmKey(alarmId, EXTRA_REMINDER_ID), reminderId)
            .putString(alarmKey(alarmId, EXTRA_TITLE), title)
            .putString(alarmKey(alarmId, EXTRA_BODY), body)
            .putString(alarmKey(alarmId, EXTRA_TEXT), text)
            .putString(alarmKey(alarmId, EXTRA_LANGUAGE_CODE), languageCode)
            .apply()
    }

    private fun speechIntent(context: Context, alarmId: Int): Intent {
        return Intent(context, ReminderSpeechReceiver::class.java).apply {
            action = "com.example.lifeease.REMINDER_SPEECH.$alarmId"
        }
    }

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun alarmKey(alarmId: Int, suffix: String): String = "$alarmId.$suffix"
}

private object ReminderNotificationFallback {
    fun show(
        context: Context,
        alarmId: Int,
        reminderId: String,
        title: String,
        body: String,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            context,
            alarmId,
            launchIntent.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_REMINDER_ID, reminderId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, REMINDER_CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setVibrate(longArrayOf(0, 500, 250, 500))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(
                0,
                "Done",
                actionIntent(context, alarmId, reminderId, ACTION_MARK_DONE),
            )
            .addAction(
                0,
                "Skip",
                actionIntent(context, alarmId, reminderId, ACTION_SKIP_OCCURRENCE),
            )
            .build()

        NotificationManagerCompat.from(context).notify(alarmId, notification)
    }

    private fun actionIntent(
        context: Context,
        alarmId: Int,
        reminderId: String,
        actionId: String,
    ): PendingIntent {
        val requestCode = 31 * alarmId + actionId.hashCode()
        val intent = Intent(context, ReminderNativeActionReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_REMINDER_ID, reminderId)
            putExtra(EXTRA_ACTION_ID, actionId)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            REMINDER_CHANNEL_ID,
            REMINDER_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Alerts for scheduled LifeEase reminders."
            enableVibration(true)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }
}

private object ReminderSpeechPlayer {
    private var activeTts: TextToSpeech? = null
    private var activeAlarmId: Int? = null
    private var lastStartedAlarmId: Int? = null
    private var lastStartedAtMillis: Long = 0L

    fun speak(context: Context, alarmId: Int, text: String, languageCode: String) {
        val now = System.currentTimeMillis()
        if (lastStartedAlarmId == alarmId && now - lastStartedAtMillis < 10_000L) return

        stop(activeAlarmId)
        lastStartedAlarmId = alarmId
        lastStartedAtMillis = now
        activeAlarmId = alarmId

        var tts: TextToSpeech? = null
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status != TextToSpeech.SUCCESS) {
                tts?.shutdown()
                return@TextToSpeech
            }

            val engine = tts ?: return@TextToSpeech
            activeTts = engine
            engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            val languageStatus = engine.setLanguage(localeFor(languageCode))
            if (languageStatus == TextToSpeech.LANG_MISSING_DATA ||
                languageStatus == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                engine.setLanguage(Locale.US)
            }
            engine.setSpeechRate(0.9f)
            engine.setPitch(1.0f)
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    stop(alarmId)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    stop(alarmId)
                }
            })
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "lifeease_reminder_$alarmId")
        }
    }

    fun stop(alarmId: Int?) {
        if (alarmId != null && activeAlarmId != null && alarmId != activeAlarmId) return

        activeTts?.stop()
        activeTts?.shutdown()
        activeTts = null
        activeAlarmId = null
    }

    private fun localeFor(languageCode: String): Locale {
        return if (languageCode.equals("tl", ignoreCase = true)) {
            Locale.forLanguageTag("fil-PH")
        } else {
            Locale.US
        }
    }
}

private object ReminderAudioPlayer {
    private var mediaPlayer: MediaPlayer? = null

    fun play(context: Context, filePath: String): Int {
        stop()
        return try {
            var durationMs = 0
            val player = MediaPlayer().apply {
                setDataSource(filePath)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                prepare()
                durationMs = duration
                start()
                setOnCompletionListener {
                    stop()
                }
            }
            mediaPlayer = player
            durationMs
        } catch (e: Exception) {
            e.printStackTrace()
            0
        }
    }

    fun stop() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (e: Exception) {
            // ignore
        } finally {
            mediaPlayer = null
        }
    }
}
