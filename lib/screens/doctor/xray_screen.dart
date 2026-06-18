import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:exif/exif.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/radiology_report.dart';
import '../../services/database_service.dart';
import '../../utils/api_config.dart';
import '../../utils/patient_manager.dart';
import '../../utils/theme_provider.dart';
import '../../utils/permission_helper.dart';

class XrayScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const XrayScreen({super.key, this.onBack});

  @override
  State<XrayScreen> createState() => _XrayScreenState();
}

class _XrayScreenState extends State<XrayScreen> {
  final ImagePicker _picker = ImagePicker();
  final DatabaseService _db = DatabaseService();

  XFile? _image;
  String? _imageOriginalName;
  String? _imageOriginalSize;
  String? _imageOriginalDate;
  String? _imageDimensions;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  // Results
  String? _prediction;
  String? _confidence;
  String? _heatmapImage;
  String? _finalReport;
  List<String> _ragGuidelines = [];
  bool _specialistUsed = false;

  // Selectors
  String _selectedBodyPart = 'Wrist';
  String _selectedModality = 'X-ray';
  PatientData? _selectedPatient;

  static const _bodyParts = [
    'Wrist', 'Elbow', 'Shoulder', 'Forearm', 'Hand', 'Finger', 'Humerus',
    'Chest', 'Knee', 'Hip', 'Spine', 'Ankle',
  ];
  static const _modalities = ['X-ray', 'MRI', 'CT Scan'];
  static const _muraDomains = {
    'Wrist', 'Elbow', 'Shoulder', 'Forearm', 'Hand', 'Finger', 'Humerus'
  };

