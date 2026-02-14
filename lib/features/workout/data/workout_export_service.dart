import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fit_tool/fit_tool.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/vdot_calculator.dart';
import '../domain/entities/workout_entity.dart';
import 'models/workout_model.dart';

/// FIT, TCX ve JSONV2 formatında antrenman export servisi
class WorkoutExportService {
  WorkoutExportService._();
  static final WorkoutExportService instance = WorkoutExportService._();

  /// Yinelemeleri açarak düz segment listesi döndürür
  List<WorkoutSegmentEntity> flattenSteps(WorkoutDefinitionEntity definition) {
    final out = <WorkoutSegmentEntity>[];
    for (final step in definition.steps) {
      if (step.isSegment && step.segment != null) {
        out.add(step.segment!);
      } else if (step.isRepeat && step.repeatCount != null && step.steps != null) {
        for (var i = 0; i < step.repeatCount!; i++) {
          for (final inner in step.steps!) {
            if (inner.isSegment && inner.segment != null) {
              out.add(inner.segment!);
            }
          }
        }
      }
    }
    return out;
  }

  /// Pace değerini hesapla (VDOT modu veya manuel)
  /// Offset bazlı: threshold + offset ile pace aralığı hesaplanır, hızlı pace döner.
  int? _getEffectivePace(
    WorkoutSegmentEntity s,
    double? userVdot, {
    int? offsetMin,
    int? offsetMax,
  }) {
    if (s.target == WorkoutTarget.pace) {
      if (s.useVdotForPace == true && userVdot != null && userVdot > 0) {
        final paceRange = VdotCalculator.getPaceRangeForSegmentType(
          userVdot,
          s.segmentType.name,
          offsetMin,
          offsetMax,
        );
        if (paceRange != null) return paceRange.$1; // Hızlı pace
        return null;
      } else {
        // Manuel pace
        return s.customPaceSecondsPerKm ?? s.paceSecondsPerKm ?? s.paceSecondsPerKmMin;
      }
    }
    return null;
  }

  /// FIT dosyası oluşturur (Garmin vb.)
  Uint8List exportToFit(
    WorkoutDefinitionEntity definition, {
    String workoutName = 'TCR Workout',
    double? userVdot,
    String? trainingTypeName,
    int? offsetMin,
    int? offsetMax,
  }) {
    final segments = flattenSteps(definition);
    final messages = <DataMessage>[];

    final fileId = FileIdMessage()
      ..type = FileType.workout
      ..manufacturer = 0
      ..product = 0
      ..serialNumber = DateTime.now().millisecondsSinceEpoch
      ..timeCreated = DateTime.now().millisecondsSinceEpoch;
    messages.add(fileId);

    final workout = WorkoutMessage()
      ..sport = Sport.running
      ..capabilities = 0
      ..numValidSteps = segments.length
      ..workoutName = workoutName;
    messages.add(workout);

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final stepMsg = WorkoutStepMessage()
        ..messageIndex = i
        ..workoutStepName = s.segmentType.displayName;

      if (s.targetType == WorkoutTargetType.duration && s.durationSeconds != null) {
        stepMsg.durationType = WorkoutStepDuration.time;
        stepMsg.durationTime = s.durationSeconds!.toDouble();
      } else if (s.targetType == WorkoutTargetType.distance && s.distanceMeters != null) {
        stepMsg.durationType = WorkoutStepDuration.distance;
        stepMsg.durationDistance = s.distanceMeters! / 1000.0;
      } else {
        stepMsg.durationType = WorkoutStepDuration.open;
      }

      final paceSec = _getEffectivePace(s, userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
      if (s.target == WorkoutTarget.pace && paceSec != null && paceSec > 0) {
        stepMsg.targetType = WorkoutStepTarget.speed;
        final speedMs = 1000.0 / paceSec;
        stepMsg.customTargetSpeedLow = speedMs;
        stepMsg.customTargetSpeedHigh = speedMs;
      } else if (s.target == WorkoutTarget.heartRate && (s.heartRateBpmMin != null || s.heartRateBpmMax != null)) {
        stepMsg.targetType = WorkoutStepTarget.heartRate;
        if (s.heartRateBpmMin != null) stepMsg.customTargetHeartRateLow = s.heartRateBpmMin!;
        if (s.heartRateBpmMax != null) stepMsg.customTargetHeartRateHigh = s.heartRateBpmMax!;
      } else if (s.target == WorkoutTarget.cadence && (s.cadenceMin != null || s.cadenceMax != null)) {
        stepMsg.targetType = WorkoutStepTarget.cadence;
        if (s.cadenceMin != null) stepMsg.customTargetCadenceLow = s.cadenceMin!;
        if (s.cadenceMax != null) stepMsg.customTargetCadenceHigh = s.cadenceMax!;
      } else if (s.target == WorkoutTarget.power && (s.powerWattsMin != null || s.powerWattsMax != null)) {
        stepMsg.targetType = WorkoutStepTarget.power;
        if (s.powerWattsMin != null) stepMsg.customTargetPowerLow = s.powerWattsMin!;
        if (s.powerWattsMax != null) stepMsg.customTargetPowerHigh = s.powerWattsMax!;
      } else {
        stepMsg.targetType = WorkoutStepTarget.open;
      }

      messages.add(stepMsg);
    }

    final builder = FitFileBuilder();
    builder.addAll(messages);
    final fitFile = builder.build();
    return fitFile.toBytes();
  }

