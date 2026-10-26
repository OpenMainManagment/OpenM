import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class ProjectNoteScreen extends ConsumerStatefulWidget {
  const ProjectNoteScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  final String companyId;
  final String companyName;

  @override
  ConsumerState<ProjectNoteScreen> createState() => _ProjectNoteScreenState();
}

class _ProjectNoteScreenState extends ConsumerState<ProjectNoteScreen> {
  static const String _draftFileName = 'project_note_autosave.txt';
  static const String _ocrFileName = 'project_note_extracted_text.txt';

  final TextEditingController _projectNameCtrl = TextEditingController();
  final TextEditingController _peopleTextCtrl = TextEditingController();
  final TextEditingController _descriptionTextCtrl = TextEditingController();
  final TextEditingController _extraInfoTextCtrl = TextEditingController();

  final List<List<Offset>> _peopleStrokes = [];
  final List<List<Offset>> _descriptionStrokes = [];
  final List<List<Offset>> _extraStrokes = [];

  bool _peopleTextMode = false;
  bool _descriptionTextMode = false;
  bool _extraTextMode = false;

  bool _peopleMoveMode = false;
  bool _descriptionMoveMode = false;
  bool _extraMoveMode = false;

  bool _saving = false;
  bool _loadingCustomers = false;
  String? _projectId;
  String? _dokuFolderId;
  String? _draftFileId;
  CompanyDto? _customerCompany;
  int? _selectedProjectLeadIndex;
  DateTime? _lastSavedAt;
  String _peopleOcrText = '';
  String _descriptionOcrText = '';
  String _extraOcrText = '';

  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    _loadCustomerCompany();
    _autosaveTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _autosave(),
    );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _projectNameCtrl.dispose();
    _peopleTextCtrl.dispose();
    _descriptionTextCtrl.dispose();
    _extraInfoTextCtrl.dispose();
    super.dispose();
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Future<void> _editProject() async {
    // This would navigate to an edit project screen
    // For now we'll show a simple dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Project'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Project Name'),
                controller: _projectNameCtrl,
              ),
              // Add more fields for editing project details
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _defaultProjectName() {
    final stamp = DateTime.now().toIso8601String().split('T').first;
    return 'Project $stamp';
  }

  Future<void> _ensureProjectExists() async {
    if (_projectId != null) {
      return;
    }
    final name = _projectNameCtrl.text.trim().isEmpty
        ? _defaultProjectName()
        : _projectNameCtrl.text.trim();
    await _applySelectedProjectLead();
    final project = await ref
        .read(apiClientProvider)
        .createProjectForClientCompany(
          clientCompanyId: widget.companyId,
          name: name,
        );
    _projectId = project.id;
    if (_projectNameCtrl.text.trim().isEmpty) {
      _projectNameCtrl.text = name;
    }
  }

  Future<void> _loadCustomerCompany() async {
    setState(() {
      _loadingCustomers = true;
    });

    try {
      final companies = await ref.read(apiClientProvider).clientCompanies();
      final company = companies
          .where((item) => item.id == widget.companyId)
          .cast<CompanyDto?>()
          .firstWhere((item) => item != null, orElse: () => null);

      if (!mounted) {
        return;
      }

      final fallbackIndex = (company != null && company.customers.isNotEmpty)
          ? 0
          : null;
      final mainIndex = company == null || company.mainCustomerId == null
          ? -1
          : company.customers.indexWhere((c) => c.id == company.mainCustomerId);

      setState(() {
        _customerCompany = company;
        _selectedProjectLeadIndex = mainIndex >= 0 ? mainIndex : fallbackIndex;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _customerCompany = null;
        _selectedProjectLeadIndex = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCustomers = false;
        });
      }
    }
  }

  Map<String, dynamic> _customerToPayload(CompanyCustomerDto customer) {
    return {
      'first_name': customer.firstName,
      'last_name': customer.lastName,
      'gender': customer.gender,
      'email': customer.email,
      'role': customer.role,
      'phone_number': customer.phoneNumber,
      'mobile_number': customer.mobileNumber,
      // Only include image_url if it exists
      if (customer.imageUrl != null && customer.imageUrl!.isNotEmpty) 
        'image_url': customer.imageUrl,
    }..removeWhere((key, value) => value == null || value == '');
  }

  Future<void> _applySelectedProjectLead() async {
    final company = _customerCompany;
    if (company == null || company.customers.isEmpty) {
      return;
    }

    var selectedIndex = _selectedProjectLeadIndex;
    if (selectedIndex == null || selectedIndex < 0) {
      selectedIndex = 0;
    }
    if (selectedIndex >= company.customers.length) {
      selectedIndex = company.customers.length - 1;
    }

    final currentMainIndex = company.mainCustomerId == null
        ? -1
        : company.customers.indexWhere((c) => c.id == company.mainCustomerId);
    if (currentMainIndex == selectedIndex) {
      return;
    }

    final customersPayload = company.customers
        .map(_customerToPayload)
        .toList(growable: false);

    final updated = await ref
        .read(apiClientProvider)
        .updateClientCompany(
          clientCompanyId: company.id,
          customers: customersPayload,
          headCustomerIndex: selectedIndex,
        );
    if (!mounted) {
      return;
    }
    final refreshedMainIndex = updated.mainCustomerId == null
        ? -1
        : updated.customers.indexWhere((c) => c.id == updated.mainCustomerId);
    setState(() {
      _customerCompany = updated;
      _selectedProjectLeadIndex = refreshedMainIndex >= 0
          ? refreshedMainIndex
          : 0;
    });
  }

  Future<void> _openAddCustomerDialog() async {
    final company = _customerCompany;
    if (company == null) {
      return;
    }
    if (company.customers.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 3 customers per client company.'),
        ),
      );
      return;
    }

    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    var gender = 'not_specified';

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add customer person'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: lastNameCtrl,
                      decoration: const InputDecoration(labelText: 'Last name'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(
                          value: 'not_specified',
                          child: Text('Not specified'),
                        ),
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(
                          value: 'diverse',
                          child: Text('Diverse'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          gender = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: roleCtrl,
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mobileCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (firstNameCtrl.text.trim().isEmpty &&
                      lastNameCtrl.text.trim().isEmpty) {
                    return;
                  }

                  final updatedCustomersPayload = [
                    ...company.customers.map(_customerToPayload),
                    {
                      'first_name': firstNameCtrl.text.trim(),
                      'last_name': lastNameCtrl.text.trim(),
                      'gender': gender,
                      'email': emailCtrl.text.trim(),
                      'role': roleCtrl.text.trim(),
                      'phone_number': phoneCtrl.text.trim(),
                      'mobile_number': mobileCtrl.text.trim(),
                      'image_url': '', // Add image_url to match backend expectations
                    }..removeWhere(
                      (key, value) => value == '',
                    ),
                  ];

                  var headIndex = _selectedProjectLeadIndex;
                  if (headIndex == null || headIndex < 0) {
                    headIndex = updatedCustomersPayload.length - 1;
                  }
                  if (headIndex >= updatedCustomersPayload.length) {
                    headIndex = updatedCustomersPayload.length - 1;
                  }

                  try {
                    print('DEBUG: About to call updateCustomerCompany with:');
                    print('  company.id: ${company.id}');
                    print('  customers count: ${updatedCustomersPayload.length}');
                    print('  headIndex: $headIndex');
                    
                    final updated = await ref
                        .read(apiClientProvider)
                        .updateClientCompany(
                          clientCompanyId: company.id,
                          customers: updatedCustomersPayload,
                          headCustomerIndex: headIndex,
                        );

                    if (!mounted || !dialogContext.mounted) {
                      return;
                    }

                    final refreshedMainIndex = updated.mainCustomerId == null
                        ? -1
                        : updated.customers.indexWhere(
                            (c) => c.id == updated.mainCustomerId,
                          );

                    setState(() {
                      _customerCompany = updated;
                      _selectedProjectLeadIndex = refreshedMainIndex >= 0
                          ? refreshedMainIndex
                          : 0;
                    });

                    Navigator.of(dialogContext).pop();
                  } catch (error, stackTrace) {
                    print('DEBUG: Error adding customer - $error');
                    print('DEBUG: Stack trace - $stackTrace');
                    if (!mounted) {
                      return;
                    }
                    // Provide more specific error feedback
                    String message = 'Could not add customer.';
                    if (error.toString().contains('maximum')) {
                      message = 'Maximum 3 customers per client company.';
                    } else if (error.toString().contains('400')) {
                      message = 'Invalid data provided for customer.';
                    } else if (error.toString().contains('404')) {
                      message = 'Client company not found.';
                    } else if (error.toString().contains('403')) {
                      message = 'Permission denied to add customer.';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                },
                child: const Text('Add customer'),
              ),
            ],
          ),
        ),
      );
    } finally {
      firstNameCtrl.dispose();
      lastNameCtrl.dispose();
      emailCtrl.dispose();
      roleCtrl.dispose();
      phoneCtrl.dispose();
      mobileCtrl.dispose();
    }
  }

  Widget _buildProjectLeadRow() {
    if (_loadingCustomers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final company = _customerCompany;
    final customers = company?.customers ?? const <CompanyCustomerDto>[];
    final hasCustomers = customers.isNotEmpty;
    final selected = _selectedProjectLeadIndex;
    final normalizedSelected =
        selected == null || selected < 0 || selected >= customers.length
        ? null
        : selected;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('${customers.length}_${normalizedSelected ?? -1}'),
            initialValue: normalizedSelected,
            decoration: const InputDecoration(
              labelText: 'Project lead',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var i = 0; i < customers.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: Text(
                    customers[i].fullName.isEmpty
                        ? 'Unnamed customer'
                        : customers[i].fullName,
                  ),
                ),
            ],
            onChanged: hasCustomers
                ? (value) {
                    setState(() {
                      _selectedProjectLeadIndex = value;
                    });
                  }
                : null,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          child: FilledButton.tonalIcon(
            onPressed: _openAddCustomerDialog,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add customer'),
          ),
        ),
      ],
    );
  }

  Future<void> _ensureDokuFolderExists() async {
    if (_projectId == null) {
      return;
    }
    if (_dokuFolderId != null) {
      return;
    }

    final api = ref.read(apiClientProvider);
    final folders = await api.folders(_projectId!, includeAll: true);
    final doku = folders
        .where((f) => f.name.trim().toLowerCase() == 'doku')
        .toList();
    if (doku.isNotEmpty) {
      _dokuFolderId = doku.first.id;
      return;
    }

    final created = await api.createFolder(
      projectId: _projectId!,
      name: 'Doku',
    );
    _dokuFolderId = created.id;
  }

  String _serializeDraft() {
    final payload = {
      'project_name': _projectNameCtrl.text.trim(),
      'people_text': _peopleTextCtrl.text,
      'description_text': _descriptionTextCtrl.text,
      'extra_infos_text': _extraInfoTextCtrl.text,
      'people_ocr_text': _peopleOcrText,
      'description_ocr_text': _descriptionOcrText,
      'extra_infos_ocr_text': _extraOcrText,
      'people_strokes': _peopleStrokes.map((s) => s.length).toList(),
      'description_strokes': _descriptionStrokes.map((s) => s.length).toList(),
      'extra_infos_strokes': _extraStrokes.map((s) => s.length).toList(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String> _resolveSectionText({
    required String typedText,
    required Uint8List? imageBytes,
    required String fileName,
  }) async {
    final trimmedTyped = typedText.trim();
    if (trimmedTyped.isNotEmpty) {
      return trimmedTyped;
    }
    if (imageBytes == null) {
      return '';
    }

    try {
      final extracted = await ref
          .read(apiClientProvider)
          .extractBusinessCardText(bytes: imageBytes, fileName: fileName);
      return extracted.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _autosave() async {
    if (_saving) {
      return;
    }
    if (_projectNameCtrl.text.trim().isEmpty &&
        _peopleTextCtrl.text.trim().isEmpty &&
        _descriptionTextCtrl.text.trim().isEmpty &&
        _extraInfoTextCtrl.text.trim().isEmpty &&
        _peopleStrokes.isEmpty &&
        _descriptionStrokes.isEmpty &&
        _extraStrokes.isEmpty) {
      return;
    }

    try {
      await _ensureProjectExists();
      await _ensureDokuFolderExists();
      if (_dokuFolderId == null) {
        return;
      }

      final api = ref.read(apiClientProvider);
      final bytes = utf8.encode(_serializeDraft());

      if (_draftFileId == null) {
        final files = await api.folderFiles(
          _dokuFolderId!,
          search: _draftFileName,
        );
        final existing = files
            .where((f) => f.fileName == _draftFileName)
            .toList();
        if (existing.isNotEmpty) {
          _draftFileId = existing.first.id;
        }
      }

      if (_draftFileId == null) {
        await api.uploadFile(
          folderId: _dokuFolderId!,
          bytes: bytes,
          fileName: _draftFileName,
        );
        final files = await api.folderFiles(
          _dokuFolderId!,
          search: _draftFileName,
        );
        final existing = files
            .where((f) => f.fileName == _draftFileName)
            .toList();
        if (existing.isNotEmpty) {
          _draftFileId = existing.first.id;
        }
      } else {
        await api.replaceFileContent(
          fileId: _draftFileId!,
          bytes: bytes,
          fileName: _draftFileName,
          contentType: 'text/plain',
        );
      }

      if (mounted) {
        setState(() {
          _lastSavedAt = DateTime.now();
        });
      }
    } catch (_) {
      // Autosave is best-effort and should not interrupt writing.
    }
  }

  Future<void> _exportPdf() async {
    if (_saving) {
      return;
    }

    final name = _projectNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a project name.')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _ensureProjectExists();
      await _ensureDokuFolderExists();
      if (_dokuFolderId == null) {
        throw Exception('Doku folder missing');
      }

      final peopleImage = await _renderStrokesToPng(_peopleStrokes);
      final descriptionImage = await _renderStrokesToPng(_descriptionStrokes);
      final extraImage = await _renderStrokesToPng(_extraStrokes);

      final peopleText = await _resolveSectionText(
        typedText: _peopleTextCtrl.text,
        imageBytes: peopleImage,
        fileName: 'project_note_people.png',
      );
      final descriptionText = await _resolveSectionText(
        typedText: _descriptionTextCtrl.text,
        imageBytes: descriptionImage,
        fileName: 'project_note_description.png',
      );
      final extraText = await _resolveSectionText(
        typedText: _extraInfoTextCtrl.text,
        imageBytes: extraImage,
        fileName: 'project_note_extra_infos.png',
      );

      _peopleOcrText = peopleText;
      _descriptionOcrText = descriptionText;
      _extraOcrText = extraText;

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, child: pw.Text('Project note: $name')),
            pw.SizedBox(height: 8),
            pw.Text('People'),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: peopleText.isNotEmpty
                  ? pw.Text(peopleText)
                  : (peopleImage != null
                        ? pw.Image(
                            pw.MemoryImage(peopleImage),
                            fit: pw.BoxFit.contain,
                          )
                        : pw.Text('No handwriting captured.')),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Project description'),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: descriptionText.isNotEmpty
                  ? pw.Text(descriptionText)
                  : (descriptionImage != null
                        ? pw.Image(
                            pw.MemoryImage(descriptionImage),
                            fit: pw.BoxFit.contain,
                          )
                        : pw.Text('No handwriting captured.')),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Extra infos'),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: extraText.isNotEmpty
                  ? pw.Text(extraText)
                  : (extraImage != null
                        ? pw.Image(
                            pw.MemoryImage(extraImage),
                            fit: pw.BoxFit.contain,
                          )
                        : pw.Text('No handwriting captured.')),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final api = ref.read(apiClientProvider);
      final pdfFileName =
          '${name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')}.pdf';

      final files = await api.folderFiles(_dokuFolderId!, search: pdfFileName);
      final existing = files.where((f) => f.fileName == pdfFileName).toList();
      if (existing.isEmpty) {
        await api.uploadFile(
          folderId: _dokuFolderId!,
          bytes: bytes,
          fileName: pdfFileName,
        );
      } else {
        await api.replaceFileContent(
          fileId: existing.first.id,
          bytes: bytes,
          fileName: pdfFileName,
          contentType: 'application/pdf',
        );
      }

      final ocrTextContent = [
        'Project note: $name',
        '',
        'People:',
        peopleText.isEmpty ? '(no text extracted)' : peopleText,
        '',
        'Project description:',
        descriptionText.isEmpty ? '(no text extracted)' : descriptionText,
        '',
        'Extra infos:',
        extraText.isEmpty ? '(no text extracted)' : extraText,
      ].join('\n');

      final ocrFiles = await api.folderFiles(
        _dokuFolderId!,
        search: _ocrFileName,
      );
      final existingOcrFile = ocrFiles
          .where((f) => f.fileName == _ocrFileName)
          .toList();
      if (existingOcrFile.isEmpty) {
        await api.uploadFile(
          folderId: _dokuFolderId!,
          bytes: utf8.encode(ocrTextContent),
          fileName: _ocrFileName,
        );
      } else {
        await api.replaceFileContent(
          fileId: existingOcrFile.first.id,
          bytes: utf8.encode(ocrTextContent),
          fileName: _ocrFileName,
          contentType: 'text/plain',
        );
      }

      await _autosave();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported PDF to Doku folder.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<Uint8List?> _renderStrokesToPng(List<List<Offset>> strokes) async {
    if (strokes.isEmpty) {
      return null;
    }
    const width = 1100.0;
    const height = 300.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.length < 2) {
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Widget _buildHandwriteField({
    required String title,
    required bool textMode,
    required bool moveMode,
    required TextEditingController textController,
    required List<List<Offset>> strokes,
    required VoidCallback onToggleTextMode,
    required VoidCallback onToggleMoveMode,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleTextMode,
                  tooltip: textMode
                      ? 'Switch to handwriting'
                      : 'Switch to text',
                  icon: Icon(
                    textMode ? Icons.draw_outlined : Icons.text_fields,
                  ),
                ),
                if (!textMode)
                  IconButton(
                    onPressed: onToggleMoveMode,
                    tooltip: moveMode ? 'Draw mode' : 'Move/Zoom mode',
                    icon: Icon(
                      moveMode
                          ? Icons.gesture_outlined
                          : Icons.pan_tool_alt_outlined,
                    ),
                  ),
                if (!textMode)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        strokes.clear();
                      });
                    },
                    tooltip: 'Clear drawing',
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (textMode)
              TextField(
                controller: textController,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write text here...',
                ),
              )
            else
              SizedBox(
                height: 240,
                child: InteractiveViewer(
                  panEnabled: moveMode,
                  scaleEnabled: moveMode,
                  minScale: 0.8,
                  maxScale: 4,
                  child: GestureDetector(
                    onPanStart: moveMode
                        ? null
                        : (details) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null) {
                              return;
                            }
                            final localPoint = box.globalToLocal(
                              details.globalPosition,
                            );
                            setState(() {
                              strokes.add([localPoint]);
                            });
                          },
                    onPanUpdate: moveMode
                        ? null
                        : (details) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null || strokes.isEmpty) {
                              return;
                            }
                            final localPoint = box.globalToLocal(
                              details.globalPosition,
                            );
                            setState(() {
                              strokes.last.add(localPoint);
                            });
                          },
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        color: Colors.white,
                      ),
                      child: CustomPaint(
                        painter: _StrokePainter(strokes),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _savedText() {
    if (_lastSavedAt == null) {
      return 'Not saved yet';
    }
    final t = _lastSavedAt!;
    return 'Last autosave: ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'New Project Note - ${widget.companyName}',
      onAdd: _exportPdf,
      onSettings: _openSettings,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _projectNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Project name (text field)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(_savedText()),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_saving ? 'Saving...' : 'Export PDF to Doku'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _autosave,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save now'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _editProject,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Project'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildHandwriteField(
              title: 'People',
              textMode: _peopleTextMode,
              moveMode: _peopleMoveMode,
              textController: _peopleTextCtrl,
              strokes: _peopleStrokes,
              onToggleTextMode: () => setState(() {
                _peopleTextMode = !_peopleTextMode;
              }),
              onToggleMoveMode: () => setState(() {
                _peopleMoveMode = !_peopleMoveMode;
              }),
            ),
            _buildHandwriteField(
              title: 'Project description',
              textMode: _descriptionTextMode,
              moveMode: _descriptionMoveMode,
              textController: _descriptionTextCtrl,
              strokes: _descriptionStrokes,
              onToggleTextMode: () => setState(() {
                _descriptionTextMode = !_descriptionTextMode;
              }),
              onToggleMoveMode: () => setState(() {
                _descriptionMoveMode = !_descriptionMoveMode;
              }),
            ),
            _buildHandwriteField(
              title: 'Extra infos',
              textMode: _extraTextMode,
              moveMode: _extraMoveMode,
              textController: _extraInfoTextCtrl,
              strokes: _extraStrokes,
              onToggleTextMode: () => setState(() {
                _extraTextMode = !_extraTextMode;
              }),
              onToggleMoveMode: () => setState(() {
                _extraMoveMode = !_extraMoveMode;
              }),
            ),
            const SizedBox(height: 12),
            _buildProjectLeadRow(),
          ],
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.length < 2) {
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
