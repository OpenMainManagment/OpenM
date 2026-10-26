import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/current_project_state.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/todo_strip.dart';
import '../../widgets/project_status_bar.dart';

class ProjectFoldersScreen extends ConsumerStatefulWidget {
  const ProjectFoldersScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  ConsumerState<ProjectFoldersScreen> createState() =>
      _ProjectFoldersScreenState();
}

class _ProjectFoldersScreenState extends ConsumerState<ProjectFoldersScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<FolderDto> _folders = const [];
  List<ProjectOrderItemDto> _orderItems = const [];
  ProjectDto? _project;
  bool _loading = true;
  bool _executingAction = false;
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentProjectIdProvider.notifier).state = widget.projectId;
    });
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    if (ref.read(currentProjectIdProvider) == widget.projectId) {
      ref.read(currentProjectIdProvider.notifier).state = null;
    }
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
    setState(() {
      _loading = true;
    });

    try {
      final foldersFuture = api.folders(
        widget.projectId,
        search: _searchCtrl.text.trim().isEmpty
            ? null
            : _searchCtrl.text.trim(),
      );
      final projectFuture = api.projectById(widget.projectId);
      final orderItemsFuture = api.projectOrderItems(widget.projectId);

      final folders = await foldersFuture;
      final project = await projectFuture;
      final orderItems = await orderItemsFuture;

      if (!mounted) {
        return;
      }
      setState(() {
        _folders = folders;
        _project = project;
        _orderItems = orderItems;
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
        SnackBar(content: Text('Could not load project data: $error')),
      );
    }
  }

  Future<void> _updateOrderItem(
    ProjectOrderItemDto item, {
    bool? selected,
    int? quantity,
  }) async {
    final api = ref.read(apiClientProvider);
    final nextSelected = selected ?? item.selected;
    final nextQuantity = quantity ?? item.quantity;

    setState(() {
      _orderItems = [
        for (final current in _orderItems)
          if (current.id == item.id)
            ProjectOrderItemDto(
              id: current.id,
              projectId: current.projectId,
              partId: current.partId,
              partName: current.partName,
              partNumber: current.partNumber,
              quantity: nextQuantity,
              selected: nextSelected,
            )
          else
            current,
      ];
    });

    try {
      final updated = await api.updateProjectOrderItem(
        projectId: widget.projectId,
        itemId: item.id,
        quantity: nextQuantity,
        selected: nextSelected,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _orderItems = [
          for (final current in _orderItems)
            if (current.id == item.id) updated else current,
        ];
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update order item.')),
      );
    }
  }

  Future<void> _openWorkflowActions() async {
    final project = _project;
    if (project == null || _executingAction) {
      return;
    }

    final api = ref.read(apiClientProvider);
    List<ProjectActionDto> actions = const [];
    try {
      // project.companyId is the *customer's* company, not the tenant
      // organization action buttons belong to — use the employee's org id.
      final employee = await api.getCurrentEmployee();
      final organizationId = employee.companyId;
      actions = await api.getProjectActions(
        companyId: organizationId,
        workflowStage: project.workflowStage,
      );
      if (actions.isEmpty) {
        actions = await api.getProjectActions(companyId: organizationId);
      }
    } catch (_) {
      actions = const [];
    }

    if (!mounted) {
      return;
    }
    if (actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project workflows available.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project Workflows',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Current stage: ${project.workflowStage}'),
                const SizedBox(height: 8),
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: _executingAction
                            ? null
                            : () async {
                                Navigator.pop(sheetContext);
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _executingAction = true;
                                });
                                try {
                                  await api.executeProjectAction(
                                    projectId: project.id,
                                    actionButtonId: action.id,
                                    executionInput: {
                                      'project_id': project.id,
                                      'project_name': project.name,
                                      'company_id': project.companyId,
                                      'workflow_stage': project.workflowStage,
                                      'action_button_id': action.id,
                                      'action_button_name': action.uniqueName,
                                    },
                                  );
                                  await _load();
                                  if (!mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Workflow "${action.uniqueName}" executed.',
                                      ),
                                    ),
                                  );
                                } on DioException catch (error) {
                                  final detail = error.response?.data;
                                  final message =
                                      detail is Map && detail['detail'] != null
                                      ? '${detail['detail']}'
                                      : 'Could not execute workflow.';
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(message)),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _executingAction = false;
                                    });
                                  }
                                }
                              },
                        label: Text(action.uniqueName),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _normalizedProjectStatus(String? status) {
    final normalized = (status ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final compact = normalized.replaceAll(RegExp(r'[\s_\-]+'), '');

    switch (compact) {
      case 'quote':
        return 'Quote';
      case 'sale':
        return 'Sale';
      case 'construction':
        return 'Construction';
      case 'procurement':
        return 'Procurement';
      case 'installation':
        return 'Installation';
      case 'programming':
        return 'Programming';
      case 'delivery':
        return 'Delivery';
      case 'commissioning':
        return 'Commissioning';
      case 'finalacceptance':
      case 'finalacceptancelegacy':
        return 'Final Acceptance';
      case 'completed':
      case 'done':
      case 'donelegacy':
        return 'Completed';
      case 'inwork':
      case 'inworklegacy':
      case 'overdue':
      case 'overduelegacy':
      case 'project':
      case 'development':
      case 'order':
      case 'assembly':
      case 'shipping':
      case 'aftersales':
        return 'Quote';
      default:
        return status?.trim() ?? '';
    }
  }

  bool _isAfterSalesStatus() {
    final normalizedStatus = _normalizedProjectStatus(_project?.status);
    if (normalizedStatus.isEmpty) {
      return false;
    }

    const workflowStages = [
      'Quote',
      'Sale',
      'Construction',
      'Procurement',
      'Installation',
      'Programming',
      'Delivery',
      'Commissioning',
      'Final Acceptance',
      'Completed',
    ];

    final currentIndex = workflowStages.indexOf(normalizedStatus);
    // Anything strictly after "Sale" (index 1) — Construction onward.
    return currentIndex > 1;
  }

  bool _isOnOrderStatus() {
    return _normalizedProjectStatus(_project?.status) == 'Procurement';
  }

  bool _canMoveToPreviousStep() {
    final normalizedStatus = _normalizedProjectStatus(_project?.status);
    if (normalizedStatus.isEmpty) {
      return false;
    }

    const workflowStages = [
      'Quote',
      'Sale',
      'Construction',
      'Procurement',
      'Installation',
      'Programming',
      'Delivery',
      'Commissioning',
      'Final Acceptance',
      'Completed',
    ];

    final currentIndex = workflowStages.indexOf(normalizedStatus);
    return currentIndex > 0;
  }

  bool _canMoveToNextStep() {
    final normalizedStatus = _normalizedProjectStatus(_project?.status);
    if (normalizedStatus.isEmpty) {
      return false;
    }

    const workflowStages = [
      'Quote',
      'Sale',
      'Construction',
      'Procurement',
      'Installation',
      'Programming',
      'Delivery',
      'Commissioning',
      'Final Acceptance',
      'Completed',
    ];

    final currentIndex = workflowStages.indexOf(normalizedStatus);
    return currentIndex >= 0 && currentIndex < workflowStages.length - 1;
  }

  Future<void> _changeProjectStatus({required bool next}) async {
    if (_project == null || _updatingStatus) {
      return;
    }

    setState(() {
      _updatingStatus = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final updatedProject = next
          ? await api.nextProjectStatus(widget.projectId)
          : await api.previousProjectStatus(widget.projectId);

      if (!mounted) {
        return;
      }

      setState(() {
        _project = updatedProject;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Moved to next project step.'
                : 'Moved to previous project step.',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? '${detail['detail']}'
          : 'Could not change project status.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change project status: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingStatus = false;
        });
      }
    }
  }

  Future<void> _addFolderDialog() async {
    final nameCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Folder'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Folder Name'),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                      });
                      try {
                        for (final name in [
                          'Angebot',
                          'Auftrag',
                          'Nacharbeit',
                        ]) {
                          await ref
                              .read(apiClientProvider)
                              .createFolder(
                                projectId: widget.projectId,
                                name: name,
                              );
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Standard folders added.'),
                            ),
                          );
                        }
                      } on DioException catch (error) {
                        final detail = error.response?.data;
                        final message =
                            detail is Map && detail['detail'] != null
                            ? '${detail['detail']}'
                            : 'Could not add standard folders.';
                        if (mounted) {
                          ScaffoldMessenger.of(
                            this.context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }
                      }
                    },
              child: const Text('Add Standard'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a folder name.'),
                            ),
                          );
                        }
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                      });
                      try {
                        await ref
                            .read(apiClientProvider)
                            .createFolder(
                              projectId: widget.projectId,
                              name: name,
                            );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Folder created.')),
                          );
                        }
                      } on DioException catch (error) {
                        final detail = error.response?.data;
                        final message =
                            detail is Map && detail['detail'] != null
                            ? '${detail['detail']}'
                            : 'Could not create folder.';
                        if (mounted) {
                          ScaffoldMessenger.of(
                            this.context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
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

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  /// Opens the project order screen
  void _openProjectOrderScreen() {
    context.push(
      '/projects/${widget.projectId}/order?name=${Uri.encodeComponent(widget.projectName)}',
    );
  }

  /// Opens the project parts status screen
  void _openProjectPartsStatusScreen() {
    context.push(
      '/projects/${widget.projectId}/parts-status?name=${Uri.encodeComponent(widget.projectName)}',
    );
  }

  /// Opens the screen for deciding how each part is sourced (Storage /
  /// Self Manufacture / Order). Only relevant once the project is past
  /// the Sale status.
  void _openProjectPartDecisionsScreen() {
    context.push(
      '/projects/${widget.projectId}/order-parts?name=${Uri.encodeComponent(widget.projectName)}',
    );
  }

  /// Opens the project details screen
  void _openProjectDetailsScreen() {
    context.push(
      '/projects/${widget.projectId}/details?name=${Uri.encodeComponent(widget.projectName)}&companyId=${Uri.encodeComponent(_project?.companyId ?? '')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Project: ${widget.projectName}',
      onAdd: _addFolderDialog,
      onSettings: _openSettings,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_project != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: !_canMoveToPreviousStep() || _updatingStatus
                                        ? null
                                        : () => _changeProjectStatus(next: false),
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Previous Step'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: !_canMoveToNextStep() || _updatingStatus
                                        ? null
                                        : () => _changeProjectStatus(next: true),
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Next Step'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TopTodoStrip(projectId: widget.projectId),
                      const SizedBox(height: 12),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search folders',
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
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _folders.length,
                          itemBuilder: (_, index) {
                            final f = _folders[index];
                            return Card(
                              child: ListTile(
                                title: Text(f.name),
                                onTap: () => context.push(
                                  '/folders/${f.id}/files?name=${Uri.encodeComponent(f.name)}&projectId=${Uri.encodeComponent(widget.projectId)}',
                                ),
                              ),
                            );
                          },
                        ),
                        if (_project != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: ProjectStatusBar(
                              project: _project!,
                              showNavigationButtons: false,
                              isEditable: false,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Project Actions',
                onPressed: _project == null ? null : _openWorkflowActions,
                icon: const Icon(Icons.tune),
              ),
            ),
          ),
          // Add a button to open the project order screen
          Positioned(
            top: 10,
            right: 60, // Positioned next to the actions button
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Order Items',
                onPressed: _openProjectOrderScreen,
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ),
          // Parts Status — order status timeline, only relevant while the
          // project is in the Procurement (order) stage.
          if (_isOnOrderStatus())
            Positioned(
              top: 10,
              right: 108, // Positioned next to the order button
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Parts Status',
                  onPressed: _openProjectPartsStatusScreen,
                  icon: const Icon(Icons.local_shipping_outlined),
                ),
              ),
            ),
          // Order Parts (Storage / Self Manufacture / Order decisions) —
          // only relevant once the project is past the Sale status.
          if (_isAfterSalesStatus())
            Positioned(
              top: 10,
              right: 156,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Order Parts',
                  onPressed: _openProjectPartDecisionsScreen,
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                ),
              ),
            ),
          Positioned(
            top: 10,
            right: 110,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Project Details',
                onPressed: _openProjectDetailsScreen,
                icon: const Icon(Icons.timeline_outlined),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
