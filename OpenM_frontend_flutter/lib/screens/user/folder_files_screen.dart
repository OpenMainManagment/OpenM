import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class FolderFilesScreen extends ConsumerStatefulWidget {
  const FolderFilesScreen({
    super.key,
    required this.folderId,
    required this.folderName,
    required this.projectId,
  });

  final String folderId;
  final String folderName;
  final String projectId;

  @override
  ConsumerState<FolderFilesScreen> createState() => _FolderFilesScreenState();
}

class _FolderFilesScreenState extends ConsumerState<FolderFilesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<FolderDto> _childFolders = const [];
  List<DocumentDto> _files = const [];
  AiSummaryDto? _aiSummary;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), _load);
  }

  void _clearSearch() {
    if (_searchCtrl.text.isEmpty) {
      return;
    }
    _searchCtrl.clear();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final search = _searchCtrl.text.trim().isEmpty
        ? null
        : _searchCtrl.text.trim();
    final folders = await api.folders(
      widget.projectId,
      parentFolderId: widget.folderId,
      search: search,
    );
    final files = await api.folderFiles(widget.folderId, search: search);
    final summary = await api.folderSummary(
      folderId: widget.folderId,
      projectContext: widget.folderName,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _childFolders = folders;
      _files = files;
      _aiSummary = summary;
    });
  }

  Future<void> _addFileOrFolder() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _createFileFromDemo(
                category: 'word',
                dialogTitle: 'New Word File',
              );
            },
            child: const Text('New Word File'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _createFileFromDemo(
                category: 'excel',
                dialogTitle: 'New Excel File',
              );
            },
            child: const Text('New Excel File'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _createFileFromDemo(
                category: 'powerpoint',
                dialogTitle: 'New PowerPoint File',
              );
            },
            child: const Text('New PowerPoint File'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _createFileFromDemo(category: 'other', dialogTitle: 'New File');
            },
            child: const Text('New File (Other)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _pickAndUploadFiles();
            },
            child: const Text('Upload File'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _pickAndUploadFiles(allowMultiple: true);
            },
            child: const Text('Upload Multiple Files'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await _newFolderDialog();
            },
            child: const Text('New Folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFileFromDemo({
    required String category,
    required String dialogTitle,
  }) async {
    final api = ref.read(apiClientProvider);
    final templates = await api.demoTemplates(category: category);
    if (!mounted) {
      return;
    }

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No demo templates available.')),
      );
      return;
    }

    DemoTemplateDto selectedTemplate = templates.first;
    final nameCtrl = TextEditingController(text: selectedTemplate.fileName);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: Text(dialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedTemplate.id,
                  items: templates
                      .map(
                        (template) => DropdownMenuItem<String>(
                          value: template.id,
                          child: Text(template.fileName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    final nextTemplate = templates.firstWhere(
                      (template) => template.id == value,
                    );
                    setStateDialog(() {
                      selectedTemplate = nextTemplate;
                      nameCtrl.text = nextTemplate.fileName;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Template'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'File name'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await api.createFileFromDemo(
                    folderId: widget.folderId,
                    templateId: selectedTemplate.id,
                    fileName: nameCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                  await _load();
                },
                child: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadFiles({
    bool allowMultiple = false,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
    );
    final files =
        picked?.files.where((file) => file.bytes != null).toList() ?? const [];
    if (files.isEmpty) {
      return;
    }

    final api = ref.read(apiClientProvider);
    for (final file in files) {
      await api.uploadFile(
        folderId: widget.folderId,
        bytes: file.bytes!,
        fileName: file.name,
      );
    }
    await _load();
  }

  Future<void> _newFolderDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Folder Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(apiClientProvider)
                  .createFolder(
                    projectId: widget.projectId,
                    name: nameCtrl.text.trim(),
                    parentFolderId: widget.folderId,
                  );
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Future<void> _download(String fileId) async {
    final url = ref.read(apiClientProvider).downloadUrl(fileId);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _renameFile(DocumentDto file) async {
    final ctrl = TextEditingController(text: file.fileName);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'File name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(apiClientProvider)
                  .renameFile(fileId: file.id, fileName: ctrl.text.trim());
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveFile(DocumentDto file) async {
    final folders = await ref
        .read(apiClientProvider)
        .folders(widget.projectId, includeAll: true);
    if (!mounted) {
      return;
    }

    String? selectedFolderId;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move File'),
        content: DropdownButtonFormField<String>(
          initialValue: selectedFolderId,
          items: folders
              .map(
                (f) =>
                    DropdownMenuItem<String>(value: f.id, child: Text(f.name)),
              )
              .toList(),
          onChanged: (value) {
            selectedFolderId = value;
          },
          decoration: const InputDecoration(labelText: 'Target folder'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedFolderId == null) {
                return;
              }
              await ref
                  .read(apiClientProvider)
                  .moveFile(fileId: file.id, folderId: selectedFolderId!);
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Move'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(DocumentDto file) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete ${file.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiClientProvider).deleteFile(file.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  bool _isExcelFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.xlsx');
  }

  String _columnName(int index) {
    var n = index + 1;
    var result = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  Future<void> _editExcelFile(DocumentDto file) async {
    final api = ref.read(apiClientProvider);
    try {
      final bytes = await api.downloadFileBytes(file.id);
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load Excel file.')),
          );
        }
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.isNotEmpty
          ? excel.tables.keys.first
          : 'Sheet1';
      final sheet = excel[sheetName];
      final rows = sheet.rows;

      var rowCount = rows.length;
      var colCount = 0;
      for (final row in rows) {
        if (row.length > colCount) {
          colCount = row.length;
        }
      }
      rowCount = rowCount < 10 ? 10 : rowCount;
      colCount = colCount < 6 ? 6 : colCount;
      if (rowCount > 30) {
        rowCount = 30;
      }
      if (colCount > 12) {
        colCount = 12;
      }

      final controllers = List.generate(
        rowCount,
        (r) => List.generate(colCount, (c) {
          final value = r < rows.length && c < rows[r].length
              ? rows[r][c]?.value?.toString() ?? ''
              : '';
          return TextEditingController(text: value);
        }),
      );

      var saving = false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit Excel: ${file.fileName}'),
            content: SizedBox(
              width: 900,
              height: 520,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: colCount * 140,
                  child: ListView.builder(
                    itemCount: rowCount + 1,
                    itemBuilder: (_, rowIndex) {
                      if (rowIndex == 0) {
                        return Row(
                          children: [
                            const SizedBox(width: 48),
                            ...List.generate(
                              colCount,
                              (c) => SizedBox(
                                width: 140,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    _columnName(c),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final r = rowIndex - 1;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 48,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text('${r + 1}'),
                            ),
                          ),
                          ...List.generate(
                            colCount,
                            (c) => SizedBox(
                              width: 140,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: TextField(
                                  controller: controllers[r][c],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        for (var r = 0; r < rowCount; r++) {
                          for (var c = 0; c < colCount; c++) {
                            final value = controllers[r][c].text;
                            final cell = sheet.cell(
                              CellIndex.indexByColumnRow(
                                columnIndex: c,
                                rowIndex: r,
                              ),
                            );
                            if (value.trim().isEmpty) {
                              cell.value = null;
                            } else {
                              cell.value = TextCellValue(value);
                            }
                          }
                        }
                        final encoded = excel.encode();
                        if (encoded == null) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text('Could not encode Excel file.'),
                              ),
                            );
                          }
                          setDialogState(() => saving = false);
                          return;
                        }
                        await api.replaceFileContent(
                          fileId: file.id,
                          bytes: encoded,
                          fileName: file.fileName,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                      },
                child: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      );

      for (final row in controllers) {
        for (final ctrl in row) {
          ctrl.dispose();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel edit failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Folder: ${widget.folderName}',
      onAdd: _addFileOrFolder,
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_aiSummary != null)
              Card(
                color: AppColors.aiSummaryBackground,
                child: ListTile(
                  title: const Text('AI Folder Summary'),
                  subtitle: Text(_aiSummary!.summary),
                ),
              ),
            if ((_aiSummary?.extractedTextPreview ?? '').isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Text preview: ${_aiSummary!.extractedTextPreview}',
                  ),
                ),
              ),
            if (_aiSummary != null)
              Wrap(
                spacing: 8,
                children: _aiSummary!.suggestions
                    .map((s) => Chip(label: Text(s)))
                    .toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search files and folders',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  ..._childFolders.map(
                    (folder) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(folder.name),
                        onTap: () => context.push(
                          '/folders/${folder.id}/files?name=${Uri.encodeComponent(folder.name)}&projectId=${Uri.encodeComponent(widget.projectId)}',
                        ),
                      ),
                    ),
                  ),
                  ..._files.map(
                    (file) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(file.fileName),
                        subtitle: Text(
                          file.createdAt.toIso8601String().split('T').first,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'download') {
                              _download(file.id);
                            } else if (value == 'edit_excel') {
                              _editExcelFile(file);
                            } else if (value == 'rename') {
                              _renameFile(file);
                            } else if (value == 'move') {
                              _moveFile(file);
                            } else if (value == 'delete') {
                              _deleteFile(file);
                            }
                          },
                          itemBuilder: (_) {
                            final items = <PopupMenuEntry<String>>[
                              const PopupMenuItem(
                                value: 'download',
                                child: Text('Download'),
                              ),
                            ];
                            if (_isExcelFile(file.fileName)) {
                              items.add(
                                const PopupMenuItem(
                                  value: 'edit_excel',
                                  child: Text('Edit Excel'),
                                ),
                              );
                            }
                            items.addAll(const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(value: 'move', child: Text('Move')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ]);
                            return items;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
