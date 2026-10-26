import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminPartCreateScreen extends ConsumerStatefulWidget {
  const AdminPartCreateScreen({super.key});

  @override
  ConsumerState<AdminPartCreateScreen> createState() =>
      _AdminPartCreateScreenState();
}

class _AdminPartCreateScreenState extends ConsumerState<AdminPartCreateScreen> {
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
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadParentCandidates();
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

  Future<void> _loadParentCandidates() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.parts(includeAll: true),
        api.partCategories(),
      ]);
      final parts = results[0] as List<PartDto>;
      final categories = results[1] as List<PartCategoryDto>;
      if (!mounted) {
        return;
      }
      parts.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      categories.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      setState(() {
        _allParts = parts;
        _categories = categories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load part data: $error')),
      );
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

  List<PartDto> get _rivalCandidates {
    final list = _allParts.where((item) => item.partRole == 'main').toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
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

    final name = _nameCtrl.text.trim();
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
          .createPart(
            name: name,
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
      ).showSnackBar(SnackBar(content: Text('Could not create part: $error')));
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

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Add Part',
      onAdd: _save,
      onSettings: _openSettings,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Part Name *'),
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
                    decoration: const InputDecoration(labelText: 'Part Number'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _categoryId,
                          decoration: InputDecoration(
                            labelText: _categoryScope == 'main'
                                ? 'Main Category'
                                : 'Sub Category',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No category'),
                            ),
                            ..._availableCategories.map(
                              (category) => DropdownMenuItem<String?>(
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
                        onPressed: _saving ? null : _openCategoryEditorDialog,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
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
                    decoration: const InputDecoration(labelText: 'Parent Part'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No parent (root part)'),
                      ),
                      ..._allParts.map(
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
                    decoration: const InputDecoration(labelText: 'Rival Part'),
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
                    decoration: const InputDecoration(labelText: 'Part Role'),
                    items: const [
                      DropdownMenuItem(value: 'main', child: Text('Main Part')),
                      DropdownMenuItem(value: 'sub', child: Text('Sub Part')),
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Buy Price'),
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Sales Price'),
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
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),

                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _imageName == null
                          ? 'Upload Image'
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
                        label: const Text('Remove Image'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save Part'),
                  ),
                ],
              ),
            ),
    );
  }
}
