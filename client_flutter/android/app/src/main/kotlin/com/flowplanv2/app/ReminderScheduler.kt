package com.flowplanv2.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object ReminderScheduler {
    private const val PREFS_NAME = "flowplanv2_reminders"
    private const val REMINDERS_KEY = "scheduled_reminders"

    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        persist: Boolean,
    ): Boolean {
        if (triggerAtMillis <= System.currentTimeMillis()) {
            if (persist) {
                remove(context, id)
            }
            return false
        }
        if (!canScheduleExactAlarms(context)) {
            return false
        }

        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = reminderIntent(
            context = context,
            id = id,
            triggerAtMillis = triggerAtMillis,
            title = title,
            body = body,
        )
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            @Suppress("DEPRECATION")
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }

        if (persist) {
            upsert(
                context = context,
                reminder = ScheduledReminder(
                    id = id,
                    triggerAtMillis = triggerAtMillis,
                    title = title,
                    body = body,
                ),
            )
        }
        return true
    }

    fun cancelAll(context: Context) {
        val reminders = load(context)
        for (reminder in reminders) {
            cancel(context, reminder.id)
        }
        save(context, emptyList())
    }

    fun pendingCount(context: Context): Int {
        prunePast(context)
        return load(context).size
    }

    fun remove(context: Context, id: Int) {
        cancel(context, id)
        save(context, load(context).filterNot { it.id == id })
    }

    fun reschedulePersisted(context: Context) {
        prunePast(context)
        val reminders = load(context)
        for (reminder in reminders) {
            schedule(
                context = context,
                id = reminder.id,
                triggerAtMillis = reminder.triggerAtMillis,
                title = reminder.title,
                body = reminder.body,
                persist = false,
            )
        }
    }

    private fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun cancel(context: Context, id: Int) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            id,
            reminderIntent(
                context = context,
                id = id,
                triggerAtMillis = 0L,
                title = "",
                body = "",
            ),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun reminderIntent(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
    ): Intent {
        return Intent(context, ReminderAlarmReceiver::class.java).apply {
            action = "com.flowplanv2.app.REMINDER_ALARM"
            putExtra(ReminderAlarmReceiver.EXTRA_ID, id)
            putExtra(ReminderAlarmReceiver.EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
            putExtra(ReminderAlarmReceiver.EXTRA_TITLE, title)
            putExtra(ReminderAlarmReceiver.EXTRA_BODY, body)
        }
    }

    private fun upsert(context: Context, reminder: ScheduledReminder) {
        val reminders = load(context)
            .filterNot { it.id == reminder.id }
            .plus(reminder)
            .sortedBy { it.triggerAtMillis }
        save(context, reminders)
    }

    private fun prunePast(context: Context) {
        val now = System.currentTimeMillis()
        val reminders = load(context).filter { it.triggerAtMillis > now }
        save(context, reminders)
    }

    private fun load(context: Context): List<ScheduledReminder> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(REMINDERS_KEY, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            val reminders = mutableListOf<ScheduledReminder>()
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val id = item.optInt("id")
                val triggerAtMillis = item.optLong("triggerAtMillis")
                val title = item.optString("title")
                val body = item.optString("body")
                if (id != 0 && triggerAtMillis > 0L && title.isNotBlank()) {
                    reminders.add(
                        ScheduledReminder(
                            id = id,
                            triggerAtMillis = triggerAtMillis,
                            title = title,
                            body = body,
                        ),
                    )
                }
            }
            reminders
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun save(context: Context, reminders: List<ScheduledReminder>) {
        val array = JSONArray()
        for (reminder in reminders) {
            array.put(
                JSONObject().apply {
                    put("id", reminder.id)
                    put("triggerAtMillis", reminder.triggerAtMillis)
                    put("title", reminder.title)
                    put("body", reminder.body)
                },
            )
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(REMINDERS_KEY, array.toString())
            .apply()
    }
}

data class ScheduledReminder(
    val id: Int,
    val triggerAtMillis: Long,
    val title: String,
    val body: String,
)
