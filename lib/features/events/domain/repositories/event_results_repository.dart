import '../../../../core/errors/failures.dart';
import '../entities/event_result_entity.dart';

/// Event Results Repository Interface
abstract class EventResultsRepository {
  /// Belirli bir etkinliğin sonuç listesini getir
  Future<({List<EventResultEntity>? results, Failure? failure})> getEventResults(
    String eventId,
  );

  /// Excel şablonunu indir (XLSX bytes)
  Future<({List<int>? bytes, Failure? failure})> downloadResultsTemplate(
    String eventId,
  );

  /// Excel dosyasını import et
  ///
  /// [fileBytes]: XLSX dosyasının bytes içeriği
  /// [fileName]: Orijinal dosya adı (content-type için yardımcı)
  Future<({bool success, List<ImportRowError> errors, Failure? failure})> importResults({
    required String eventId,
    required List<int> fileBytes,
    required String fileName,
  });
}

/// Import edilen satırdaki hata bilgisi
class ImportRowError {
  final int rowIndex;
  final String message;

  const ImportRowError({
    required this.rowIndex,
    required this.message,
  });
}

