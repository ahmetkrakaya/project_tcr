package com.rivlus.project_tcr

import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.contracts.HealthPermissionsRequestContract
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred

class MainActivity : FlutterFragmentActivity() {

    private var healthConnectChannel: MethodChannel? = null

    private val healthConnectPermissions: Set<String> = setOf(
        "android.permission.health.WRITE_PLANNED_EXERCISE",
        "android.permission.health.READ_PLANNED_EXERCISE"
    )

    @Volatile
    private var pendingHealthConnectResult: CompletableDeferred<Set<String>>? = null

    private val healthConnectPermissionLauncher: ActivityResultLauncher<Set<String>> =
        registerForActivityResult(
            HealthPermissionsRequestContract("com.google.android.apps.healthdata")
        ) { granted: Set<String> ->
            pendingHealthConnectResult?.complete(granted)
            pendingHealthConnectResult = null
        }

    fun requestHealthConnectPermissions(): CompletableDeferred<Set<String>> {
        val deferred = CompletableDeferred<Set<String>>()
        pendingHealthConnectResult = deferred
        healthConnectPermissionLauncher.launch(healthConnectPermissions)
        return deferred
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        healthConnectChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tcr/health_connect_workout"
        ).apply {
            setMethodCallHandler(
                HealthConnectWorkoutHandler(this@MainActivity, this)
            )
        }
    }
}
