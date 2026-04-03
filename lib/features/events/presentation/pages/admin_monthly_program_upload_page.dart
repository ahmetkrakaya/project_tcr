import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/event_provider.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';

class AdminMonthlyProgramUploadPage extends ConsumerStatefulWidget {
  const AdminMonthlyProgramUploadPage({super.key});

  @override
  ConsumerState<AdminMonthlyProgramUploadPage> createState() =>
      _AdminMonthlyProgramUploadPageState();
}

class _AdminMonthlyProgramUploadPageState
    extends ConsumerState<AdminMonthlyProgramUploadPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  PlatformFile? _selectedFile;
  bool _isLoading = false;
  List<Map<String, dynamic>> _errors = [];
  int _acceptedRows = 0;

  String get _monthKey => DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _downloadTemplate() async {
    try {
      setState(() => _isLoading = true);
      final ds = ref.read(eventDataSourceProvider);
      final bytes = await ds.downloadMonthlyProgramTemplate();

      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Web için otomatik indirme kapalı. Mobilde indirip paylaşabilirsiniz.',
            ),
          ),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/monthly_program_template.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Aylık program şablonu');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Şablon indirilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _selectedFile = result.files.first;
    });
  }

  Future<void> _importFile() async {
    final file = _selectedFile;
    if (file == null) return;
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya okunamadı')),
      );
      return;
    }
    try {
      setState(() {
        _isLoading = true;
        _errors = [];
      });
      final ds = ref.read(eventDataSourceProvider);
      final response = await ds.importMonthlyProgram(
        monthKey: _monthKey,
        fileName: file.name,
        fileBytes: bytes,
      );
      setState(() {
        _acceptedRows = (response['accepted_rows'] as num?)?.toInt() ?? 0;
        final rawErrors = (response['errors'] as List?) ?? [];
        _errors = rawErrors
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errors.isEmpty
              ? 'Import tamamlandı: $_acceptedRows satır'
              : 'Import hatalı: ${_errors.length} satır hatası'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aylık Program Yükle')),
        body: const Center(child: Text('Bu sayfaya erişim yetkiniz yok.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Aylık Program Yükle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ay Seçimi'),
            subtitle: Text(DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth)),
            trailing: FilledButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedMonth,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2035, 12, 31),
                        locale: const Locale('tr', 'TR'),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedMonth = DateTime(picked.year, picked.month, 1);
                        });
                      }
                    },
              child: const Text('Değiştir'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _downloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Şablonu İndir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Dosya Seç'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_selectedFile != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_selectedFile!.name),
              subtitle: Text(
                'Boyut: ${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
              ),
              trailing: FilledButton(
                onPressed: _isLoading ? null : _importFile,
                child: const Text('Yükle'),
              ),
            ),
          if (_isLoading) const LinearProgressIndicator(),
          if (_acceptedRows > 0) ...[
            const SizedBox(height: 12),
            Text('Başarılı satır: $_acceptedRows'),
          ],
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Hata Listesi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._errors.take(50).map((e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text('Satır ${e['row']}: ${e['message']}'),
                )),
          ],
        ],
      ),
    );
  }
}
