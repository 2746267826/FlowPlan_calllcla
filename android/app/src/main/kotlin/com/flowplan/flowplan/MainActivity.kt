package com.flowplan.flowplan

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.flowplan.flowplan/android_usage_stats"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsageAccessPermissionStatus" -> {
                    result.success(hasUsageAccessPermission())
                }

                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }

                "queryUsageEvents" -> {
                    val sinceMillis =
                        call.argument<Number>("sinceMillis")?.toLong()
                    val untilMillis =
                        call.argument<Number>("untilMillis")?.toLong()
                    if (sinceMillis == null || untilMillis == null) {
                        result.error(
                            "invalid_args",
                            "Missing sinceMillis or untilMillis.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    result.success(
                        queryUsageEvents(
                            sinceMillis = sinceMillis,
                            untilMillis = untilMillis,
                        ),
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccessPermission(): Boolean {
        val appOps =
            getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName,
                )
            }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        startActivity(
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    private fun queryUsageEvents(
        sinceMillis: Long,
        untilMillis: Long,
    ): List<Map<String, Any?>> {
        if (!hasUsageAccessPermission()) {
            return emptyList()
        }

        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val usageEvents = usageStatsManager.queryEvents(sinceMillis, untilMillis)
        val packageManager = applicationContext.packageManager
        val event = UsageEvents.Event()
        val results = mutableListOf<Map<String, Any?>>()

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val packageName = event.packageName ?: continue
            val eventType = usageEventTypeName(event.eventType) ?: continue
            results.add(
                mapOf(
                    "timestampMillis" to event.timeStamp,
                    "packageName" to packageName,
                    "className" to event.className,
                    "eventType" to eventType,
                    "appLabel" to resolveAppLabel(packageManager, packageName),
                ),
            )
        }

        return results
    }

    private fun usageEventTypeName(eventType: Int): String? {
        return when (eventType) {
            UsageEvents.Event.ACTIVITY_RESUMED -> "activity_resumed"
            UsageEvents.Event.ACTIVITY_PAUSED -> "activity_paused"
            UsageEvents.Event.ACTIVITY_STOPPED -> "activity_stopped"
            UsageEvents.Event.MOVE_TO_FOREGROUND -> "move_to_foreground"
            UsageEvents.Event.MOVE_TO_BACKGROUND -> "move_to_background"
            else -> null
        }
    }

    private fun resolveAppLabel(
        packageManager: PackageManager,
        packageName: String,
    ): String {
        return try {
            val applicationInfo =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        packageName,
                        PackageManager.ApplicationInfoFlags.of(0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getApplicationInfo(packageName, 0)
                }
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }
}