  Future<void> _pickImage() async {
    try {
      final hasPermission = await checkAndRequestUploadPermission(
        context,
        isCamera: false,
      );
      if (!hasPermission) {
        setState(() => _error = 'Storage permission denied. Please allow access to pick an image.');
        return;
      }

      // ── Pick image ───────────────────────────────────────────────
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final file = File(picked.path);
        String? originalName = picked.name;
        String? originalSize;
        String? originalDate;
        String? dimensions;

        // 1. Get file size
        try {
          if (file.existsSync()) {
            final bytes = file.lengthSync();
            if (bytes < 1024) {
              originalSize = '$bytes B';
            } else if (bytes < 1024 * 1024) {
              originalSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
            } else {
              originalSize = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
            }
          }
        } catch (_) {}

        // 2. Get EXIF metadata (original date taken)
        try {
          final fileBytes = await file.readAsBytes();
          final tags = await readExifFromBytes(fileBytes);
          final dateTag = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
          if (dateTag != null) {
            final rawDate = dateTag.printable;
            final parts = rawDate.split(' ');
            if (parts.length == 2) {
              final datePart = parts[0].replaceAll(':', '-');
              final timePart = parts[1];
              final timeSubParts = timePart.split(':');
              if (timeSubParts.length >= 2) {
                int hour = int.parse(timeSubParts[0]);
                int minute = int.parse(timeSubParts[1]);
                String ampm = hour >= 12 ? 'PM' : 'AM';
                int hour12 = hour % 12;
                if (hour12 == 0) hour12 = 12;
                final minuteStr = minute.toString().padLeft(2, '0');
                originalDate = '$datePart  $hour12:$minuteStr $ampm';
              } else {
                originalDate = '$datePart  $timePart';
              }
            } else {
              originalDate = rawDate;
            }
          }
        } catch (e) {
          debugPrint('Error reading EXIF: $e');
        }

        // Fallback to last modified date if no EXIF date
        if (originalDate == null) {
          try {
            final lastModified = file.lastModifiedSync();
            originalDate = DateFormat('yyyy-MM-dd  hh:mm a').format(lastModified);
          } catch (_) {}
        }

        // 3. Get image dimensions
        try {
          final fileBytes = await file.readAsBytes();
          final ui.Codec codec = await ui.instantiateImageCodec(fileBytes);
          final ui.FrameInfo frameInfo = await codec.getNextFrame();
          dimensions = '${frameInfo.image.width} × ${frameInfo.image.height}';
        } catch (e) {
          debugPrint('Error reading dimensions: $e');
        }

        setState(() {
          _image = picked;
          _imageOriginalName = originalName;
          _imageOriginalSize = originalSize;
          _imageOriginalDate = originalDate;
          _imageDimensions = dimensions;
          _prediction = null;
          _confidence = null;
          _heatmapImage = null;
          _finalReport = null;
          _ragGuidelines = [];
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  Future<void> _analyzeImage() async {
    if (_image == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _prediction = null;
      _confidence = null;
      _heatmapImage = null;
      _finalReport = null;
      _ragGuidelines = [];
    });

    try {
      final uri = Uri.parse(ApiConfig.xrayApiUrl);
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _image!.path,
        contentType: MediaType('image', 'jpeg'),
      ));
      request.fields['body_part'] = _selectedBodyPart;
      request.fields['modality'] = _selectedModality;
      request.fields['api_key'] = ApiConfig.openRouterApiKey;

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(body);
        setState(() {
          _prediction = data['prediction']?.toString();
          _confidence = data['confidence']?.toString();
          _heatmapImage = data['heatmap_image']?.toString();
          _finalReport = data['final_report']?.toString();
          _specialistUsed = data['specialist_used'] == true;
          final rawGuidelines = data['rag_guidelines'];
          if (rawGuidelines is List) {
            _ragGuidelines = rawGuidelines.map((e) => e.toString()).toList();
          }
        });

        // Auto-save if a patient is selected
        if (_selectedPatient != null) {
          await _saveReport();
        }
      } else {
        setState(() => _error = 'Server error (${streamedResponse.statusCode})');
      }
    } on Exception catch (e) {
      setState(() => _error =
          'Connection failed: $e\n\nMake sure the backend server is running and the IP in api_config.dart matches your PC.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveReport() async {
    if (_selectedPatient == null || _prediction == null) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final doctorSnap = user == null
          ? null
          : await FirebaseFirestore.instance
              .collection('doctors')
              .doc(user.uid)
              .get();
      final doctorName =
          doctorSnap?.data()?['fullName'] as String? ?? 'Doctor';

      final report = RadiologyReport(
        id: '',
        patientId: _selectedPatient!.id,
        patientName: _selectedPatient!.name,
        doctorId: user?.uid ?? '',
        doctorName: doctorName,
        modality: _selectedModality,
        bodyPart: _selectedBodyPart,
        prediction: _prediction ?? '',
        confidence: _confidence ?? '',
        finalReport: _finalReport ?? '',
        ragGuidelines: _ragGuidelines,
        heatmapBase64: _heatmapImage,
        specialistUsed: _specialistUsed,
        createdAt: DateTime.now(),
      );

      await _db.saveRadiologyReport(
        patientId: _selectedPatient!.id,
        report: report,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved for ${_selectedPatient!.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showHistorySheet() {
    if (_selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a patient first to view history')),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => _HistorySheet(
          patientId: _selectedPatient!.id,
          patientName: _selectedPatient!.name,
          isDark: isDark,
          scrollController: controller,
        ),
      ),
    );
  }

  Color _resultColor() {
    if (_prediction == null) return const Color(0xFF00BCD4);
    final p = _prediction!.toLowerCase();
    if (p.contains('abnormal') || p.contains('positive') || p.contains('fracture')) {
      return Colors.red;
    }
    if (p.contains('normal') || p.contains('negative')) return Colors.green;
    return const Color(0xFF00BCD4);
  }

  void _showHeatmapDialog() {
    if (_heatmapImage == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.card(isDark),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Grad-CAM Heatmap',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text(isDark),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Image.memory(base64Decode(_heatmapImage!), fit: BoxFit.contain),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BCD4)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppTheme.bg(isDark);
    final cardColor = AppTheme.card(isDark);
    final textColor = AppTheme.text(isDark);
    final patients = PatientManager().myPatients;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card(isDark),
        elevation: 0,
        title: const Text(
          'X-Ray Analysis',
          style: TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.text(isDark)),
          onPressed: () => widget.onBack != null ? widget.onBack!() : Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFF00BCD4)),
            tooltip: 'Past Reports',
            onPressed: _showHistorySheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Patient selector ───────────────────────────────────
            _card(
              cardColor: cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient (optional)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.sub(isDark))),
                  const SizedBox(height: 6),
                  DropdownButton<PatientData?>(
                    value: _selectedPatient,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: AppTheme.card(isDark),
                    style: TextStyle(color: textColor, fontSize: 13),
                    hint: Text('Select patient to link report',
                        style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 13)),
                    onChanged: (v) => setState(() => _selectedPatient = v),
                    items: [
                      DropdownMenuItem<PatientData?>(
                        value: null,
                        child: Text('— No patient —',
                            style: TextStyle(
                                color: AppTheme.sub(isDark))),
                      ),
                      ...patients.map((p) => DropdownMenuItem<PatientData?>(
                            value: p,
                            child: Text(p.name),
                          )),
                    ],
                  ),
                  if (_selectedPatient != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Report will be saved to ${_selectedPatient!.name}\'s profile',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF00BCD4)),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Image preview ──────────────────────────────────────
            _card(
              cardColor: cardColor,
              child: _image != null
                  ? _buildFileDetails(File(_image!.path), isDark)
                  : GestureDetector(
                      onTap: _isLoading ? null : _pickImage,
                      child: Column(children: [
                        const Icon(Icons.image_search, size: 100, color: Color(0xFF00BCD4)),
                        const SizedBox(height: 16),
                        Text('Select an X-ray / MRI / CT image',
                            style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.grey[400] : Colors.grey[700])),
                      ]),
                    ),
            ),

            const SizedBox(height: 16),

            // ── Selectors ──────────────────────────────────────────
            Row(children: [
              Expanded(child: _buildDropdown('Body Part', _bodyParts, _selectedBodyPart,
                  (v) => setState(() => _selectedBodyPart = v!), isDark, textColor)),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown('Modality', _modalities, _selectedModality,
                  (v) => setState(() => _selectedModality = v!), isDark, textColor)),
            ]),

            const SizedBox(height: 8),

            // CNN badge
            if (_selectedModality == 'X-ray' && _muraDomains.contains(_selectedBodyPart))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Specialist CNN will be used for this body part',
                    style: TextStyle(fontSize: 12, color: Colors.blue)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Generalist AI (MedGemma) will be used',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),

            const SizedBox(height: 16),

            // ── Action buttons ─────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Pick Image'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00BCD4),
                  side: const BorderSide(color: Color(0xFF00BCD4)),
                ),
                onPressed: _isLoading ? null : _pickImage,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.science),
                label: const Text('Analyze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  foregroundColor: Colors.white,
                ),
                onPressed: (_image != null && !_isLoading) ? _analyzeImage : null,
              ),
            ]),

            const SizedBox(height: 16),

            // ── Loading / saving ───────────────────────────────────
            if (_isLoading)
              const Center(
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Analyzing image — this may take up to 60 seconds…',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),

            if (_isSaving)
              const Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Saving report…',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),

            // ── Error ──────────────────────────────────────────────
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),

            // ── CNN result ─────────────────────────────────────────
            if (_prediction != null) ...[
              const SizedBox(height: 12),
              _card(
                cardColor: cardColor,
                borderColor: _resultColor(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.analytics, color: _resultColor()),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _specialistUsed ? 'Specialist CNN Result' : 'AI Analysis Result',
                        style: TextStyle(
                            color: _resultColor(), fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('Finding: $_prediction',
                      style: TextStyle(fontSize: 15, color: textColor)),
                  if (_confidence != null)
                    Text('Confidence: $_confidence',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.sub(isDark))),
                  if (_heatmapImage != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.image),
                        label: const Text('View Grad-CAM Heatmap'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _resultColor(),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _showHeatmapDialog,
                      ),
                    ),
                  ],
                ]),
              ),
            ],

            // ── Doctor's report ────────────────────────────────────
            if (_finalReport != null && _finalReport!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text("Doctor's Report",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
              const SizedBox(height: 8),
              _card(
                cardColor: cardColor,
                child: MarkdownBody(
                  data: _finalReport!,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 14, height: 1.6, color: textColor),
                    strong: const TextStyle(fontWeight: FontWeight.bold),
                    h3: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ),
              ),
            ],

            // ── RAG guidelines ─────────────────────────────────────
            if (_ragGuidelines.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Clinical Guidelines (RAG)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
              const SizedBox(height: 8),
              ..._ragGuidelines.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Reference ${e.key + 1}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF00BCD4)),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(e.value,
                              style: TextStyle(
                                  fontSize: 13, color: textColor, height: 1.5)),
                        )
                      ],
                    ),
                  )),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFileDetails(File file, bool isDark) {
    final fileName = _imageOriginalName ?? file.path.split(Platform.isWindows ? '\\' : '/').last;
    final fileSizeStr = _imageOriginalSize ?? 'Unknown size';
    final fileDateStr = _imageOriginalDate ?? 'Unknown date';
    final fileDimensions = _imageDimensions;

    return InkWell(
      onTap: () => _showFullImageDialog(context, file, isDark),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          // Thumbnail preview
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.insert_drive_file,
                  size: 40,
                  color: Color(0xFF00BCD4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.text(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.sd_storage_outlined, size: 14, color: Color(0xFF00BCD4)),
                    const SizedBox(width: 4),
                    Text(
                      fileSizeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.sub(isDark),
                      ),
                    ),
                    if (fileDimensions != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.aspect_ratio, size: 14, color: Color(0xFF00BCD4)),
                      const SizedBox(width: 4),
                      Text(
                        fileDimensions,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.sub(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Color(0xFF00BCD4)),
                    const SizedBox(width: 4),
                    Text(
                      fileDateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.sub(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // View icon
          const Icon(Icons.zoom_in, color: Color(0xFF00BCD4), size: 20),
        ],
      ),
    );
  }

  void _showFullImageDialog(BuildContext context, File file, bool isDark) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Color cardColor, required Widget child, Color? borderColor}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? const Color(0xFF00BCD4).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
    bool isDark,
    Color textColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.sub(isDark))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.bg(isDark) : AppTheme.card(isDark),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppTheme.card(isDark),
            style: TextStyle(color: textColor, fontSize: 13),
            onChanged: onChanged,
            items: items
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ── Past reports bottom sheet ──────────────────────────────────────────────
class _HistorySheet extends StatelessWidget {
  final String patientId;
  final String patientName;
  final bool isDark;
  final ScrollController scrollController;

