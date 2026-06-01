package com.example.lifeease

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioAttributes
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone

private const val CHANNEL = "lifeease/reminder_native"
private const val PREFS_NAME = "lifeease_native_reminder_speech"
private const val STORED_ALARMS_KEY = "scheduled_alarm_ids"
private const val EXTRA_ALARM_ID = "alarmId"
private const val EXTRA_TRIGGER_AT_MILLIS = "triggerAtMillis"
private const val EXTRA_TEXT = "text"
private const val EXTRA_LANGUAGE_CODE = "languageCode"
private const val LOCATION_PERMISSION_REQUEST = 4101

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTimeZoneName" -> result.success(deviceTimeZoneId())
                "getCurrentLocation" -> currentLocation(result)
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
}

class ReminderSpeechReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, 0)
        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        val languageCode = intent.getStringExtra(EXTRA_LANGUAGE_CODE) ?: "en"
        if (alarmId == 0 || text.isBlank()) return

        ReminderSpeechScheduler.removeStoredAlarm(context, alarmId)
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

private object ReminderSpeechScheduler {
    fun schedule(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        text: String,
        languageCode: String,
    ) {
        if (triggerAtMillis <= System.currentTimeMillis()) return

        val intent = speechIntent(context, alarmId).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }

        storeAlarm(context, alarmId, triggerAtMillis, text, languageCode)
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
    }

    fun rescheduleStoredAlarms(context: Context) {
        val prefs = prefs(context)
        val now = System.currentTimeMillis()
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toList()
        for (alarmIdText in alarmIds) {
            val alarmId = alarmIdText.toIntOrNull() ?: continue
            val triggerAtMillis = prefs.getLong(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS), 0L)
            val text = prefs.getString(alarmKey(alarmId, EXTRA_TEXT), null)
            val languageCode = prefs.getString(alarmKey(alarmId, EXTRA_LANGUAGE_CODE), "en") ?: "en"

            if (triggerAtMillis <= now || text.isNullOrBlank()) {
                removeStoredAlarm(context, alarmId)
                continue
            }

            schedule(context, alarmId, triggerAtMillis, text, languageCode)
        }
    }

    fun removeStoredAlarm(context: Context, alarmId: Int) {
        val prefs = prefs(context)
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toMutableSet()
        alarmIds.remove(alarmId.toString())
        prefs.edit()
            .putStringSet(STORED_ALARMS_KEY, alarmIds)
            .remove(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS))
            .remove(alarmKey(alarmId, EXTRA_TEXT))
            .remove(alarmKey(alarmId, EXTRA_LANGUAGE_CODE))
            .apply()
    }

    private fun storeAlarm(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        text: String,
        languageCode: String,
    ) {
        val prefs = prefs(context)
        val alarmIds = prefs.getStringSet(STORED_ALARMS_KEY, emptySet()).orEmpty().toMutableSet()
        alarmIds.add(alarmId.toString())
        prefs.edit()
            .putStringSet(STORED_ALARMS_KEY, alarmIds)
            .putLong(alarmKey(alarmId, EXTRA_TRIGGER_AT_MILLIS), triggerAtMillis)
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

private object ReminderSpeechPlayer {
    private var activeTts: TextToSpeech? = null
    private var activeAlarmId: Int? = null
    private var lastStartedAlarmId: Int? = null
    private var lastStartedAtMillis: Long = 0L

    fun speak(context: Context, alarmId: Int, text: String, languageCode: String) {
        val now = System.currentTimeMillis()
        if (lastStartedAlarmId == alarmId && now - lastStartedAtMillis < 60_000L) return

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
