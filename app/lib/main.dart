import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FieldManagerHelperApp());
}

class FieldManagerHelperApp extends StatelessWidget {
  const FieldManagerHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '현장관리 도우미',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        appBarTheme: const AppBarTheme(centerTitle: true),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class AppConfig {
  static String get defaultBaseUrl {
    const definedUrl = String.fromEnvironment('BASE_URL', defaultValue: '');
    if (definedUrl.isNotEmpty) {
      return definedUrl;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://127.0.0.1:8000';
      default:
        return 'http://127.0.0.1:8000';
    }
  }
}

class InspectionRecord {
  final String recordNo;
  final String title;
  final String siteName;
  final String inspectionDateTime;
  final String inspector;
  final String zone;
  final String category;
  final String target;
  final String content;
  final String result;
  final String actionNeeded;
  final String remarks;
  final List<String> imagePaths;
  final String createdAt;

  InspectionRecord({
    required this.recordNo,
    required this.title,
    required this.siteName,
    required this.inspectionDateTime,
    required this.inspector,
    required this.zone,
    required this.category,
    required this.target,
    required this.content,
    required this.result,
    required this.actionNeeded,
    required this.remarks,
    required this.imagePaths,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'recordNo': recordNo,
      'title': title,
      'siteName': siteName,
      'inspectionDateTime': inspectionDateTime,
      'inspector': inspector,
      'zone': zone,
      'category': category,
      'target': target,
      'content': content,
      'result': result,
      'actionNeeded': actionNeeded,
      'remarks': remarks,
      'imagePaths': imagePaths,
      'createdAt': createdAt,
    };
  }

  factory InspectionRecord.fromJson(Map<String, dynamic> json) {
    return InspectionRecord(
      recordNo: json['recordNo'] ?? '',
      title: json['title'] ?? '',
      siteName: json['siteName'] ?? '',
      inspectionDateTime: json['inspectionDateTime'] ?? '',
      inspector: json['inspector'] ?? '',
      zone: json['zone'] ?? '',
      category: json['category'] ?? '',
      target: json['target'] ?? '',
      content: json['content'] ?? '',
      result: json['result'] ?? '',
      actionNeeded: json['actionNeeded'] ?? '',
      remarks: json['remarks'] ?? '',
      imagePaths: List<String>.from(json['imagePaths'] ?? <String>[]),
      createdAt: json['createdAt'] ?? '',
    );
  }
}

class BasicInfoData {
  final String siteName;
  final String inspectionDateTime;
  final String inspector;
  final String category;
  final String zone;
  final String serverUrl;

  BasicInfoData({
    required this.siteName,
    required this.inspectionDateTime,
    required this.inspector,
    required this.category,
    required this.zone,
    required this.serverUrl,
  });
}

class SttResponseData {
  final String rawText;
  final String cleanText;
  final String language;
  final double? languageProbability;

  SttResponseData({
    required this.rawText,
    required this.cleanText,
    required this.language,
    required this.languageProbability,
  });
}

class StorageService {
  static const String recordsKey = 'inspection_records_v1';
  static const String serverUrlKey = 'stt_server_url_v2';

  static Future<List<InspectionRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(recordsKey);

    if (encoded == null || encoded.isEmpty) {
      return <InspectionRecord>[];
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return <InspectionRecord>[];
    }

    return decoded
        .map((item) => InspectionRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> saveRecords(List<InspectionRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(records.map((e) => e.toJson()).toList());
    await prefs.setString(recordsKey, encoded);
  }

  static Future<void> upsertRecord(InspectionRecord record) async {
    final records = await loadRecords();
    final index = records.indexWhere((e) => e.recordNo == record.recordNo);

    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }

    await saveRecords(records);
  }

  static Future<void> deleteRecord(String recordNo) async {
    final records = await loadRecords();
    records.removeWhere((e) => e.recordNo == recordNo);
    await saveRecords(records);
  }

  static Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(serverUrlKey);
    if (saved == null || saved.trim().isEmpty) {
      return AppConfig.defaultBaseUrl;
    }
    return saved.trim();
  }

  static Future<void> saveServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(serverUrlKey, value.trim());
  }
}

