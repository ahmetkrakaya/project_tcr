import Flutter
import UIKit
import Foundation
import WorkoutKit
import FirebaseCore
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let _authDefaultsKey = "apple_watch.workoutkit.isAuthorized"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)

    // Uygulama öndeyken gelen push'ların banner/ses göstermesi için (iOS varsayılanı göstermiyor)
    UNUserNotificationCenter.current().delegate = self

    // Apple Watch WorkoutKit bridge (MethodChannel)
    if #available(iOS 17.0, *),
       let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "tcr/apple_watch_workoutkit",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "isSupported":
          result(true)
          return

        case "requestAuthorization":
          Task {
            let status = await WorkoutScheduler.shared.requestAuthorization()
            let statusStr = Self._stringForAuthorizationStatus(status)
            // WorkoutKit API yüzeyi sürüme göre değişebildiği için authorization durumunu ayrıca saklıyoruz.
            UserDefaults.standard.set(statusStr == "authorized", forKey: Self._authDefaultsKey)
            result(statusStr)
          }
          return

        case "getAuthorizationStatus":
          let isAuthorized = UserDefaults.standard.bool(forKey: Self._authDefaultsKey)
          result(isAuthorized ? "authorized" : "notDetermined")
          return

        case "syncScheduledWorkouts":
          guard let args = call.arguments as? [String: Any],
                let payloads = args["payloads"] as? [[String: Any]] else {
            result(FlutterError(code: "invalid_args", message: "payloads missing", details: nil))
            return
          }
          Task {
            do {
              try await Self._syncScheduledWorkouts(payloads: payloads)
              result(nil)
            } catch {
              result(FlutterError(code: "sync_failed", message: "\(error)", details: nil))
            }
          }
          return

        default:
          result(FlutterMethodNotImplemented)
          return
        }
      }
    } else {
      // iOS < 17: kanal yine de kurulabilir ama supported=false döndürmek için basit bir handler kuruyoruz.
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "tcr/apple_watch_workoutkit",
          binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
          switch call.method {
          case "isSupported":
            result(false)
          case "requestAuthorization", "getAuthorizationStatus":
            result("notSupported")
          case "syncScheduledWorkouts":
            result(FlutterError(code: "not_supported", message: "iOS 17+ required", details: nil))
          default:
            result(FlutterMethodNotImplemented)
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Uygulama öndeyken gelen bildirimi banner + ses + badge ile göster
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}

@available(iOS 17.0, *)
private extension AppDelegate {
  /// WorkoutKit tarafında authorization status type adı sürüme göre değişebildiği için
  /// burada doğrudan type'a bağlanmıyoruz. `String(describing:)` ile gelen değeri map'liyoruz.
  static func _stringForAuthorizationStatus(_ status: Any) -> String {
    let s = String(describing: status).lowercased()
    if s.contains("authorized") { return "authorized" }
    if s.contains("denied") { return "denied" }
    if s.contains("notdetermined") { return "notDetermined" }
    if s.contains("restricted") { return "restricted" }
    return "unknown"
  }

  struct _Segment {
    let segmentType: String
    let targetType: String
    let target: String
    let durationSeconds: Double?
    let distanceMeters: Double?
    /// Tempo hedefi: hızlı pace (saniye/km). Varsa saate speed alert olarak gider.
    let paceSecondsPerKmMin: Double?
    /// Tempo hedefi: yavaş pace (saniye/km). Range alert için.
    let paceSecondsPerKmMax: Double?
  }

  static func _syncScheduledWorkouts(payloads: [[String: Any]]) async throws {
    let isAuthorized = UserDefaults.standard.bool(forKey: Self._authDefaultsKey)
    guard isAuthorized else {
      throw NSError(domain: "tcr.applewatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "authorizationDenied"])
    }

    // Duplikasyon önlemek için: payload id'lerini UserDefaults'ta tutup yalnızca yeni olanları schedule ediyoruz.
    let defaultsKey = "apple_watch.workoutkit.sentIds"
    let defaults = UserDefaults.standard
    let sent = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    var updatedSent = sent

    for p in payloads {
      guard let id = p["id"] as? String,
            let title = p["title"] as? String,
            let scheduledAtMs = p["scheduledAtMs"] as? NSNumber else {
        continue
      }

      let scheduledAt = Date(timeIntervalSince1970: scheduledAtMs.doubleValue / 1000.0)
      let scheduledAtRaw = String(format: "%.0f", scheduledAtMs.doubleValue)

      if sent.contains(id) {
        continue
      }

      // Debug payload'ları: sabit örnek workout.
      if id.hasPrefix("debug-") {
        let plan = try _buildDebugWorkoutPlan(title: title)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        await WorkoutScheduler.shared.schedule(plan, at: comps)
        updatedSent.insert(id)
        continue
      }

      // Gerçek payload'lar: WorkoutDefinition JSON'u kullan.
      guard let definition = p["definition"] as? [String: Any] else {
        continue
      }

      let segments = _flattenSegments(definition: definition)
      if segments.isEmpty {
        continue
      }

      let plan = try _buildWorkoutPlan(title: title, segments: segments)
      let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
      await WorkoutScheduler.shared.schedule(plan, at: comps)
      updatedSent.insert(id)
    }

    defaults.set(Array(updatedSent), forKey: defaultsKey)
  }

  static func _flattenSegments(definition: [String: Any]) -> [_Segment] {
    guard let steps = definition["steps"] as? [[String: Any]] else { return [] }
    var out: [_Segment] = []
    for step in steps {
      _flattenStep(step, into: &out)
    }
    return out
  }

  static func _flattenStep(_ step: [String: Any], into out: inout [_Segment]) {
    let type = (step["type"] as? String) ?? ""
    if type == "segment" {
      if let seg = step["segment"] as? [String: Any],
         let segType = seg["segmentType"] as? String,
         let targetType = seg["targetType"] as? String {
        let dur = (seg["durationSeconds"] as? NSNumber)?.doubleValue
        let dist = (seg["distanceMeters"] as? NSNumber)?.doubleValue
        let target = (seg["target"] as? String) ?? "none"
        // Pace aralığı: paceSecondsPerKmMin (hızlı) ve paceSecondsPerKmMax (yavaş)
        let paceMin = (seg["paceSecondsPerKmMin"] as? NSNumber)?.doubleValue
          ?? (seg["customPaceSecondsPerKm"] as? NSNumber)?.doubleValue
          ?? (seg["paceSecondsPerKm"] as? NSNumber)?.doubleValue
        let paceMax = (seg["paceSecondsPerKmMax"] as? NSNumber)?.doubleValue
          ?? paceMin
        out.append(_Segment(segmentType: segType, targetType: targetType, target: target, durationSeconds: dur, distanceMeters: dist, paceSecondsPerKmMin: paceMin, paceSecondsPerKmMax: paceMax))
      }
      return
    }
    if type == "repeat" {
      let repeatCount = (step["repeatCount"] as? NSNumber)?.intValue ?? 1
      let innerSteps = step["steps"] as? [[String: Any]] ?? []
      if repeatCount <= 1 {
        for s in innerSteps { _flattenStep(s, into: &out) }
      } else {
        for _ in 0..<repeatCount {
          for s in innerSteps { _flattenStep(s, into: &out) }
        }
      }
      return
    }
  }

  static func _buildWorkoutPlan(title: String, segments: [_Segment]) throws -> WorkoutPlan {
    var warmupStep: WorkoutStep? = nil
    var cooldownStep: WorkoutStep? = nil
    var core: [_Segment] = segments

    // Isınma ve soğuma segmentlerini listedeki konumdan bağımsız olarak ayıkla.
    // Pace varsa alert ile saate tempo hedefi gönderilir (Isınma/Soğuma tempo görünsün).
    if let warmupIndex = core.firstIndex(where: { $0.segmentType == "warmup" }) {
      let warmupSeg = core.remove(at: warmupIndex)
      let warmupAlert = _alertForSegment(warmupSeg)
      warmupStep = WorkoutStep(goal: _goalForSegment(warmupSeg), alert: warmupAlert)
    }
    if let cooldownIndex = core.firstIndex(where: { $0.segmentType == "cooldown" }) {
      let cooldownSeg = core.remove(at: cooldownIndex)
      let cooldownAlert = _alertForSegment(cooldownSeg)
      cooldownStep = WorkoutStep(goal: _goalForSegment(cooldownSeg), alert: cooldownAlert)
    }

    if core.isEmpty {
      core = [_Segment(segmentType: "main", targetType: "open", target: "none", durationSeconds: nil, distanceMeters: nil, paceSecondsPerKmMin: nil, paceSecondsPerKmMax: nil)]
    }

    let intervalSteps: [IntervalStep] = core.map { seg in
      let alert = _alertForSegment(seg)
      return IntervalStep(seg.segmentType == "recovery" ? .recovery : .work, goal: _goalForSegment(seg), alert: alert)
    }
    let block = IntervalBlock(steps: intervalSteps, iterations: 1)

    let workout = CustomWorkout(
      activity: .running,
      displayName: title,
      warmup: warmupStep,
      blocks: [block],
      cooldown: cooldownStep
    )
    return WorkoutPlan(.custom(workout))
  }

  /// Debug/test amacıyla tanımlanmış basit bir koşu antrenmanı:
  /// - 5 dk ısınma
  /// - 10 dk ana bölüm (interval block)
  /// - Açık soğuma
  static func _buildDebugWorkoutPlan(title: String) throws -> WorkoutPlan {
    let warmupStep = WorkoutStep(goal: .time(5 * 60, .seconds))
    let mainStep = IntervalStep(.work, goal: .time(10 * 60, .seconds), alert: nil)
    let cooldownStep = WorkoutStep(goal: .open)

    let block = IntervalBlock(steps: [mainStep], iterations: 1)

    let workout = CustomWorkout(
      activity: .running,
      displayName: title,
      warmup: warmupStep,
      blocks: [block],
      cooldown: cooldownStep
    )
    return WorkoutPlan(.custom(workout))
  }

  static func _goalForSegment(_ seg: _Segment) -> WorkoutGoal {
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

  /// Tempo (pace) varsa WorkoutKit speed alert döndürür; saat antrenmanda hedef tempo olarak gösterilir.
  /// Pace aralığı varsa (min != max) speed range alert, yoksa tek değer alert gönderilir.
  static func _alertForSegment(_ seg: _Segment) -> WorkoutAlert? {
    guard let paceMin = seg.paceSecondsPerKmMin, paceMin > 0 else { return nil }
    let paceMax = seg.paceSecondsPerKmMax ?? paceMin
    // pace saniye/km → hız km/h: 3600 / paceSec
    // NOT: paceMin (hızlı) → daha yüksek km/h, paceMax (yavaş) → daha düşük km/h
    let speedHighKmH = 3600.0 / paceMin  // Hızlı pace = yüksek hız
    let speedLowKmH = 3600.0 / paceMax   // Yavaş pace = düşük hız
    if abs(speedHighKmH - speedLowKmH) < 0.01 {
      // Tek değer
      return .speed(speedHighKmH, unit: .kilometersPerHour)
    }
    // Range alert: minimum hız ile maksimum hız arası
    return .speed(speedLowKmH...speedHighKmH, unit: .kilometersPerHour)
  }
}
