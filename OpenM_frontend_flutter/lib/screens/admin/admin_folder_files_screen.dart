import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminFolderFilesScreen extends ConsumerStatefulWidget {
  const AdminFolderFilesScreen({super.key});

  @override
  ConsumerState<AdminFolderFilesScreen> createState() =>
      _AdminFolderFilesScreenState();
}

class _AdminFolderFilesScreenState
    extends ConsumerState<AdminFolderFilesScreen> {
  String? _companyId;
  List<ProjectFolderTemplateDto> _folderTemplates = const [];
  List<DemoTemplateDto> _demoTemplates = const [];
  Map<String, List<ProjectFolderTemplateDemoFileDto>> _demoAssignments =
      const {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const List<String> _fallbackFolders = [
    'Angebot',
    'Auftrag',
    'Nacharbeit',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final api = ref.read(apiClientProvider);
      final companies = await api.companies();
      if (companies.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No company found.';
        });
        return;
      }

      _companyId = companies.first.id;
      final results = await Future.wait([
        api.projectFolderTemplates(_companyId!),
        api.demoTemplates(),
      ]);

      final templates = results[0] as List<ProjectFolderTemplateDto>;
      final demoTemplates = results[1] as List<DemoTemplateDto>;

      final assignments = <String, List<ProjectFolderTemplateDemoFileDto>>{};
      if (templates.isNotEmpty) {
        final loaded = await Future.wait(
          templates.map((t) => _fetchFolderTemplateDemoFiles(api, t.id)),
        );
        for (var i = 0; i < templates.length; i++) {
          assignments[templates[i].id] = loaded[i];
        }
      }

      setState(() {
        _folderTemplates = templates;
        _demoTemplates = demoTemplates;
        _demoAssignments = assignments;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<ProjectFolderTemplateDemoFileDto>> _fetchFolderTemplateDemoFiles(
    ApiClient api,
    String templateId,
  ) async {
    try {
      return await api.folderTemplateDemoFiles(templateId);
    } catch (_) {
      return const <ProjectFolderTemplateDemoFileDto>[];
    }
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    openSettingsMenu(context: context, ref: ref);
  }

  String _displayDemoName(String demoTemplateId) {
    final fromCatalog = _demoTemplates.where((d) => d.id == demoTemplateId);
    if (fromCatalog.isNotEmpty) {
      return fromCatalog.first.fileName;
    }
    final parts = demoTemplateId.split('/');
    return parts.isNotEmpty ? parts.last : demoTemplateId;
  }

  List<String> get _effectiveFolders {
    if (_folderTemplates.isEmpty) {
      return _fallbackFolders;
    }
    return _folderTemplates.map((item) => item.name).toList();
  }

  List<ProjectFolderTemplateDto> _childrenOf(String? parentTemplateId) {
    final children = _folderTemplates
        .where((t) => t.parentTemplateId == parentTemplateId)
        .toList();
    children.sort((a, b) {
      final orderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return children;
  }

  Future<void> _addFolderTemplate(String name) async {
    await _addFolderTemplateAt(name: name, parentTemplateId: null);
  }

  Future<void> _addFolderTemplateAt({
    required String name,
    required String? parentTemplateId,
  }) async {
    if (_companyId == null) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.addProjectFolderTemplate(
        companyId: _companyId!,
        name: name,
        parentTemplateId: parentTemplateId,
      );

      final nextAssignments =
          <String, List<ProjectFolderTemplateDemoFileDto>>{};
      for (final template in updated) {
        nextAssignments[template.id] =
            _demoAssignments[template.id] ?? const [];
      }

      setState(() {
        _folderTemplates = updated;
        _demoAssignments = nextAssignments;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showAddSubFolderDialog(String parentTemplateId) async {
    final nameController = TextEditingController();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add subfolder'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Subfolder name'),
            autofocus: true,
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
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      await _addFolderTemplateAt(
                        name: name,
                        parentTemplateId: parentTemplateId,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Add'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
  }

  Future<void> _deleteFolderTemplate(String templateId) async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.deleteProjectFolderTemplate(templateId);
      final nextAssignments =
          <String, List<ProjectFolderTemplateDemoFileDto>>{};
      for (final template in updated) {
        nextAssignments[template.id] =
            _demoAssignments[template.id] ?? const [];
      }

      setState(() {
        _folderTemplates = updated;
        _demoAssignments = nextAssignments;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _initDefaultFolders() async {
    if (_companyId == null) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.initDefaultProjectFolderTemplates(_companyId!);

      final loadedAssignments = await Future.wait(
        updated.map((t) => api.folderTemplateDemoFiles(t.id)),
      );
      final nextAssignments =
          <String, List<ProjectFolderTemplateDemoFileDto>>{};
      for (var i = 0; i < updated.length; i++) {
        nextAssignments[updated[i].id] = loadedAssignments[i];
      }

      setState(() {
        _folderTemplates = updated;
        _demoAssignments = nextAssignments;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addTemplateDemoFile({
    required String folderTemplateId,
    required String demoTemplateId,
    String? targetFileName,
  }) async {
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .addFolderTemplateDemoFile(
            templateId: folderTemplateId,
            demoTemplateId: demoTemplateId,
            targetFileName: targetFileName,
          );

      setState(() {
        _demoAssignments = {..._demoAssignments, folderTemplateId: updated};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteTemplateDemoFile({
    required String folderTemplateId,
    required String demoFileId,
  }) async {
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .deleteFolderTemplateDemoFile(demoFileId);

      setState(() {
        _demoAssignments = {..._demoAssignments, folderTemplateId: updated};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Admin - New Project Structure',
      onAdd: () {},
      onSettings: () => _openSettings(context, ref),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildTemplateSection(),
              const SizedBox(height: 20),
              _buildDemoFileSection(),
              const SizedBox(height: 20),
              _buildPreviewSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_tree_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Template used by Add Project',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Folders and assigned demo files here are created automatically when Add Project is used on the company page.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Default folder list',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_folderTemplates.isEmpty)
              Text(
                'No custom template set. Fallback is: ${_fallbackFolders.join(', ')}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            if (_folderTemplates.isEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _initDefaultFolders,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Initialize default folders'),
              ),
            ],
            const SizedBox(height: 8),
            _buildFolderTreeRows(parentTemplateId: null, depth: 0),
            const SizedBox(height: 8),
            _AddTemplateChip(enabled: !_saving, onAdd: _addFolderTemplate),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTreeRows({
    required String? parentTemplateId,
    required int depth,
  }) {
    final children = _childrenOf(parentTemplateId);
    if (children.isEmpty) {
      if (depth == 0 && _folderTemplates.isNotEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: EdgeInsets.only(left: depth * 20.0, bottom: 4),
        child: Text(
          'No subfolders.',
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
      );
    }

    return Column(
      children: [
        for (final item in children) ...[
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0, bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(item.name)),
                IconButton(
                  tooltip: 'Add subfolder',
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed: _saving
                      ? null
                      : () => _showAddSubFolderDialog(item.id),
                ),
                IconButton(
                  tooltip: 'Delete folder',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _saving
                      ? null
                      : () => _deleteFolderTemplate(item.id),
                ),
              ],
            ),
          ),
          _buildFolderTreeRows(parentTemplateId: item.id, depth: depth + 1),
        ],
      ],
    );
  }

  Widget _buildDemoFileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.file_copy_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Demo files copied into each folder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_folderTemplates.isEmpty)
              Text(
                'Create a custom folder first to assign demo files.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              )
            else
              ..._folderTemplates.map((template) {
                final assigned =
                    _demoAssignments[template.id] ??
                    const <ProjectFolderTemplateDemoFileDto>[];
                final assignedIds = assigned
                    .map((a) => a.demoTemplateId)
                    .toSet();
                final selectable = _demoTemplates
                    .where((demo) => !assignedIds.contains(demo.id))
                    .toList();

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text(
                      template.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${assigned.length} demo file(s)'),
                    children: [
                      if (assigned.isEmpty)
                        Text(
                          'No demo files assigned.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: assigned
                              .map(
                                (item) => InputChip(
                                  label: Text(
                                    item.targetFileName == null ||
                                            item.targetFileName!.trim().isEmpty
                                        ? _displayDemoName(item.demoTemplateId)
                                        : '${_displayDemoName(item.demoTemplateId)} -> ${item.targetFileName}',
                                  ),
                                  onDeleted: _saving
                                      ? null
                                      : () => _deleteTemplateDemoFile(
                                          folderTemplateId: template.id,
                                          demoFileId: item.id,
                                        ),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 8),
                      _AddDemoFileRow(
                        enabled: !_saving,
                        candidates: selectable,
                        onAdd: (demoTemplateId, targetFileName) {
                          _addTemplateDemoFile(
                            folderTemplateId: template.id,
                            demoTemplateId: demoTemplateId,
                            targetFileName: targetFileName,
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.visibility_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Preview of new project structure',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_folderTemplates.isEmpty)
              ..._effectiveFolders.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, size: 18),
                      const SizedBox(width: 8),
                      Text(name),
                    ],
                  ),
                ),
              )
            else
              _buildPreviewTree(parentTemplateId: null, depth: 0),
            const Divider(height: 22),
            Text(
              'Demo files come from backend/demo_files and are copied into each created folder.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTree({
    required String? parentTemplateId,
    required int depth,
  }) {
    final children = _childrenOf(parentTemplateId);
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (final folder in children) ...[
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder, size: 18),
                    const SizedBox(width: 8),
                    Text(folder.name),
                  ],
                ),
                ...(_demoAssignments[folder.id] ??
                        const <ProjectFolderTemplateDemoFileDto>[])
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(left: 26, top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              item.targetFileName == null ||
                                      item.targetFileName!.trim().isEmpty
                                  ? _displayDemoName(item.demoTemplateId)
                                  : item.targetFileName!,
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          _buildPreviewTree(parentTemplateId: folder.id, depth: depth + 1),
        ],
      ],
    );
  }
}

class _AddTemplateChip extends StatefulWidget {
  const _AddTemplateChip({required this.enabled, required this.onAdd});

  final bool enabled;
  final ValueChanged<String> onAdd;

  @override
  State<_AddTemplateChip> createState() => _AddTemplateChipState();
}

class _AddTemplateChipState extends State<_AddTemplateChip> {
  bool _editing = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      widget.onAdd(value);
    }
    _controller.clear();
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return ActionChip(
        avatar: const Icon(Icons.add, size: 16),
        label: const Text('Add folder'),
        onPressed: widget.enabled
            ? () => setState(() => _editing = true)
            : null,
      );
    }

    return SizedBox(
      width: 180,
      child: TextField(
        controller: _controller,
        autofocus: true,
        enabled: widget.enabled,
        decoration: const InputDecoration(
          hintText: 'Folder name',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onSubmitted: (_) => _submit(),
        onEditingComplete: _submit,
      ),
    );
  }
}

class _AddDemoFileRow extends StatefulWidget {
  const _AddDemoFileRow({
    required this.enabled,
    required this.candidates,
    required this.onAdd,
  });

  final bool enabled;
  final List<DemoTemplateDto> candidates;
  final void Function(String demoTemplateId, String? targetFileName) onAdd;

  @override
  State<_AddDemoFileRow> createState() => _AddDemoFileRowState();
}

class _AddDemoFileRowState extends State<_AddDemoFileRow> {
  String? _selectedId;
  final _targetNameCtrl = TextEditingController();

  @override
  void dispose() {
    _targetNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) {
      return Text(
        'All available demo files are already assigned.',
        style: TextStyle(color: Theme.of(context).colorScheme.secondary),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Demo file',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: widget.candidates
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(item.fileName),
                  ),
                )
                .toList(),
            onChanged: widget.enabled
                ? (value) => setState(() => _selectedId = value)
                : null,
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _targetNameCtrl,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Optional rename',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: !widget.enabled || _selectedId == null
              ? null
              : () {
                  final target = _targetNameCtrl.text.trim();
                  widget.onAdd(_selectedId!, target.isEmpty ? null : target);
                  setState(() => _selectedId = null);
                  _targetNameCtrl.clear();
                },
          child: const Text('Add demo file'),
        ),
      ],
    );
  }
}