  /// TCX (Training Center XML) dosyası oluşturur
  String exportToTcx(
    WorkoutDefinitionEntity definition, {
    String workoutName = 'TCR Workout',
    double? userVdot,
    String? trainingTypeName,
    int? offsetMin,
    int? offsetMax,
  }) {
    final segments = flattenSteps(definition);
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">');
    buffer.writeln('  <Workouts>');
    buffer.writeln('    <Workout Sport="Running">');
    buffer.writeln('      <Name>$workoutName</Name>');

    for (final s in segments) {
      buffer.writeln('      <Step>');
      buffer.writeln('        <Name>${_escapeXml(s.segmentType.displayName)}</Name>');
      if (s.targetType == WorkoutTargetType.duration && s.durationSeconds != null) {
        buffer.writeln('        <Duration>');
        buffer.writeln('          <TotalTimeSeconds>${s.durationSeconds}</TotalTimeSeconds>');
        buffer.writeln('        </Duration>');
      } else if (s.targetType == WorkoutTargetType.distance && s.distanceMeters != null) {
        buffer.writeln('        <Duration>');
        buffer.writeln('          <DistanceMeters>${s.distanceMeters!.round()}</DistanceMeters>');
        buffer.writeln('        </Duration>');
      } else {
        buffer.writeln('        <Duration>');
        buffer.writeln('          <Open/>');
        buffer.writeln('        </Duration>');
      }

      final paceSec = _getEffectivePace(s, userVdot, offsetMin: offsetMin, offsetMax: offsetMax);
      if (s.target == WorkoutTarget.pace && paceSec != null && paceSec > 0) {
        final speedMs = 1000.0 / paceSec;
        buffer.writeln('        <Target>');
        buffer.writeln('          <Speed>');
        buffer.writeln('            <LowInMetersPerSecond>$speedMs</LowInMetersPerSecond>');
        buffer.writeln('            <HighInMetersPerSecond>$speedMs</HighInMetersPerSecond>');
        buffer.writeln('          </Speed>');
        buffer.writeln('        </Target>');
      } else if (s.target == WorkoutTarget.heartRate && (s.heartRateBpmMin != null || s.heartRateBpmMax != null)) {
        buffer.writeln('        <Target>');
        buffer.writeln('          <HeartRate>');
        if (s.heartRateBpmMin != null) buffer.writeln('            <LowBpm>${s.heartRateBpmMin}</LowBpm>');
        if (s.heartRateBpmMax != null) buffer.writeln('            <HighBpm>${s.heartRateBpmMax}</HighBpm>');
        buffer.writeln('          </HeartRate>');
        buffer.writeln('        </Target>');
      } else {
        buffer.writeln('        <Target>');
        buffer.writeln('          <Open/>');
        buffer.writeln('        </Target>');
      }
      buffer.writeln('        <Intensity>Active</Intensity>');
      buffer.writeln('      </Step>');
    }

    buffer.writeln('    </Workout>');
    buffer.writeln('  </Workouts>');
    buffer.writeln('</TrainingCenterDatabase>');
    return buffer.toString();
  }

  String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// JSONV2 (uygulama içi yapılandırılmış format)
  String exportToJsonV2(WorkoutDefinitionEntity definition) {
    final model = WorkoutDefinitionModel.fromEntity(definition);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(model.toJson());
  }

  /// Export eder ve paylaşım / dosya seçeneği sunar.
  /// Web'de dosya download olarak indirilir, mobilde Share sheet açılır.
  Future<void> exportAndShare({
    required WorkoutDefinitionEntity definition,
    required String format,
    String workoutName = 'TCR Workout',
    double? userVdot,
    String? trainingTypeName,
    int? offsetMin,
    int? offsetMax,
  }) async {
    final baseName = workoutName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    Uint8List fileBytes;
    String fileName;

    switch (format.toLowerCase()) {
      case 'fit':
        fileBytes = exportToFit(
          definition,
          workoutName: workoutName,
          userVdot: userVdot,
          trainingTypeName: trainingTypeName,
          offsetMin: offsetMin,
          offsetMax: offsetMax,
        );
        fileName = '$baseName.fit';
        break;
      case 'tcx':
        final tcxContent = exportToTcx(
          definition,
          workoutName: workoutName,
          userVdot: userVdot,
          trainingTypeName: trainingTypeName,
          offsetMin: offsetMin,
          offsetMax: offsetMax,
        );
        fileBytes = Uint8List.fromList(utf8.encode(tcxContent));
        fileName = '$baseName.tcx';
        break;
      case 'json':
      case 'jsonv2':
        final jsonContent = exportToJsonV2(definition);
        fileBytes = Uint8List.fromList(utf8.encode(jsonContent));
        fileName = '$baseName.json';
        break;
      default:
        throw ArgumentError('Unsupported format: $format');
    }

    if (kIsWeb) {
      // Web'de dosyayı indirme olarak sun
      _downloadFileWeb(fileBytes, fileName);
    } else {
      // Mobilde: geçici dosya oluştur ve Share sheet aç
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$fileName';
      final file = File(path);
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(path)], text: 'Antrenman: $workoutName');
    }
  }

  /// Web'de dosyayı browser download olarak indirir
  void _downloadFileWeb(Uint8List bytes, String fileName) {
    // Web'de share_plus Share.shareXFiles zaten download fallback yapıyor
    // Ancak XFile.fromData ile daha temiz çalışır
    Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName)],
      text: 'Antrenman: $fileName',
    );
  }
}
