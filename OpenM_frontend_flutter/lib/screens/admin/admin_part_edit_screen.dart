import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminPartEditScreen extends ConsumerStatefulWidget {
  const AdminPartEditScreen({super.key, required this.partId});

  final String partId;

  @override
  ConsumerState<AdminPartEditScreen> createState() =>
      _AdminPartEditScreenState();
}

class _AdminPartEditScreenState extends ConsumerState<AdminPartEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _partSourceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _buyPriceCtrl = TextEditingController(text: '0');
  final _sellPriceCtrl = TextEditingController(text: '0');

  Uint8List? _imageBytes;
  String? _imageName;
  String _partRole = 'main';
  String _status = 'active';
  String? _parentPartId;
  String? _rivalPartId;
  String? _categoryId;
  List<PartDto> _allParts = const [];
  List<PartCategoryDto> _categories = const [];
  Set<String> _selectedChildIds = {};
  Set<String> _initialChildIds = {};
  bool _loading = true;
  bool _saving = false;

  // CAD / drawings / instructions state
  PartDto? _part;
  bool _uploadingCad = false;
  bool _uploadingInstructions = false;
  bool _deletingCad = false;
  bool _deletingInstructions = false;
  final Set<String> _deletingDrawingIds = {};
  bool _uploadingDrawing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    _descriptionCtrl.dispose();
    _partSourceCtrl.dispose();
    _notesCtrl.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.partById(widget.partId),
        api.parts(includeAll: true),
        api.partCategories(),
      ]);
      final part = results[0] as PartDto;
      final allParts = results[1] as List<PartDto>;
      final categories = results[2] as List<PartCategoryDto>;
      final childIds = allParts
          .where((item) => item.parentPartId == widget.partId)
          .map((item) => item.id)
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _nameCtrl.text = part.name;
        _idNumberCtrl.text = part.idNumber ?? '';
        _descriptionCtrl.text = part.description ?? '';
        _partSourceCtrl.text = part.partSource ?? '';
        _notesCtrl.text = part.notes ?? '';
        _partRole = part.partRole;
        _status = part.status;
        _parentPartId = part.parentPartId;
        _rivalPartId = part.rivalPartId;
        _categoryId = part.categoryId;
        _buyPriceCtrl.text = part.buyPrice.toStringAsFixed(2);
        _sellPriceCtrl.text = part.sellPrice.toStringAsFixed(2);
        _allParts = allParts;
        _categories = categories;
        _selectedChildIds = Set<String>.from(childIds);
        _initialChildIds = Set<String>.from(childIds);
        _part = part;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load part: $error')));
    }
  }

  String get _categoryScope =>
      _parentPartId != null || _partRole == 'sub' ? 'sub' : 'main';

  List<PartCategoryDto> get _availableCategories {
    final scoped = _categories
        .where((item) => item.scope == _categoryScope)
        .toList();
    scoped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return scoped;
  }

  void _syncCategorySelectionToScope() {
    if (_categoryId == null) {
      return;
    }
    final stillValid = _availableCategories.any(
      (item) => item.id == _categoryId,
    );
    if (!stillValid) {
      _categoryId = null;
    }
  }

  Future<void> _openCategoryEditorDialog() async {
    final api = ref.read(apiClientProvider);
    final nameCtrl = TextEditingController();
    String scope = _categoryScope;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final scoped =
              _categories.where((item) => item.scope == scope).toList()..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

          return AlertDialog(
            title: const Text('Manage Categories'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(
                      labelText: 'Category Group',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'main',
                        child: Text('Main Categories'),
                      ),
                      DropdownMenuItem(
                        value: 'sub',
                        child: Text('Sub Categories'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        scope = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'New Category Name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                return;
                              }
                              setDialogState(() {
                                saving = true;
                              });
                              try {
                                final created = await api.createPartCategory(
                                  scope: scope,
                                  name: name,
                                );
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _categories = [..._categories, created];
                                  if (_categoryScope == created.scope) {
                                    _categoryId = created.id;
                                  }
                                });
                                nameCtrl.clear();
                              } finally {
                                if (mounted) {
                                  setDialogState(() {
                                    saving = false;
                                  });
                                }
                              }
                            },
                      child: Text(saving ? 'Adding...' : 'Add Category'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Existing Categories'),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 200,
                    child: ListView(
                      children: scoped
                          .map(
                            (category) => ListTile(
                              dense: true,
                              title: Text(category.name),
                              trailing: IconButton(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          saving = true;
                                        });
                                        try {
                                          await api.deletePartCategory(
                                            category.id,
                                          );
                                          if (!mounted) {
                                            return;
                                          }
                                          setState(() {
                                            _categories = _categories
                                                .where(
                                                  (item) =>
                                                      item.id != category.id,
                                                )
                                                .toList(growable: false);
                                            if (_categoryId == category.id) {
                                              _categoryId = null;
                                            }
                                          });
                                        } finally {
                                          if (mounted) {
                                            setDialogState(() {
                                              saving = false;
                                            });
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    setState(_syncCategorySelectionToScope);
  }

  List<PartDto> get _childCandidates {
    final list = _allParts.where((item) => item.id != widget.partId).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<PartDto> get _rivalCandidates {
    final list = _allParts
        .where((item) => item.id != widget.partId && item.partRole == 'main')
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<PartDto> get _selectedChildren {
    final selected = _allParts
        .where((item) => _selectedChildIds.contains(item.id))
        .toList();
    selected.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return selected;
  }

  double get _subBuySum =>
      _selectedChildren.fold(0.0, (sum, item) => sum + item.buyPrice);

  double get _subSellSum =>
      _selectedChildren.fold(0.0, (sum, item) => sum + item.sellPrice);

  Future<void> _syncChildParts() async {
    final api = ref.read(apiClientProvider);
    final mapById = {for (final part in _allParts) part.id: part};

    final removed = _initialChildIds.difference(_selectedChildIds);
    final added = _selectedChildIds.difference(_initialChildIds);

    for (final id in removed) {
      final child = mapById[id];
      if (child == null) {
        continue;
      }
      await api.updatePart(
        partId: child.id,
        name: child.name,
        parentPartId: null,
        rivalPartId: child.rivalPartId,
        description: child.description,
        partSource: child.partSource,
        categoryId: child.categoryId,
        status: child.status,
        notes: child.notes,
        partRole: 'main',
        idNumber: child.idNumber,
        buyPrice: child.buyPrice,
        sellPrice: child.sellPrice,
      );
    }

    if (added.isNotEmpty) {
      await api.linkExistingParts(
        parentPartId: widget.partId,
        childPartIds: added.toList(),
      );
    }
  }

  Future<void> _openAddSubPartsDialog() async {
    final candidates = _childCandidates
        .where((item) => !_selectedChildIds.contains(item.id))
        .toList();

    if (candidates.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more parts available to add.')),
      );
      return;
    }

    final selected = <String>{};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Sub Parts'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                children: candidates
                    .map(
                      (part) => CheckboxListTile(
                        value: selected.contains(part.id),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selected.add(part.id);
                            } else {
                              selected.remove(part.id);
                            }
                          });
                        },
                        title: Text(part.name),
                        subtitle: Text(
                          'Role: ${part.partRole == 'main' ? 'Main' : 'Sub'} | Buy ${part.buyPrice.toStringAsFixed(2)} | Sell ${part.sellPrice.toStringAsFixed(2)}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedChildIds = {..._selectedChildIds, ...selected};
                      });
                      Navigator.pop(context);
                    },
              child: const Text('Add Selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) {
      return;
    }

    setState(() {
      _imageBytes = file.bytes;
      _imageName = file.name;
    });
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    final buyPrice =
        double.tryParse(_buyPriceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final sellPrice =
        double.tryParse(_sellPriceCtrl.text.trim().replaceAll(',', '.')) ?? 0;

    setState(() {
      _saving = true;
    });

    try {
      await ref
          .read(apiClientProvider)
          .updatePart(
            partId: widget.partId,
            name: _nameCtrl.text.trim(),
            parentPartId: _parentPartId,
            rivalPartId: _rivalPartId,
            description: _descriptionCtrl.text.trim().isEmpty
                ? null
                : _descriptionCtrl.text.trim(),
            partSource: _partSourceCtrl.text.trim().isEmpty
                ? null
                : _partSourceCtrl.text.trim(),
            categoryId: _categoryId,
            status: _status,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            partRole: _partRole,
            idNumber: _idNumberCtrl.text.trim().isEmpty
                ? null
                : _idNumberCtrl.text.trim(),
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            imageBytes: _imageBytes,
            imageFileName: _imageName,
          );
      await _syncChildParts();
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save part: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageName = null;
    });
  }

  Future<void> _uploadCadFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingCad = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .uploadPartCadFile(
            partId: widget.partId,
            fileBytes: file.bytes!,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() => _part = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload CAD file.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingCad = false);
    }
  }

  Future<void> _deleteCadFile() async {
    setState(() => _deletingCad = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .deletePartCadFile(widget.partId);
      if (!mounted) return;
      setState(() => _part = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete CAD file.')),
      );
    } finally {
      if (mounted) setState(() => _deletingCad = false);
    }
  }

  Future<void> _uploadDrawing() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingDrawing = true);
    try {
      final drawing = await ref
          .read(apiClientProvider)
          .uploadPartDrawing(
            partId: widget.partId,
            fileBytes: file.bytes!,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() {
        _part = PartDto(
          id: _part!.id,
          parentPartId: _part!.parentPartId,
          categoryId: _part!.categoryId,
          categoryName: _part!.categoryName,
          categoryScope: _part!.categoryScope,
          name: _part!.name,
          partSource: _part!.partSource,
          status: _part!.status,
          partRole: _part!.partRole,
          imageUrl: _part!.imageUrl,
          idNumber: _part!.idNumber,
          sellPrice: _part!.sellPrice,
          buyPrice: _part!.buyPrice,
          cadFileUrl: _part!.cadFileUrl,
          cadFileName: _part!.cadFileName,
          instructionsUrl: _part!.instructionsUrl,
          instructionsName: _part!.instructionsName,
          drawings: [..._part!.drawings, drawing],
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload drawing.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingDrawing = false);
    }
  }

  Future<void> _deleteDrawing(PartDrawingDto drawing) async {
    setState(() => _deletingDrawingIds.add(drawing.id));
    try {
      await ref
          .read(apiClientProvider)
          .deletePartDrawing(partId: widget.partId, drawingId: drawing.id);
      if (!mounted) return;
      setState(() {
        _part = PartDto(
          id: _part!.id,
          parentPartId: _part!.parentPartId,
          categoryId: _part!.categoryId,
          categoryName: _part!.categoryName,
          categoryScope: _part!.categoryScope,
          name: _part!.name,
          partSource: _part!.partSource,
          status: _part!.status,
          partRole: _part!.partRole,
          imageUrl: _part!.imageUrl,
          idNumber: _part!.idNumber,
          sellPrice: _part!.sellPrice,
          buyPrice: _part!.buyPrice,
          cadFileUrl: _part!.cadFileUrl,
          cadFileName: _part!.cadFileName,
          instructionsUrl: _part!.instructionsUrl,
          instructionsName: _part!.instructionsName,
          drawings: _part!.drawings.where((d) => d.id != drawing.id).toList(),
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete drawing.')),
      );
    } finally {
      if (mounted) setState(() => _deletingDrawingIds.remove(drawing.id));
    }
  }

  Future<void> _uploadInstructions() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingInstructions = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .uploadPartInstructions(
            partId: widget.partId,
            fileBytes: file.bytes!,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() => _part = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload instructions.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingInstructions = false);
    }
  }

  Future<void> _deleteInstructions() async {
    setState(() => _deletingInstructions = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .deletePartInstructions(widget.partId);
      if (!mounted) return;
      setState(() => _part = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete instructions.')),
      );
    } finally {
      if (mounted) setState(() => _deletingInstructions = false);
    }
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(labelText: label, hintText: hint);
  }

  Widget _sectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF102A43),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: Color(0xFF627D98)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = const Color(0xFFD9E2EC);

    return AppShell(
      pageName: 'Edit Part',
      onAdd: _save,
      onSettings: _openSettings,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Theme(
              data: Theme.of(context).copyWith(
                scaffoldBackgroundColor: const Color(0xFFF4F7FB),
                cardTheme: CardThemeData(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: borderColor),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  labelStyle: const TextStyle(
                    color: Color(0xFF486581),
                    fontWeight: FontWeight.w600,
                  ),
                  hintStyle: const TextStyle(color: Color(0xFF9FB3C8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF334E68),
                      width: 1.6,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFB42318)),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFFB42318),
                      width: 1.4,
                    ),
                  ),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF102A43),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                dividerTheme: DividerThemeData(color: borderColor),
              ),
              child: Container(
                color: const Color(0xFFF4F7FB),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: _sectionHeading(
                            'Part Details',
                            'Maintain technical and commercial information in one place.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: _fieldDecoration('Part Name *'),
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Part name is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _idNumberCtrl,
                                decoration: _fieldDecoration(
                                  'Part Number',
                                  hint: 'Internal or supplier code',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _descriptionCtrl,
                                minLines: 2,
                                maxLines: 4,
                                decoration: _fieldDecoration('Description'),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String?>(
                                      initialValue: _categoryId,
                                      decoration: _fieldDecoration(
                                        _categoryScope == 'main'
                                            ? 'Main Category'
                                            : 'Sub Category',
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('No category'),
                                        ),
                                        ..._availableCategories.map(
                                          (category) =>
                                              DropdownMenuItem<String?>(
                                                value: category.id,
                                                child: Text(category.name),
                                              ),
                                        ),
                                      ],
                                      onChanged: _saving
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _categoryId = value;
                                              });
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : _openCategoryEditorDialog,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _status,
                                decoration: _fieldDecoration('Status'),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'active',
                                    child: Text('Active'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'inactive',
                                    child: Text('Inactive'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          _status = value;
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String?>(
                                initialValue: _parentPartId,
                                decoration: _fieldDecoration('Parent Part'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('No parent (root part)'),
                                  ),
                                  ..._childCandidates.map(
                                    (part) => DropdownMenuItem<String?>(
                                      value: part.id,
                                      child: Text(part.name),
                                    ),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _parentPartId = value;
                                          if (value != null) {
                                            _partRole = 'sub';
                                          }
                                          _syncCategorySelectionToScope();
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String?>(
                                initialValue: _rivalPartId,
                                decoration: _fieldDecoration('Rival Part'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('No rival part'),
                                  ),
                                  ..._rivalCandidates.map(
                                    (part) => DropdownMenuItem<String?>(
                                      value: part.id,
                                      child: Text(part.name),
                                    ),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _rivalPartId = value;
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _partRole,
                                decoration: _fieldDecoration('Part Role'),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'main',
                                    child: Text('Main Part'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'sub',
                                    child: Text('Sub Part'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          _partRole = value;
                                          _syncCategorySelectionToScope();
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _buyPriceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _fieldDecoration('Buy Price'),
                                validator: (value) {
                                  final parsed = double.tryParse(
                                    (value ?? '').trim().replaceAll(',', '.'),
                                  );
                                  if (parsed == null) {
                                    return 'Enter a valid number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _sellPriceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _fieldDecoration('Sales Price'),
                                validator: (value) {
                                  final parsed = double.tryParse(
                                    (value ?? '').trim().replaceAll(',', '.'),
                                  );
                                  if (parsed == null) {
                                    return 'Enter a valid number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _notesCtrl,
                                minLines: 2,
                                maxLines: 5,
                                decoration: _fieldDecoration('Notes'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sub Parts in this Part',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (_selectedChildren.isEmpty)
                                const Text('No sub parts selected.')
                              else
                                ..._selectedChildren.map(
                                  (child) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${child.name}  |  Buy ${child.buyPrice.toStringAsFixed(2)}  |  Sell ${child.sellPrice.toStringAsFixed(2)}',
                                    ),
                                  ),
                                ),
                              const Divider(height: 20),
                              Text(
                                'Sub parts sum buy: ${_subBuySum.toStringAsFixed(2)}',
                              ),
                              Text(
                                'Sub parts sum sell: ${_subSellSum.toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Added Sub Parts',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _saving
                                        ? null
                                        : _openAddSubPartsDialog,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Sub Parts'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 280,
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: ListView(
                                    children: _selectedChildren.isEmpty
                                        ? const [
                                            ListTile(
                                              dense: true,
                                              title: Text(
                                                'No sub parts added yet.',
                                              ),
                                            ),
                                          ]
                                        : _selectedChildren
                                              .map(
                                                (part) => ListTile(
                                                  dense: true,
                                                  title: Text(part.name),
                                                  subtitle: Text(
                                                    'Role: ${part.partRole == 'main' ? 'Main' : 'Sub'} | Buy ${part.buyPrice.toStringAsFixed(2)} | Sell ${part.sellPrice.toStringAsFixed(2)}',
                                                  ),
                                                  trailing: IconButton(
                                                    onPressed: _saving
                                                        ? null
                                                        : () {
                                                            setState(() {
                                                              _selectedChildIds
                                                                  .remove(
                                                                    part.id,
                                                                  );
                                                            });
                                                          },
                                                    icon: const Icon(
                                                      Icons
                                                          .remove_circle_outline,
                                                    ),
                                                    tooltip: 'Remove sub part',
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          _imageName == null
                              ? 'Upload New Image'
                              : 'Image: $_imageName',
                        ),
                      ),
                      if (_imageBytes case final imageBytes?) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            imageBytes,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _removeImage,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove New Image'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // ── CAD File ─────────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CAD File (one per part)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (_part?.cadFileName != null)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.view_in_ar_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _part!.cadFileName!,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete CAD file',
                                      icon: _deletingCad
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.delete_outline),
                                      onPressed: _deletingCad
                                          ? null
                                          : _deleteCadFile,
                                    ),
                                  ],
                                )
                              else
                                const Text('No CAD file uploaded.'),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _uploadingCad
                                    ? null
                                    : _uploadCadFile,
                                icon: _uploadingCad
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_file_outlined),
                                label: Text(
                                  _part?.cadFileName != null
                                      ? 'Replace CAD File'
                                      : 'Upload CAD File',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ── 2D Drawings ──────────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '2D Drawings',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (_part == null || _part!.drawings.isEmpty)
                                const Text('No drawings uploaded.')
                              else
                                ...(_part!.drawings.map(
                                  (drawing) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.image_outlined,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            drawing.fileName,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete drawing',
                                          icon:
                                              _deletingDrawingIds.contains(
                                                drawing.id,
                                              )
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.delete_outline,
                                                ),
                                          onPressed:
                                              _deletingDrawingIds.contains(
                                                drawing.id,
                                              )
                                              ? null
                                              : () => _deleteDrawing(drawing),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _uploadingDrawing
                                    ? null
                                    : _uploadDrawing,
                                icon: _uploadingDrawing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_photo_alternate_outlined,
                                      ),
                                label: const Text('Add 2D Drawing'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ── Instructions PDF ─────────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Instructions (PDF)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (_part?.instructionsName != null)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _part!.instructionsName!,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete instructions',
                                      icon: _deletingInstructions
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.delete_outline),
                                      onPressed: _deletingInstructions
                                          ? null
                                          : _deleteInstructions,
                                    ),
                                  ],
                                )
                              else
                                const Text('No instructions uploaded.'),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _uploadingInstructions
                                    ? null
                                    : _uploadInstructions,
                                icon: _uploadingInstructions
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_file_outlined),
                                label: Text(
                                  _part?.instructionsName != null
                                      ? 'Replace Instructions PDF'
                                      : 'Upload Instructions PDF',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving...' : 'Save Changes'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
