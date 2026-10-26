import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminManufacturersScreen extends ConsumerStatefulWidget {
  const AdminManufacturersScreen({super.key});

  @override
  ConsumerState<AdminManufacturersScreen> createState() =>
      _AdminManufacturersScreenState();
}

class _AdminManufacturersScreenState
    extends ConsumerState<AdminManufacturersScreen> {
  bool _isLoading = true;
  String? _error;
  List<ManufacturerDto> _manufacturers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiClientProvider).manufacturers();
      if (!mounted) {
        return;
      }
      setState(() {
        _manufacturers = list;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load manufacturers: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditor({ManufacturerDto? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final websiteCtrl = TextEditingController(text: existing?.website ?? '');
    final emailCtrl = TextEditingController(
      text: existing?.contactEmail ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: existing?.phoneNumber ?? '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Manufacturer' : 'Edit Manufacturer',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: websiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final api = ref.read(apiClientProvider);
                        final updated = existing == null
                            ? await api.addManufacturer(
                                name: name,
                                website: websiteCtrl.text.trim(),
                                contactEmail: emailCtrl.text.trim(),
                                phoneNumber: phoneCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                              )
                            : await api.updateManufacturer(
                                manufacturerId: existing.id,
                                name: name,
                                website: websiteCtrl.text.trim(),
                                contactEmail: emailCtrl.text.trim(),
                                phoneNumber: phoneCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                              );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          _manufacturers = updated;
                        });
                        Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not save: $error'),
                            ),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    websiteCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _delete(ManufacturerDto item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Manufacturer'),
        content: Text('Delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final updated = await ref
          .read(apiClientProvider)
          .deleteManufacturer(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _manufacturers = updated;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Manufacturers',
      onAdd: () => _openEditor(),
      onSettings: () {},
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Manufacturers admins can order parts from. '
                          'These show up as options when marking a part '
                          '"Order" on a project\'s Order Parts screen.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Manufacturer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_manufacturers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No manufacturers added yet.'),
                      ),
                    )
                  else
                    ..._manufacturers.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Icon(Icons.factory_outlined, color: Colors.white),
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              if (item.website != null && item.website!.isNotEmpty)
                                item.website!,
                              if (item.contactEmail != null &&
                                  item.contactEmail!.isNotEmpty)
                                item.contactEmail!,
                              if (item.phoneNumber != null &&
                                  item.phoneNumber!.isNotEmpty)
                                item.phoneNumber!,
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _openEditor(existing: item),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _delete(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
