import Foundation
import Flutter

import WorkoutKit

enum AppleWatchBridgeError: Error {
  case invalidArgs
  case notSupported
  case authorizationDenied
}

final class AppleWatchWorkoutKitBridge {
  static let channelName = "tcr/apple_watch_workoutkit"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = AppleWatchWorkoutKitBridge()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
}

extension AppleWatchWorkoutKitBridge: FlutterPlugin {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      if #available(iOS 17.0, *) {
        result(true)
      } else {
        result(false)
      }
      return

    case "requestAuthorization":
      if #available(iOS 17.0, *) {
        Task {
          let status = await requestAuthorization()
          result(status)
        }
      } else {
        result("notSupported")
      }
      return

    case "getAuthorizationStatus":
      if #available(iOS 17.0, *) {
        result(getAuthorizationStatus())
      } else {
        result("notSupported")
      }
      return

    case "syncScheduledWorkouts":
      if #available(iOS 17.0, *) {
        guard let args = call.arguments as? [String: Any],
              let payloads = args["payloads"] as? [[String: Any]] else {
          result(FlutterError(code: "invalid_args", message: "payloads missing", details: nil))
          return
        }
        Task {
          do {
            try await syncScheduledWorkouts(payloads: payloads)
            result(nil)
          } catch {
            result(FlutterError(code: "sync_failed", message: "\(error)", details: nil))
          }
        }
      } else {
        result(FlutterError(code: "not_supported", message: "iOS 17+ required", details: nil))
      }
      return

    default:
      result(FlutterMethodNotImplemented)
      return
    }
  }
}

@available(iOS 17.0, *)
private extension AppleWatchWorkoutKitBridge {
  func requestAuthorization() async -> String {
    let status = await WorkoutScheduler.shared.requestAuthorization()
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  func getAuthorizationStatus() -> String {
    // WorkoutScheduler.shared.authorizationStatus API'si iOS 17'de mevcut.
    let status = WorkoutScheduler.shared.authorizationStatus
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  func syncScheduledWorkouts(payloads: [[String: Any]]) async throws {
    // Authorization kontrolü
    guard WorkoutScheduler.shared.authorizationStatus == .authorized else {
      throw AppleWatchBridgeError.authorizationDenied
    }

    // Duplikasyon önlemek için: payload id'lerini UserDefaults'ta tutup yalnızca yeni olanları schedule ediyoruz.
    // Kullanıcı "Şimdi Senkronla" yaptıkça aynı id'ler yeniden schedule edilmez.
    let defaultsKey = "apple_watch.workoutkit.sentIds"
    let defaults = UserDefaults.standard
    let sent = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    var updatedSent = sent

    for p in payloads {
      guard let id = p["id"] as? String,
            let title = p["title"] as? String,
            let scheduledAtRaw = p["scheduledAt"] as? String,
            let scheduledAt = ISO8601DateFormatter().date(from: scheduledAtRaw),
            let definition = p["definition"] as? [String: Any] else {
        continue
      }

      if sent.contains(id) { continue }

      let segments = flattenSegments(definition: definition)
      if segments.isEmpty { continue }

      let workoutPlan = try buildWorkoutPlan(title: title, segments: segments)
      let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
      await WorkoutScheduler.shared.schedule(workoutPlan, at: comps)
      updatedSent.insert(id)
    }

    defaults.set(Array(updatedSent), forKey: defaultsKey)
  }

  struct Segment {
    let segmentType: String
    let targetType: String
    let durationSeconds: Double?
    let distanceMeters: Double?
  }

  func flattenSegments(definition: [String: Any]) -> [Segment] {
    guard let steps = definition["steps"] as? [[String: Any]] else { return [] }
    var out: [Segment] = []
    for step in steps {
      flattenStep(step, into: &out)
    }
    return out
  }

  func flattenStep(_ step: [String: Any], into out: inout [Segment]) {
    let type = (step["type"] as? String) ?? ""
    if type == "segment" {
      if let seg = step["segment"] as? [String: Any],
         let segType = seg["segmentType"] as? String,
         let targetType = seg["targetType"] as? String {
        let dur = (seg["durationSeconds"] as? NSNumber)?.doubleValue
        let dist = (seg["distanceMeters"] as? NSNumber)?.doubleValue
        out.append(Segment(segmentType: segType, targetType: targetType, durationSeconds: dur, distanceMeters: dist))
      }
      return
    }
    if type == "repeat" {
      let repeatCount = (step["repeatCount"] as? NSNumber)?.intValue ?? 1
      let innerSteps = step["steps"] as? [[String: Any]] ?? []
      if repeatCount <= 1 {
        for s in innerSteps { flattenStep(s, into: &out) }
      } else {
        for _ in 0..<repeatCount {
          for s in innerSteps { flattenStep(s, into: &out) }
        }
      }
      return
    }
  }

  func buildWorkoutPlan(title: String, segments: [Segment]) throws -> WorkoutPlan {
    // Warmup & cooldown ayır
    var warmupStep: WorkoutStep? = nil
    var cooldownStep: WorkoutStep? = nil
    var core: [Segment] = segments

    if let first = core.first, first.segmentType == "warmup" {
      warmupStep = WorkoutStep(goal: goalForSegment(first))
      core.removeFirst()
    }
    if let last = core.last, last.segmentType == "cooldown" {
      cooldownStep = WorkoutStep(goal: goalForSegment(last))
      core.removeLast()
    }

    // Planned workout'lar interval block beklediği için core boşsa tek bir open interval ekleyelim.
    if core.isEmpty {
      core = [Segment(segmentType: "main", targetType: "open", durationSeconds: nil, distanceMeters: nil)]
    }

    let intervalSteps: [IntervalStep] = core.map { seg in
      let kind: IntervalStep.Kind = (seg.segmentType == "recovery") ? .recovery : .work
      return IntervalStep(kind, goal: goalForSegment(seg), alert: nil)
    }
    let block = IntervalBlock(steps: intervalSteps, iterations: 1)

    let workout = CustomWorkout(
      activity: .running,
      warmup: warmupStep,
      blocks: [block],
      cooldown: cooldownStep,
      displayName: title
    )
    return WorkoutPlan(.custom(workout))
  }

  func goalForSegment(_ seg: Segment) -> WorkoutGoal {
    switch seg.targetType {
    case "duration":
      let seconds = seg.durationSeconds ?? 0
      return .time(seconds, .seconds)
    case "distance":
      let meters = seg.distanceMeters ?? 0
      return .distance(meters, .meters)
    default:
      return .open
    }
  }
}

