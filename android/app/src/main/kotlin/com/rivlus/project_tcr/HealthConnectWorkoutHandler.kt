package com.rivlus.project_tcr

import android.app.Activity
import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSegment
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.PlannedExerciseBlock
import androidx.health.connect.client.records.PlannedExerciseSessionRecord
import androidx.health.connect.client.records.PlannedExerciseStep
import androidx.health.connect.client.records.ExerciseCompletionGoal
import androidx.health.connect.client.records.ExercisePerformanceTarget
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Length
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Health Connect MethodChannel handler - antrenman programlarını Health Connect'e
 * PlannedExerciseSessionRecord olarak yazar.
 *
 * TCR workout definition: warmup, main, recovery, cooldown segmentleri ve repeat blokları.
 * Health Connect: PlannedExerciseBlock + PlannedExerciseStep (EXERCISE_PHASE_*).
 */
class HealthConnectWorkoutHandler(
    private val activity: Activity,
    private val channel: MethodChannel
) : MethodChannel.MethodCallHandler {

    private val context: Context get() = activity

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> scope.launch {
                try {
                    val supported = isSupported()
                    result.success(supported)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "requestAuthorization" -> scope.launch {
                try {
                    val status = requestAuthorization()
                    result.success(status)
                } catch (e: Exception) {
                    result.error("auth_failed", e.message, null)
                }
            }
            "getAuthorizationStatus" -> scope.launch {
                try {
                    val status = getAuthorizationStatus()
                    result.success(status)
                } catch (e: Exception) {
                    result.success("unknown")
                }
            }
            "syncScheduledWorkouts" -> scope.launch {
                try {
                    @Suppress("UNCHECKED_CAST")
                    val payloads = (call.arguments as? Map<String, Any>)?.get("payloads") as? List<Map<String, Any>>
                        ?: emptyList()
                    syncScheduledWorkouts(payloads)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("sync_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun isSupported(): Boolean = withContext(Dispatchers.IO) {
        try {
            val providerPackage = "com.google.android.apps.healthdata"
            val sdkStatus = HealthConnectClient.getSdkStatus(context, providerPackage)
            if (sdkStatus == HealthConnectClient.SDK_UNAVAILABLE ||
                sdkStatus == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED) {
                return@withContext false
            }
            // PlannedExercise 1.1.0+ ile birlikte gelir; SDK kullanılabilirse destekleniyor kabul ediyoruz.
            true
        } catch (e: Exception) {
            false
        }
    }

    private val permissions: Set<String> = setOf(
        "android.permission.health.WRITE_PLANNED_EXERCISE",
        "android.permission.health.READ_PLANNED_EXERCISE"
    )

    private suspend fun requestAuthorization(): String = withContext(Dispatchers.Main) {
        try {
            val deferred = (activity as? com.rivlus.project_tcr.MainActivity)?.requestHealthConnectPermissions()
                ?: return@withContext "denied"
            val granted: Set<String> = deferred.await()
            val allGranted = permissions.all { it in granted }
            if (allGranted) "authorized" else "denied"
        } catch (e: Exception) {
            "denied"
        }
    }

    private suspend fun getAuthorizationStatus(): String = withContext(Dispatchers.IO) {
        try {
            val client = HealthConnectClient.getOrCreate(context)
            val granted: Set<String> = client.permissionController.getGrantedPermissions()
            val allGranted = permissions.all { it in granted }
            if (allGranted) "authorized" else "denied"
        } catch (e: Exception) {
            "unknown"
        }
    }

    private suspend fun syncScheduledWorkouts(payloads: List<Map<String, Any>>) = withContext(Dispatchers.IO) {
        val client = HealthConnectClient.getOrCreate(context)
        val granted: Set<String> = client.permissionController.getGrantedPermissions()
        if (!permissions.all { it in granted }) {
            throw SecurityException("Health Connect PlannedExercise izinleri verilmedi")
        }

        for (p in payloads) {
            val id = p["id"] as? String ?: continue
            val title = p["title"] as? String ?: "Antrenman"
            val scheduledAtRaw = p["scheduledAt"] as? String ?: continue
            val definition = p["definition"] as? Map<String, Any> ?: continue

            val scheduledAt = try {
                Instant.parse(scheduledAtRaw)
            } catch (e: Exception) {
                continue
            }

            val blocks = parseDefinitionToBlocks(definition)
            if (blocks.isEmpty()) continue

            val (totalDurationSeconds, blocksForRecord) = blocksToPlannedExerciseBlocks(blocks)
            val startLocalDate = scheduledAt.atZone(ZoneId.systemDefault()).toLocalDate()
            val duration = Duration.ofSeconds(totalDurationSeconds.toLong())

            val record = PlannedExerciseSessionRecord(
                startDate = startLocalDate,
                duration = duration,
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
                blocks = blocksForRecord,
                title = title,
                notes = null,
                metadata = Metadata.manualEntry()
            )

            client.insertRecords(listOf(record))
        }
    }

    /**
     * TCR definition'dan block listesi üretir.
     * Apple Watch formatıyla uyumlu: steps = [segment|repeat], segmentType, targetType, durationSeconds, distanceMeters.
     */
    private fun parseDefinitionToBlocks(definition: Map<String, Any>): List<BlockInfo> {
        @Suppress("UNCHECKED_CAST")
        val steps = definition["steps"] as? List<Map<String, Any>> ?: return emptyList()
        val blocks = mutableListOf<BlockInfo>()

        for (step in steps) {
            val type = step["type"] as? String ?: "segment"
            when (type) {
                "segment" -> {
                    val seg = step["segment"] as? Map<String, Any> ?: continue
                    val segType = seg["segmentType"] as? String ?: "main"
                    val targetType = seg["targetType"] as? String ?: "duration"
                    val durationSeconds = (seg["durationSeconds"] as? Number)?.toInt()
                    val distanceMeters = (seg["distanceMeters"] as? Number)?.toDouble()

                    val goal = when (targetType) {
                        "duration" -> if (durationSeconds != null && durationSeconds > 0) {
                            ExerciseCompletionGoal.DurationGoal(Duration.ofSeconds(durationSeconds.toLong()))
                        } else {
                            ExerciseCompletionGoal.DurationGoal(Duration.ofMinutes(1))
                        }
                        "distance" -> if (distanceMeters != null && distanceMeters > 0) {
                            ExerciseCompletionGoal.DistanceGoal(Length.meters(distanceMeters))
                        } else {
                            ExerciseCompletionGoal.DurationGoal(Duration.ofMinutes(1))
                        }
                        else -> ExerciseCompletionGoal.DurationGoal(Duration.ofMinutes(1))
                    }

                    blocks.add(BlockInfo(
                        segmentType = segType,
                        exercisePhase = mapSegmentTypeToPhase(segType),
                        completionGoal = goal,
                        performanceTargets = emptyList()
                    ))
                }
                "repeat" -> {
                    val repeatCount = (step["repeatCount"] as? Number)?.toInt() ?: 1
                    @Suppress("UNCHECKED_CAST")
                    val innerSteps = step["steps"] as? List<Map<String, Any>> ?: emptyList()
                    val innerDefinition = mapOf("steps" to innerSteps)
                    val innerBlocks = parseDefinitionToBlocks(innerDefinition)
                    if (innerBlocks.isNotEmpty()) {
                        for (i in 0 until maxOf(1, repeatCount)) {
                            blocks.addAll(innerBlocks)
                        }
                    }
                }
            }
        }
        return blocks
    }

    private fun mapSegmentTypeToPhase(segmentType: String): Int {
        return when (segmentType.lowercase()) {
            "warmup" -> PlannedExerciseStep.EXERCISE_PHASE_WARMUP
            "main" -> PlannedExerciseStep.EXERCISE_PHASE_ACTIVE
            "recovery" -> PlannedExerciseStep.EXERCISE_PHASE_RECOVERY
            "cooldown" -> PlannedExerciseStep.EXERCISE_PHASE_COOLDOWN
            else -> PlannedExerciseStep.EXERCISE_PHASE_ACTIVE
        }
    }

    private data class BlockInfo(
        val segmentType: String,
        val exercisePhase: Int,
        val completionGoal: ExerciseCompletionGoal,
        val performanceTargets: List<ExercisePerformanceTarget>
    )

    private fun blocksToPlannedExerciseBlocks(blocks: List<BlockInfo>): Pair<Int, List<PlannedExerciseBlock>> {
        var totalSeconds = 0L
        val plannedBlocks = blocks.map { info ->
            val goal = info.completionGoal
            val seconds = when (goal) {
                is ExerciseCompletionGoal.DurationGoal -> goal.duration.seconds
                is ExerciseCompletionGoal.DistanceGoal -> {
                    val length = goal.distance
                    val meters = length.inMeters
                    (meters / 1000.0 * 360).toLong()
                }
                else -> 60L
            }
            totalSeconds += seconds

            val step = PlannedExerciseStep(
                exerciseType = ExerciseSegment.EXERCISE_SEGMENT_TYPE_RUNNING,
                exercisePhase = info.exercisePhase,
                completionGoal = info.completionGoal,
                performanceTargets = info.performanceTargets,
                description = segmentDisplayName(info.segmentType)
            )
            PlannedExerciseBlock(
                repetitions = 1,
                steps = listOf(step),
                description = segmentDisplayName(info.segmentType)
            )
        }
        return Pair(totalSeconds.toInt(), plannedBlocks)
    }

    private fun segmentDisplayName(segmentType: String): String {
        return when (segmentType.lowercase()) {
            "warmup" -> "Isınma"
            "main" -> "Ana Antrenman"
            "recovery" -> "Toparlanma"
            "cooldown" -> "Soğuma"
            else -> "Antrenman"
        }
    }
}
