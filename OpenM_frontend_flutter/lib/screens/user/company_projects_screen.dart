import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/todo_strip.dart';

class CompanyProjectsScreen extends ConsumerStatefulWidget {
  const CompanyProjectsScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  final String companyId;
  final String companyName;

  @override
  ConsumerState<CompanyProjectsScreen> createState() =>
      _CompanyProjectsScreenState();
}

class _CompanyProjectsScreenState extends ConsumerState<CompanyProjectsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<ProjectDto> _projects = const [];

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
    final projects = await api.projectsByClientCompany(
      widget.companyId,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _projects = projects;
    });
  }

  Future<void> _addProjectDialog() async {
    await context.push(
      '/companies/${widget.companyId}/projects/new-note?name=${Uri.encodeComponent(widget.companyName)}',
    );
    await _load();
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Color _statusColor(String status) {
    if (status == 'Done') {
      return AppColors.statusDone;
    }
    if (status == 'Overdue') {
      return AppColors.statusOverdue;
    }
    return AppColors.projectStatusDefault;
  }

  Color _statusBackgroundColor(String status) {
    return _statusColor(status).withValues(alpha: 0.12);
  }

  String _baseModelLabel(String baseModel) {
    switch (baseModel.toLowerCase()) {
      case 'normal':
        return 'Normal';
      case 'duble':
        return 'Duble';
      case 'extra':
        return 'Extra';
      default:
        return baseModel;
    }
  }

  Future<void> _editBaseModel(ProjectDto project) async {
    final api = ref.read(apiClientProvider);
    var selected = project.baseModel;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Base Case Model'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'Normal',
                groupValue: selected,
                title: const Text('Normal'),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selected = value;
                        });
                      },
              ),
              RadioListTile<String>(
                value: 'Duble',
                groupValue: selected,
                title: const Text('Duble'),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selected = value;
                        });
                      },
              ),
              RadioListTile<String>(
                value: 'Extra',
                groupValue: selected,
                title: const Text('Extra'),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selected = value;
                        });
                      },
              ),
            ],
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
                      setDialogState(() {
                        saving = true;
                      });
                      try {
                        final updated = await api.updateProjectBaseModel(
                          projectId: project.id,
                          baseModel: selected,
                        );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          final index = _projects.indexWhere((item) => item.id == project.id);
                          if (index >= 0) {
                            _projects = [
                              ..._projects.take(index),
                              updated,
                              ..._projects.skip(index + 1),
                            ];
                          }
                        });
                        } catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not save base model: $error')),
                            );
                          }
                        Navigator.pop(dialogContext);
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Client Company: ${widget.companyName}',
      onAdd: _addProjectDialog,
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TopTodoStrip(customerCompanyId: widget.companyId),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search projects',
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
              child: ListView.builder(
                itemCount: _projects.length,
                itemBuilder: (_, index) {
                  final p = _projects[index];
                  final accentColor = _statusColor(p.status);
                  return Card(
                    color: _statusBackgroundColor(p.status),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: accentColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 10,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${p.status} • ${_baseModelLabel(p.baseModel)}',
                        style: TextStyle(color: accentColor),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () => _editBaseModel(p),
                        child: const Text('Edit Base Model'),
                      ),
                      onTap: () => context.push(
                        '/projects/${p.id}/folders?name=${Uri.encodeComponent(p.name)}',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
