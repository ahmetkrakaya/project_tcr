import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/event_result_entity.dart';
import '../../domain/repositories/event_results_repository.dart';
import '../models/event_result_model.dart';

class EventResultsRepositoryImpl implements EventResultsRepository {
  final SupabaseClient _supabase;

  EventResultsRepositoryImpl(this._supabase);

  @override
  Future<({List<EventResultEntity>? results, Failure? failure})> getEventResults(
    String eventId,
  ) async {
    try {
      // Tercihen helper fonksiyon üzerinden al
      final response = await _supabase
          .rpc(
            'get_event_results',
            params: {'event_uuid': eventId},
          )
          .select();

      final List<dynamic> data = response as List<dynamic>;
      final models = data
          .map(
            (json) =>
                EventResultModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();

      return (
        results: models.map((m) => m.toEntity()).toList(),
        failure: null,
      );
    } on PostgrestException catch (e) {
      return (
        results: null,
        failure: ServerFailure(message: e.message, code: e.code),
      );
    } catch (e) {
      return (
        results: null,
        failure: ServerFailure(
          message: 'Yarış sonuçları alınamadı',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<({List<int>? bytes, Failure? failure})> downloadResultsTemplate(
    String eventId,
  ) async {
    try {
      
      // Edge Function URL'i oluştur
      final functionName = 'event-results-template';
      final functionUrl = '${AppConstants.supabaseUrl}/functions/v1/$functionName?event_id=$eventId';
      
      // Access token al
      final session = _supabase.auth.currentSession;
      final accessToken = session?.accessToken;
      
      if (accessToken == null) {
        await _supabase.auth.refreshSession();
        final newSession = _supabase.auth.currentSession;
        final newToken = newSession?.accessToken;
        if (newToken == null) {
          return (
            bytes: null,
            failure: const ServerFailure(message: 'Oturum bulunamadı. Lütfen tekrar giriş yapın.'),
          );
        }
      }
      
      final finalToken = _supabase.auth.currentSession?.accessToken ?? '';
      
      // Dio ile binary response al
      final dio = Dio();
      
      Response<List<int>> response;
      try {
        response = await dio.get<List<int>>(
          functionUrl,
          options: Options(
            headers: {
              'Authorization': 'Bearer $finalToken',
              'apikey': AppConstants.supabaseAnonKey,
            },
            responseType: ResponseType.bytes,
            validateStatus: (status) => true, // Tüm status kodlarını kabul et
          ),
        );
      } catch (e) {
        return (
          bytes: null,
          failure: ServerFailure(
            message: 'Şablon indirilemedi: $e',
          ),
        );
      }
      
      if (response.statusCode != 200) {
        // Response body'yi string olarak oku (hata mesajı için)
        String? errorBody;
        if (response.data != null && response.data!.isNotEmpty) {
          try {
            errorBody = String.fromCharCodes(response.data!);
            
            // JSON response ise parse et
            try {
              final jsonError = jsonDecode(errorBody);
              if (jsonError is Map && jsonError.containsKey('message')) {
                errorBody = jsonError['message'] as String? ?? errorBody;
              }
            } catch (_) {
              // JSON değilse olduğu gibi kullan
            }
          } catch (_) {
            // Hata durumunda errorBody boş kalır; varsayılan mesaj kullanılacak
          }
        }
        
        return (
          bytes: null,
          failure: ServerFailure(
            message: 'Şablon indirilemedi (HTTP ${response.statusCode}): ${errorBody ?? response.statusMessage ?? "Bilinmeyen hata"}',
          ),
        );
      }
      
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return (
          bytes: null,
          failure: const ServerFailure(message: 'Şablon indirilemedi: Boş dosya'),
        );
      }
      
      return (bytes: bytes, failure: null);
    } catch (e) {
      return (
        bytes: null,
        failure: ServerFailure(
          message: 'Şablon indirilemedi: ${e.toString()}',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<({bool success, List<ImportRowError> errors, Failure? failure})>
      importResults({
    required String eventId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
      final functionName = 'event-results-import';
      final response = await _supabase.functions.invoke(
        functionName,
        body: {
          'event_id': eventId,
          'file_name': fileName,
          'file_bytes': fileBytes,
        },
      );

      // Edge function her zaman JSON dönüyor
      final data = response.data as Map<String, dynamic>? ?? {};
      final bool success = data['success'] as bool? ?? true;
      final List<dynamic> errorList =
          data['errors'] as List<dynamic>? ?? <dynamic>[];

      final errors = errorList.map((e) {
        final rowIndex =
            e is Map && e['rowIndex'] is int ? e['rowIndex'] as int : 0;
        final message = e is Map && e['message'] is String
            ? e['message'] as String
            : 'Bilinmeyen hata';
        return ImportRowError(rowIndex: rowIndex, message: message);
      }).toList();

      return (success: success, errors: errors, failure: null);
    } catch (e) {
      return (
        success: false,
        errors: const <ImportRowError>[],
        failure: ServerFailure(
          message: 'Sonuçlar import edilemedi: ${e.toString()}',
          originalError: e,
        ),
      );
    }
  }
}