  const _HistorySheet({
    required this.patientId,
    required this.patientName,
    required this.isDark,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(isDark);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.history, color: Color(0xFF00BCD4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reports for $patientName',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    color: AppTheme.sub(isDark)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('patients')
                .doc(patientId)
                .collection('radiology_reports')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text('No saved reports yet',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45)),
                );
              }
              final docs = snapshot.data!.docs;
              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final report = RadiologyReport.fromFirestore(docs[i]);
                  return _ReportCard(
                      report: report, isDark: isDark, textColor: textColor);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final RadiologyReport report;
  final bool isDark;
  final Color textColor;

  const _ReportCard(
      {required this.report, required this.isDark, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final isAbnormal = report.prediction.toLowerCase().contains('abnormal') ||
        report.prediction.toLowerCase().contains('fracture');
    final badgeColor = isAbnormal ? Colors.red : Colors.green;

    return GestureDetector(
      onTap: () => _showReportDialog(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.bg(isDark) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.image_search, color: Color(0xFF00BCD4), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${report.bodyPart} — ${report.modality}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: textColor)),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(report.createdAt),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                report.prediction,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    final isDarkLocal = Theme.of(context).brightness == Brightness.dark;
    final tc = isDarkLocal ? Colors.white : Colors.black87;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor:
            isDarkLocal ? AppTheme.card(isDark) : Colors.white,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${report.bodyPart} — ${report.modality}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: tc)),
              const SizedBox(height: 4),
              Text(_formatDate(report.createdAt),
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          isDarkLocal ? Colors.white54 : Colors.black45)),
              const Divider(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(
                        data: report.finalReport.isNotEmpty
                            ? report.finalReport
                            : '_No report text available_',
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                              fontSize: 13, height: 1.6, color: tc),
                          strong: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (report.heatmapBase64 != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.image),
                            label: const Text('View Grad-CAM Heatmap'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00BCD4),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Image.memory(
                                      base64Decode(report.heatmapBase64!),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BCD4)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