class PdfService {
  static Future<File> createPdf(InspectionRecord record) async {
    final pdf = pw.Document();

    final dateLabel =
        record.inspectionDateTime.isEmpty ? '-' : record.inspectionDateTime;

    final imageWidgets = <pw.Widget>[];

    for (final path in record.imagePaths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        imageWidgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Image(
              pw.MemoryImage(bytes),
              height: 220,
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return <pw.Widget>[
            pw.Text(
              '현장관리 도우미 점검 보고서',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            _pdfField('보고서 번호', record.recordNo),
            _pdfField('현장명', record.siteName),
            _pdfField('점검 일시', dateLabel),
            _pdfField('점검자', record.inspector),
            _pdfField('점검 구역/위치', record.zone),
            _pdfField('점검 분류', record.category),
            _pdfField('점검 대상', record.target),
            _pdfField('점검 내용', record.content),
            _pdfField('확인 결과', record.result),
            _pdfField('조치 필요사항', record.actionNeeded),
            _pdfField('비고', record.remarks),
            pw.SizedBox(height: 12),
            pw.Text(
              '사진',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if (imageWidgets.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text('첨부된 사진 없음'),
              )
            else
              ...imageWidgets,
          ];
        },
      ),
    );

    final downloads = await getDownloadsDirectory();
    final externalDir = await getExternalStorageDirectory();
    final docsDir = await getApplicationDocumentsDirectory();
    final baseDir = downloads ?? externalDir ?? docsDir;

    final safeRecordNo = record.recordNo.replaceAll('/', '-');
    final file = File('${baseDir.path}/$safeRecordNo.pdf');

    await file.writeAsBytes(await pdf.save(), flush: true);
    return file;
  }

  static pw.Widget _pdfField(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }
}

class ApiService {
  static Future<SttResponseData> uploadAudio({
    required String serverUrl,
    required String audioFilePath,
  }) async {
    final url = serverUrl.trim();
    if (url.isEmpty) {
      throw Exception('서버 URL이 비어 있음');
    }

    final normalized =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final uri = Uri.parse('$normalized/transcribe');

    final request = http.MultipartRequest('POST', uri)
      ..fields['language'] = 'ko'
      ..fields['beam_size'] = '5'
      ..files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      String message = 'STT 업로드 실패 (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (map['text'] ?? '').toString();
    final language = (map['language'] ?? '').toString();

    double? probability;
    final rawProbability = map['language_probability'];
    if (rawProbability is num) {
      probability = rawProbability.toDouble();
    }

    return SttResponseData(
      rawText: text,
      cleanText: text,
      language: language,
      languageProbability: probability,
    );
  }
}

String buildRecordNo(List<InspectionRecord> records) {
  final now = DateTime.now();
  final prefix = DateFormat('yyyyMMdd').format(now);
  final todayCount =
      records.where((e) => e.recordNo.startsWith(prefix)).length + 1;
  return '$prefix-${todayCount.toString().padLeft(3, '0')}';
}

String buildRecordTitle({
  required String siteName,
  required String zone,
  required String recordNo,
}) {
  final parts =
      <String>[siteName.trim(), zone.trim()].where((e) => e.isNotEmpty).toList();

  if (parts.isEmpty) {
    return '점검기록 $recordNo';
  }

  return '${parts.join(' / ')} ($recordNo)';
}

String nowLabel() {
  return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
}

String formatCreatedAt(String createdAt) {
  if (createdAt.trim().isEmpty) {
    return '-';
  }

  try {
    final dt = DateTime.parse(createdAt).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  } catch (_) {
    return createdAt.replaceAll('T', ' ');
  }
}

Future<void> showPermissionDeniedDialog(
  BuildContext context,
  String title,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      );
    },
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('현장관리 도우미')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.engineering, size: 88, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              '현장관리 도우미',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '녹음 · STT · 사진첨부 · PDF 저장',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              '기본 서버: ${AppConfig.defaultBaseUrl}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BasicInfoScreen()),
                  );
                },
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('점검 기록 시작', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.list_alt),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordListScreen()),
                  );
                },
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('점검 기록 조회', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BasicInfoScreen extends StatefulWidget {
  const BasicInfoScreen({super.key});

  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _siteNameController = TextEditingController();
  final _inspectionDateTimeController =
      TextEditingController(text: nowLabel());
  final _inspectorController = TextEditingController();
  final _zoneController = TextEditingController();
  final _serverUrlController = TextEditingController();

  String _category = '안전';

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    _serverUrlController.text = await StorageService.loadServerUrl();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _inspectionDateTimeController.dispose();
    _inspectorController.dispose();
    _zoneController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await StorageService.saveServerUrl(_serverUrlController.text.trim());

    final data = BasicInfoData(
      siteName: _siteNameController.text.trim(),
      inspectionDateTime: _inspectionDateTimeController.text.trim(),
      inspector: _inspectorController.text.trim(),
      category: _category,
      zone: _zoneController.text.trim(),
      serverUrl: _serverUrlController.text.trim(),
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordScreen(info: data)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기본정보 입력')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _siteNameController,
                decoration: const InputDecoration(labelText: '현장명'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '현장명을 입력하세요.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _inspectionDateTimeController,
                decoration: const InputDecoration(labelText: '점검일시'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '점검일시를 입력하세요.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _inspectorController,
                decoration: const InputDecoration(labelText: '점검자'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '점검자를 입력하세요.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: '점검분류'),
                items: const [
                  DropdownMenuItem(value: '안전', child: Text('안전')),
                  DropdownMenuItem(value: '품질', child: Text('품질')),
                  DropdownMenuItem(value: '공정', child: Text('공정')),
                  DropdownMenuItem(value: '환경', child: Text('환경')),
                  DropdownMenuItem(value: '기타', child: Text('기타')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _zoneController,
                decoration: const InputDecoration(labelText: '점검 구역/위치'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '점검 구역/위치를 입력하세요.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'STT 서버 URL',
                  helperText:
                      '에뮬레이터는 기본값 사용 가능 / 실제 폰 테스트 시 PC IP 또는 배포 URL 입력',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '서버 URL을 입력하세요.' : null,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.mic),
                onPressed: _goNext,
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('녹음 화면으로 이동', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordScreen extends StatefulWidget {
  final BasicInfoData info;

  const RecordScreen({super.key, required this.info});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  bool _isUploading = false;

  String? _audioPath;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      return true;
    }

    if (!mounted) return false;

    await showPermissionDeniedDialog(
      context,
      '마이크 권한 필요',
      '녹음 기능을 사용하려면 마이크 권한이 필요합니다.',
    );
    return false;
  }

  Future<void> _startRecording() async {
    final ok = await _ensureMicPermission();
    if (!ok) return;

    final tempDir = await getTemporaryDirectory();
    final fileName = 'inspection_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '${tempDir.path}/$fileName';

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _timer?.cancel();
    _seconds = 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;

      setState(() => _seconds += 1);

      if (_seconds >= 60) {
        await _stopRecording(showMessage: true);
      }
    });

    setState(() {
      _isRecording = true;
      _audioPath = path;
    });
  }

  Future<void> _stopRecording({bool showMessage = false}) async {
    _timer?.cancel();
    final savedPath = await _audioRecorder.stop();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      if (savedPath != null && savedPath.isNotEmpty) {
        _audioPath = savedPath;
      }
    });

    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('권장 최대 녹음시간 60초에 도달하여 녹음을 종료함.')),
      );
    }
  }

  Future<void> _resetRecording() async {
    _timer?.cancel();

    if (_isRecording) {
      await _audioRecorder.stop();
    }

    if (_audioPath != null) {
      final file = File(_audioPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _audioPath = null;
      _seconds = 0;
    });
  }

  Future<void> _uploadAudio() async {
    if (_audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 녹음을 완료하세요.')),
      );
      return;
    }

    final file = File(_audioPath!);
    if (!await file.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('녹음 파일을 찾을 수 없음. 재녹음 후 다시 시도하세요.')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final sttData = await ApiService.uploadAudio(
        serverUrl: widget.info.serverUrl,
        audioFilePath: _audioPath!,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SttReviewScreen(
            info: widget.info,
            sttData: sttData,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('STT 업로드 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('녹음')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.mic,
              size: 96,
              color: _isRecording ? Colors.red : Colors.blue,
            ),
            const SizedBox(height: 12),
            Text(
              _isRecording ? '녹음 중' : (_audioPath == null ? '녹음 대기' : '녹음 완료'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(timeLabel, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            const Text('녹음 최대 60초 권장'),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('현장명: ${widget.info.siteName}'),
                    Text('점검자: ${widget.info.inspector}'),
                    Text('구역/위치: ${widget.info.zone}'),
                    Text('분류: ${widget.info.category}'),
                    const SizedBox(height: 6),
                    Text(
                      '서버: ${widget.info.serverUrl}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (!_isRecording && _audioPath == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.fiber_manual_record),
                  onPressed: _startRecording,
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('녹음 시작', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            if (_isRecording)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined),
                  onPressed: () => _stopRecording(),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('녹음 종료', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            if (!_isRecording && _audioPath != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: _resetRecording,
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('재녹음', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: _isUploading ? null : _uploadAudio,
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _isUploading ? '업로드 중...' : '업로드 및 STT 실행',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SttReviewScreen extends StatefulWidget {
  final BasicInfoData info;
  final SttResponseData sttData;

  const SttReviewScreen({
    super.key,
    required this.info,
    required this.sttData,
  });

  @override
  State<SttReviewScreen> createState() => _SttReviewScreenState();
}

class _SttReviewScreenState extends State<SttReviewScreen> {
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _textController;
  final List<String> _imagePaths = <String>[];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.sttData.cleanText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      return true;
    }

    if (!mounted) return false;

    await showPermissionDeniedDialog(
      context,
      '카메라 권한 필요',
      '사진 촬영 기능을 사용하려면 카메라 권한이 필요합니다.',
    );
    return false;
  }

  Future<void> _pickFromCamera() async {
    final ok = await _ensureCameraPermission();
    if (!ok) return;

    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (file != null && mounted) {
      setState(() => _imagePaths.add(file.path));
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (file != null && mounted) {
      setState(() => _imagePaths.add(file.path));
    }
  }

  Future<void> _showImageSourceSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('카메라 촬영'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('갤러리에서 선택'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _goDraft() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDraftScreen.createFromStt(
          info: widget.info,
          cleanedText: _textController.text.trim(),
          imagePaths: _imagePaths,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langInfo = widget.sttData.language.isEmpty
        ? ''
        : widget.sttData.languageProbability == null
            ? widget.sttData.language
            : '${widget.sttData.language} (${widget.sttData.languageProbability!.toStringAsFixed(2)})';

    return Scaffold(
      appBar: AppBar(title: const Text('STT 결과 확인')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (langInfo.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '감지 언어: $langInfo',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  labelText: '다듬어진 텍스트',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '첨부 이미지 (${_imagePaths.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: _imagePaths.isEmpty
                  ? const Center(child: Text('첨부된 이미지 없음'))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final path = _imagePaths[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(path),
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _imagePaths.removeAt(index));
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: _imagePaths.length,
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.image_outlined),
                onPressed: _showImageSourceSelector,
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('이미지 추가', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.description_outlined),
                onPressed: _goDraft,
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('보고서 초안 생성', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportDraftScreen extends StatefulWidget {
  final InspectionRecord? existingRecord;
  final BasicInfoData? info;
  final String? cleanedText;
  final List<String>? imagePaths;

  const ReportDraftScreen._({
    super.key,
    this.existingRecord,
    this.info,
    this.cleanedText,
    this.imagePaths,
  });

  factory ReportDraftScreen.createFromStt({
    required BasicInfoData info,
    required String cleanedText,
    required List<String> imagePaths,
  }) {
    return ReportDraftScreen._(
      info: info,
      cleanedText: cleanedText,
      imagePaths: imagePaths,
    );
  }

  factory ReportDraftScreen.edit({required InspectionRecord record}) {
    return ReportDraftScreen._(existingRecord: record);
  }

  @override
  State<ReportDraftScreen> createState() => _ReportDraftScreenState();
}

class _ReportDraftScreenState extends State<ReportDraftScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _recordNoController;
  late final TextEditingController _siteNameController;
  late final TextEditingController _inspectionDateTimeController;
  late final TextEditingController _inspectorController;
  late final TextEditingController _zoneController;
  late final TextEditingController _categoryController;
  late final TextEditingController _targetController;
  late final TextEditingController _contentController;
  late final TextEditingController _resultController;
  late final TextEditingController _actionNeededController;
  late final TextEditingController _remarksController;

  List<String> _imagePaths = <String>[];

  bool _saving = false;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    _recordNoController = TextEditingController();
    _siteNameController = TextEditingController();
    _inspectionDateTimeController = TextEditingController();
    _inspectorController = TextEditingController();
    _zoneController = TextEditingController();
    _categoryController = TextEditingController();
    _targetController = TextEditingController();
    _contentController = TextEditingController();
    _resultController = TextEditingController();
    _actionNeededController = TextEditingController();
    _remarksController = TextEditingController();
    _initializeFields();
  }

  Future<void> _initializeFields() async {
    if (widget.existingRecord != null) {
      final record = widget.existingRecord!;
      _recordNoController.text = record.recordNo;
      _siteNameController.text = record.siteName;
      _inspectionDateTimeController.text = record.inspectionDateTime;
      _inspectorController.text = record.inspector;
      _zoneController.text = record.zone;
      _categoryController.text = record.category;
      _targetController.text = record.target;
      _contentController.text = record.content;
      _resultController.text = record.result;
      _actionNeededController.text = record.actionNeeded;
      _remarksController.text = record.remarks;
      _imagePaths = List<String>.from(record.imagePaths);

      if (mounted) setState(() {});
      return;
    }

    final records = await StorageService.loadRecords();
    final recordNo = buildRecordNo(records);
    final info = widget.info!;

    _recordNoController.text = recordNo;
    _siteNameController.text = info.siteName;
    _inspectionDateTimeController.text = info.inspectionDateTime;
    _inspectorController.text = info.inspector;
    _zoneController.text = info.zone;
    _categoryController.text = info.category;
    _targetController.text = '';
    _contentController.text = widget.cleanedText ?? '';
    _resultController.text = '현장 확인 결과 이상사항 확인됨';
    _actionNeededController.text = '필요 조치사항 입력 필요함';
    _remarksController.text = '';
    _imagePaths = List<String>.from(widget.imagePaths ?? <String>[]);

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recordNoController.dispose();
    _siteNameController.dispose();
    _inspectionDateTimeController.dispose();
    _inspectorController.dispose();
    _zoneController.dispose();
    _categoryController.dispose();
    _targetController.dispose();
    _contentController.dispose();
    _resultController.dispose();
    _actionNeededController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  InspectionRecord _buildRecord() {
    final recordNo = _recordNoController.text.trim();

    return InspectionRecord(
      recordNo: recordNo,
      title: buildRecordTitle(
        siteName: _siteNameController.text.trim(),
        zone: _zoneController.text.trim(),
        recordNo: recordNo,
      ),
      siteName: _siteNameController.text.trim(),
      inspectionDateTime: _inspectionDateTimeController.text.trim(),
      inspector: _inspectorController.text.trim(),
      zone: _zoneController.text.trim(),
      category: _categoryController.text.trim(),
      target: _targetController.text.trim(),
      content: _contentController.text.trim(),
      result: _resultController.text.trim(),
      actionNeeded: _actionNeededController.text.trim(),
      remarks: _remarksController.text.trim(),
      imagePaths: List<String>.from(_imagePaths),
      createdAt:
          widget.existingRecord?.createdAt ?? DateTime.now().toIso8601String(),
    );
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final record = _buildRecord();
      await StorageService.upsertRecord(record);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('점검 기록 저장 완료')),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdf() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _pdfBusy = true);

    try {
      final record = _buildRecord();
      final file = await PdfService.createPdf(record);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 저장 완료: ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _sharePdf() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _pdfBusy = true);

    try {
      final record = _buildRecord();
      final file = await PdfService.createPdf(record);

      final params = ShareParams(
        text: '현장관리 도우미 점검 보고서',
        files: [XFile(file.path)],
      );

      await SharePlus.instance.share(params);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 공유 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Widget _buildImagePreview() {
    if (_imagePaths.isEmpty) {
      return const Text('첨부된 사진 없음');
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final path = _imagePaths[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(path),
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => setState(() => _imagePaths.removeAt(index)),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _imagePaths.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existingRecord != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? '보고서 수정' : '보고서 초안')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildField(_recordNoController, '보고서 번호', enabled: false),
              const SizedBox(height: 12),
              _buildField(_siteNameController, '현장명'),
              const SizedBox(height: 12),
              _buildField(_inspectionDateTimeController, '점검 일시'),
              const SizedBox(height: 12),
              _buildField(_inspectorController, '점검자'),
              const SizedBox(height: 12),
              _buildField(_zoneController, '점검 구역/위치'),
              const SizedBox(height: 12),
              _buildField(_categoryController, '점검 분류'),
              const SizedBox(height: 12),
              _buildField(_targetController, '점검 대상'),
              const SizedBox(height: 12),
              _buildField(_contentController, '점검 내용', maxLines: 5),
              const SizedBox(height: 12),
              _buildField(_resultController, '확인 결과', maxLines: 4),
              const SizedBox(height: 12),
              _buildField(_actionNeededController, '조치 필요사항', maxLines: 4),
              const SizedBox(height: 12),
              _buildField(_remarksController, '비고', maxLines: 3),
              const SizedBox(height: 16),
              const Text('사진', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildImagePreview(),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                onPressed: _saving ? null : _saveRecord,
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _saving ? '저장 중...' : '기록 저장',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _pdfBusy ? null : _savePdf,
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _pdfBusy ? 'PDF 처리 중...' : 'PDF 저장',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.share),
                onPressed: _pdfBusy ? null : _sharePdf,
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('PDF 공유', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      validator: (value) {
        if (!enabled) return null;
        if (value == null || value.trim().isEmpty) {
          return '$label을(를) 입력하세요.';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class RecordListScreen extends StatefulWidget {
  const RecordListScreen({super.key});

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  late Future<List<InspectionRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = StorageService.loadRecords();
  }

  Future<void> _reload() async {
    setState(() {
      _future = StorageService.loadRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('점검 기록 조회')),
      body: FutureBuilder<List<InspectionRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data ?? <InspectionRecord>[];

          if (records.isEmpty) {
            return const Center(child: Text('저장된 점검 기록이 없음'));
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final record = records[index];

                return ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  title: Text(
                    record.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '등록일시: ${formatCreatedAt(record.createdAt)}\n점검자: ${record.inspector}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RecordDetailScreen(recordNo: record.recordNo),
                      ),
                    );
                    await _reload();
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: records.length,
            ),
          );
        },
      ),
    );
  }
}

class RecordDetailScreen extends StatefulWidget {
  final String recordNo;

  const RecordDetailScreen({super.key, required this.recordNo});

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  InspectionRecord? _record;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await StorageService.loadRecords();

    InspectionRecord? found;
    for (final item in records) {
      if (item.recordNo == widget.recordNo) {
        found = item;
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      _record = found;
      _loading = false;
    });
  }

  Future<void> _delete() async {
    await StorageService.deleteRecord(widget.recordNo);

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final record = _record;

    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('기록 상세')),
        body: const Center(child: Text('기록을 찾을 수 없음')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('기록 상세 조회'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportDraftScreen.edit(record: record),
                ),
              );
              await _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('기록 삭제'),
                        content: const Text('이 점검 기록을 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      );
                    },
                  ) ??
                  false;

              if (ok) {
                await _delete();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _detailCard('보고서 번호', record.recordNo),
          _detailCard('현장명', record.siteName),
          _detailCard('점검 일시', record.inspectionDateTime),
          _detailCard('점검자', record.inspector),
          _detailCard('점검 구역/위치', record.zone),
          _detailCard('점검 분류', record.category),
          _detailCard('점검 대상', record.target),
          _detailCard('점검 내용', record.content),
          _detailCard('확인 결과', record.result),
          _detailCard('조치 필요사항', record.actionNeeded),
          _detailCard('비고', record.remarks),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('사진', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (record.imagePaths.isEmpty)
                    const Text('첨부된 사진 없음')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: record.imagePaths
                          .map(
                            (path) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(value.isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }
}
