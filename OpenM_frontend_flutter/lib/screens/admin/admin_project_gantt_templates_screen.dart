import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminProjectGanttTemplatesScreen extends ConsumerStatefulWidget {
  const AdminProjectGanttTemplatesScreen({super.key});

  @override
  ConsumerState<AdminProjectGanttTemplatesScreen> createState() =>
      _AdminProjectGanttTemplatesScreenState();
}

class _AdminProjectGanttTemplatesScreenState
    extends ConsumerState<AdminProjectGanttTemplatesScreen> {
  String? _companyId;
  List<ProjectGanttStepTemplateDto> _templates = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = 'No company found.';
        });
        return;
      }

      final companyId = companies.first.id;
      final templates = await api.projectGanttStepTemplates(companyId);
      if (!mounted) {
        return;
      }
      setState(() {
        _companyId = companyId;
        _templates = templates;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Future<void> _initDefaults() async {
    if (_companyId == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.initDefaultProjectGanttStepTemplates(
        _companyId!,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = updated;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initialize defaults: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showAddDialog() async {
    final statusCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '7');
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Gantt Step Template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: statusCtrl,
                  decoration: const InputDecoration(labelText: 'Status key'),
                ),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (days)',
                  ),
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
                      if (_companyId == null) {
                        return;
                      }
                      final statusKey = statusCtrl.text.trim();
                      final title = titleCtrl.text.trim();
                      final durationDays =
                          int.tryParse(durationCtrl.text.trim()) ?? 7;
                      if (statusKey.isEmpty || title.isEmpty) {
                        return;
                      }

                      setDialogState(() => saving = true);
                      try {
                        final api = ref.read(apiClientProvider);
                        final updated = await api.addProjectGanttStepTemplate(
                          companyId: _companyId!,
                          statusKey: statusKey,
                          title: title,
                          description: descriptionCtrl.text.trim().isEmpty
                              ? null
                              : descriptionCtrl.text.trim(),
                          durationDays: durationDays,
                        );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          _templates = updated;
                        });
                        Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not add template: $error'),
                            ),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Add'),
            ),
          ],
        ),
      ),
    );

    statusCtrl.dispose();
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    durationCtrl.dispose();
  }

  Future<void> _showEditDialog(ProjectGanttStepTemplateDto item) async {
    final statusCtrl = TextEditingController(text: item.statusKey);
    final titleCtrl = TextEditingController(text: item.title);
    final descriptionCtrl = TextEditingController(text: item.description ?? '');
    final durationCtrl = TextEditingController(
      text: item.durationDays.toString(),
    );
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Gantt Step Template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: statusCtrl,
                  decoration: const InputDecoration(labelText: 'Status key'),
                ),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (days)',
                  ),
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
                      final statusKey = statusCtrl.text.trim();
                      final title = titleCtrl.text.trim();
                      final durationDays = int.tryParse(
                        durationCtrl.text.trim(),
                      );
                      if (statusKey.isEmpty ||
                          title.isEmpty ||
                          durationDays == null) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final api = ref.read(apiClientProvider);
                        final updated = await api
                            .updateProjectGanttStepTemplate(
                              templateId: item.id,
                              statusKey: statusKey,
                              title: title,
                              description: descriptionCtrl.text.trim(),
                              durationDays: durationDays,
                            );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          _templates = updated;
                        });
                        Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not update template: $error',
                              ),
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

    statusCtrl.dispose();
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    durationCtrl.dispose();
  }

  Future<void> _deleteTemplate(ProjectGanttStepTemplateDto item) async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.deleteProjectGanttStepTemplate(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = updated;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete template: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showAddSubStepDialog(ProjectGanttStepTemplateDto parent) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '1');
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Sub Step to "${parent.title}"'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (days)',
                  ),
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
                      final title = titleCtrl.text.trim();
                      final durationDays =
                          int.tryParse(durationCtrl.text.trim()) ?? 1;
                      if (title.isEmpty) {
                        return;
                      }

                      setDialogState(() => saving = true);
                      try {
                        final api = ref.read(apiClientProvider);
                        final updated = await api
                            .addProjectGanttSubStepTemplate(
                              parentTemplateId: parent.id,
                              title: title,
                              description: descriptionCtrl.text.trim().isEmpty
                                  ? null
                                  : descriptionCtrl.text.trim(),
                              durationDays: durationDays,
                            );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          _templates = updated;
                        });
                        Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not add sub step: $error'),
                            ),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Add'),
            ),
          ],
        ),
      ),
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    durationCtrl.dispose();
  }

  Future<void> _showEditSubStepDialog(
    ProjectGanttSubStepTemplateDto item,
  ) async {
    final titleCtrl = TextEditingController(text: item.title);
    final descriptionCtrl = TextEditingController(text: item.description ?? '');
    final durationCtrl = TextEditingController(
      text: item.durationDays.toString(),
    );
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Sub Step'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (days)',
                  ),
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
                      final title = titleCtrl.text.trim();
                      final durationDays = int.tryParse(
                        durationCtrl.text.trim(),
                      );
                      if (title.isEmpty || durationDays == null) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final api = ref.read(apiClientProvider);
                        final updated = await api
                            .updateProjectGanttSubStepTemplate(
                              subTemplateId: item.id,
                              title: title,
                              description: descriptionCtrl.text.trim(),
                              durationDays: durationDays,
                            );
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        setState(() {
                          _templates = updated;
                        });
                        Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not update sub step: $error',
                              ),
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

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    durationCtrl.dispose();
  }

  Future<void> _deleteSubStepTemplate(
    ProjectGanttSubStepTemplateDto item,
  ) async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.deleteProjectGanttSubStepTemplate(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = updated;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete sub step: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppShell(
        pageName: 'Gantt Templates',
        onAdd: () {},
        onSettings: _openSettings,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return AppShell(
        pageName: 'Gantt Templates',
        onAdd: () {},
        onSettings: _openSettings,
        child: Center(child: Text(_error!)),
      );
    }

    return AppShell(
      pageName: 'Gantt Templates',
      onAdd: _showAddDialog,
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _saving ? null : _initDefaults,
                  child: Text(
                    _saving ? 'Please wait...' : 'Init Default Steps',
                  ),
                ),
                Text(
                  'Templates define default gantt steps used when a project starts gantt at Sale status. '
                  'Expand a step to add its default sub steps — new projects will use them instead of '
                  'the generic auto-split fallback.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _templates.isEmpty
                  ? const Center(child: Text('No gantt templates configured.'))
                  : ListView.builder(
                      itemCount: _templates.length,
                      itemBuilder: (context, index) {
                        final item = _templates[index];
                        return Card(
                          child: ExpansionTile(
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.statusKey} • ${item.durationDays} days'
                              '${(item.description ?? '').isEmpty ? '' : '\n${item.description}'}'
                              '${item.subStepTemplates.isEmpty ? '' : '\n${item.subStepTemplates.length} sub step${item.subStepTemplates.length == 1 ? '' : 's'}'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: _saving
                                      ? null
                                      : () => _showEditDialog(item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: _saving
                                      ? null
                                      : () => _deleteTemplate(item),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            children: [
                              ...item.subStepTemplates.map(
                                (subItem) => Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.subdirectory_arrow_right,
                                    ),
                                    title: Text(subItem.title),
                                    subtitle: Text(
                                      '${subItem.durationDays} days'
                                      '${(subItem.description ?? '').isEmpty ? '' : ' • ${subItem.description}'}',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit Sub Step',
                                          onPressed: _saving
                                              ? null
                                              : () =>
                                                    _showEditSubStepDialog(
                                                      subItem,
                                                    ),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 20,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete Sub Step',
                                          onPressed: _saving
                                              ? null
                                              : () => _deleteSubStepTemplate(
                                                  subItem,
                                                ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => _showAddSubStepDialog(item),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Sub Step'),
                                  ),
                                ),
                              ),
                              if (item.subStepTemplates.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    bottom: 8,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'No sub steps configured — new projects will '
                                      'get generic auto-split "Detail 1/2/3" sub '
                                      'steps for this one instead.',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
