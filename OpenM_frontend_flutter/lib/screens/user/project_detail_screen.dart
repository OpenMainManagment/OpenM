import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/current_project_state.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/project_status_bar.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.companyId,
  });

  final String projectId;
  final String projectName;
  final String companyId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  ProjectDto? _project;
  List<ProjectGanttStepTreeDto> _ganttSteps = const [];
  bool _isLoading = true;
  bool _isStartingGantt = false;
  bool _isUpdatingGantt = false;
  bool _isEditable = false; // To determine if user can edit status

  static const Set<String> _ganttStartableStatuses = {
    'Sale',
    'Construction',
    'Procurement',
    'Installation',
    'Programming',
    'Delivery',
    'Commissioning',
    'Final Acceptance',
    'Completed',
  };

  bool get _canStartGantt {
    final project = _project;
    return project != null && _ganttStartableStatuses.contains(project.status);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentProjectIdProvider.notifier).state = widget.projectId;
    });
    _loadProject();
  }

  @override
  void dispose() {
    if (ref.read(currentProjectIdProvider) == widget.projectId) {
      ref.read(currentProjectIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _loadProject() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final project = await api.projectById(widget.projectId);
      final ganttTree = project.ganttStarted
          ? await api.projectGanttTree(widget.projectId)
          : null;

      if (!mounted) return;

      setState(() {
        _project = project;
        _ganttSteps = ganttTree?.ganttSteps ?? const <ProjectGanttStepTreeDto>[];
        // TODO: Check permissions to determine if user can edit status
        // For now, we'll assume the user can edit if they have access to the project
        _isEditable = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading project: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _nextStep() async {
    if (_project == null) return;

    try {
      final api = ref.read(apiClientProvider);
      final updatedProject = await api.nextProjectStatus(_project!.id);
      final ganttTree = updatedProject.ganttStarted
          ? await api.projectGanttTree(_project!.id)
          : null;

      if (!mounted) return;

      setState(() {
        _project = updatedProject;
        _ganttSteps = ganttTree?.ganttSteps ?? const <ProjectGanttStepTreeDto>[];
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project status updated to next step')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating project status: $e')),
        );
      }
    }
  }

  Future<void> _previousStep() async {
    if (_project == null) return;

    try {
      final api = ref.read(apiClientProvider);
      final updatedProject = await api.previousProjectStatus(_project!.id);
      final ganttTree = updatedProject.ganttStarted
          ? await api.projectGanttTree(_project!.id)
          : null;

      if (!mounted) return;

      setState(() {
        _project = updatedProject;
        _ganttSteps = ganttTree?.ganttSteps ?? const <ProjectGanttStepTreeDto>[];
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project status updated to previous step'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating project status: $e')),
        );
      }
    }
  }

  Future<void> _startGantt() async {
    if (_project == null || _isStartingGantt) {
      return;
    }

    setState(() {
      _isStartingGantt = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.startProjectGantt(_project!.id);
      final ganttTree = await api.projectGanttTree(_project!.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _project = response.project;
        _ganttSteps = ganttTree.ganttSteps;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gantt process started.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start gantt: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingGantt = false;
        });
      }
    }
  }

  Future<void> _updateOverviewStepDuration({
    required String stepId,
    required int durationDays,
  }) async {
    if (_project == null || _isUpdatingGantt) {
      return;
    }

    setState(() {
      _isUpdatingGantt = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.updateProjectGanttStepDuration(
        projectId: _project!.id,
        stepId: stepId,
        durationDays: durationDays,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _project = response.project;
        _ganttSteps = response.ganttSteps;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update overview step: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGantt = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AppShell(
        pageName: widget.projectName,
        onAdd: () {},
        onSettings: () {},
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null) {
      return AppShell(
        pageName: widget.projectName,
        onAdd: () {},
        onSettings: () {},
        child: const Center(child: Text('Project not found')),
      );
    }

    return AppShell(
      pageName: widget.projectName,
      onAdd: () {},
      onSettings: () {},
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project info section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _project!.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Company: ${_project!.companyId}'),
                      const SizedBox(height: 8),
                      Text('Base Model: ${_project!.baseModel}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status bar with navigation buttons
              ProjectStatusBar(
                project: _project!,
                onNextStep: _nextStep,
                onPreviousStep: _previousStep,
                showNavigationButtons: true,
                isEditable: _isEditable,
              ),
              const SizedBox(height: 12),
              if (!_project!.ganttStarted)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: (_canStartGantt && !_isStartingGantt)
                        ? _startGantt
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _isStartingGantt ? 'Starting...' : 'Start Gantt Process',
                    ),
                  ),
                ),
              if (!_project!.ganttStarted)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Gantt can be started when project status is Sale or later.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              if (_project!.ganttStarted)
                _ProjectGanttCard(
                  projectId: widget.projectId,
                  projectName: widget.projectName,
                  companyId: widget.companyId,
                  steps: _ganttSteps,
                  isUpdating: _isUpdatingGantt,
                  onUpdateOverviewDuration: _updateOverviewStepDuration,
                  onOpenSubGantt: ({required stepId, required stepTitle}) {
                    final encodedProjectName = Uri.encodeQueryComponent(widget.projectName);
                    final encodedStepTitle = Uri.encodeQueryComponent(stepTitle);
                    final encodedCompanyId = Uri.encodeQueryComponent(widget.companyId);
                    context.push(
                      '/projects/${widget.projectId}/gantt/$stepId?name=$encodedProjectName&stepTitle=$encodedStepTitle&companyId=$encodedCompanyId',
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectGanttCard extends StatelessWidget {
  const _ProjectGanttCard({
    required this.projectId,
    required this.projectName,
    required this.companyId,
    required this.steps,
    required this.isUpdating,
    required this.onUpdateOverviewDuration,
    required this.onOpenSubGantt,
  });

  final String projectId;
  final String projectName;
  final String companyId;
  final List<ProjectGanttStepTreeDto> steps;
  final bool isUpdating;
  final Future<void> Function({
    required String stepId,
    required int durationDays,
  }) onUpdateOverviewDuration;
  final void Function({
    required String stepId,
    required String stepTitle,
  }) onOpenSubGantt;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No project steps available.'),
        ),
      );
    }

    final validStarts = steps
        .map((step) => DateTime.tryParse(step.plannedStartDate ?? ''))
        .whereType<DateTime>()
        .toList();
    final validEnds = steps
        .map((step) => DateTime.tryParse(step.plannedEndDate ?? ''))
        .whereType<DateTime>()
        .toList();

    final DateTime? timelineStart = validStarts.isEmpty
        ? null
        : validStarts.reduce(
            (left, right) => left.isBefore(right) ? left : right,
          );
    final DateTime? timelineEnd = validEnds.isEmpty
        ? null
        : validEnds.reduce((left, right) => left.isAfter(right) ? left : right);
    final int totalDays = (timelineStart != null && timelineEnd != null)
        ? timelineEnd.difference(timelineStart).inDays + 1
        : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Master Gantt Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Change overview durations here and open each deep Gantt in its own screen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...steps.map(
              (step) => _ProjectGanttOverviewRow(
                step: step,
                timelineStart: timelineStart,
                totalDays: totalDays,
                isUpdating: isUpdating,
                onUpdateOverviewDuration: onUpdateOverviewDuration,
                onOpenSubGantt: onOpenSubGantt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectGanttOverviewRow extends StatelessWidget {
  const _ProjectGanttOverviewRow({
    required this.step,
    required this.timelineStart,
    required this.totalDays,
    required this.isUpdating,
    required this.onUpdateOverviewDuration,
    required this.onOpenSubGantt,
  });

  final ProjectGanttStepTreeDto step;
  final DateTime? timelineStart;
  final int totalDays;
  final bool isUpdating;
  final Future<void> Function({
    required String stepId,
    required int durationDays,
  }) onUpdateOverviewDuration;
  final void Function({
    required String stepId,
    required String stepTitle,
  }) onOpenSubGantt;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(step.plannedStartDate ?? '');
    final end = DateTime.tryParse(step.plannedEndDate ?? '');
    final bool hasRange =
        timelineStart != null && totalDays > 0 && start != null && end != null;

    final barColor = step.isCurrent
        ? Colors.orange
        : step.isCompleted
        ? Colors.green
        : Colors.blueGrey;
    final overviewDuration = _durationDays(step.plannedStartDate, step.plannedEndDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _DraggableDurationControl(
                value: overviewDuration,
                enabled: !isUpdating,
                onCommit: (nextDuration) => onUpdateOverviewDuration(
                  stepId: step.id,
                  durationDays: nextDuration,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDateRange(step.plannedStartDate, step.plannedEndDate),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!hasRange) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }

                final offsetDays = start.difference(timelineStart!).inDays;
                final durationDays = end.difference(start).inDays + 1;
                final startFraction = (offsetDays / totalDays).clamp(0.0, 1.0);
                final widthFraction = (durationDays / totalDays).clamp(
                  0.03,
                  1.0,
                );

                final left = constraints.maxWidth * startFraction;
                final width = constraints.maxWidth * widthFraction;

                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Positioned(
                      left: left,
                      width: width,
                      top: 0,
                      bottom: 0,
                      child: _BarResizeHandle(
                        enabled: !isUpdating,
                        baseDurationDays: durationDays,
                        onCommit: (nextDuration) => onUpdateOverviewDuration(
                          stepId: step.id,
                          durationDays: nextDuration,
                        ),
                        barColor: barColor,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => onOpenSubGantt(stepId: step.id, stepTitle: step.title),
              icon: const Icon(Icons.open_in_new),
              label: Text('Open Sub Gantt (${step.subSteps.length} steps)'),
            ),
          ),
        ],
      ),
    );
  }

  int _durationDays(String? startValue, String? endValue) {
    final start = DateTime.tryParse(startValue ?? '');
    final end = DateTime.tryParse(endValue ?? '');
    if (start == null || end == null) {
      return 1;
    }
    return end.difference(start).inDays + 1;
  }

  String _formatDateRange(String? startValue, String? endValue) {
    final start = DateTime.tryParse(startValue ?? '');
    final end = DateTime.tryParse(endValue ?? '');
    if (start == null || end == null) {
      return 'No schedule';
    }
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _DraggableDurationControl extends StatefulWidget {
  const _DraggableDurationControl({
    required this.value,
    required this.enabled,
    required this.onCommit,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_DraggableDurationControl> createState() =>
      _DraggableDurationControlState();
}

class _DraggableDurationControlState extends State<_DraggableDurationControl> {
  static const double _pixelsPerDay = 16;
  double _dragBuffer = 0;
  int? _preview;

  int get _currentValue => _preview ?? widget.value;

  void _applyDeltaDays(int delta) {
    if (delta == 0) {
      return;
    }
    final next = (_currentValue + delta).clamp(1, 3650);
    setState(() {
      _preview = next;
    });
  }

  void _commit() {
    if (_preview == null) {
      return;
    }
    final next = _preview!;
    setState(() {
      _preview = null;
      _dragBuffer = 0;
    });
    if (next != widget.value) {
      widget.onCommit(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = '${_currentValue}d';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Shorten by one day',
          onPressed: widget.enabled
              ? () => widget.onCommit((widget.value - 1).clamp(1, 3650))
              : null,
        ),
        GestureDetector(
          onHorizontalDragUpdate: widget.enabled
              ? (details) {
                  _dragBuffer += details.delta.dx;
                  final deltaDays = (_dragBuffer / _pixelsPerDay).truncate();
                  if (deltaDays == 0) {
                    return;
                  }
                  _dragBuffer -= deltaDays * _pixelsPerDay;
                  _applyDeltaDays(deltaDays);
                }
              : null,
          onHorizontalDragEnd: widget.enabled ? (_) => _commit() : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$label ↔',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Extend by one day',
          onPressed: widget.enabled
              ? () => widget.onCommit((widget.value + 1).clamp(1, 3650))
              : null,
        ),
      ],
    );
  }
}

class _BarResizeHandle extends StatefulWidget {
  const _BarResizeHandle({
    required this.enabled,
    required this.baseDurationDays,
    required this.onCommit,
    required this.barColor,
  });

  final bool enabled;
  final int baseDurationDays;
  final ValueChanged<int> onCommit;
  final Color barColor;

  @override
  State<_BarResizeHandle> createState() => _BarResizeHandleState();
}

class _BarResizeHandleState extends State<_BarResizeHandle> {
  static const double _pixelsPerDay = 14;
  double _dragPixels = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.barColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: widget.enabled
              ? (details) {
                  _dragPixels += details.delta.dx;
                }
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) {
                  final deltaDays = (_dragPixels / _pixelsPerDay).round();
                  _dragPixels = 0;
                  if (deltaDays == 0) {
                    return;
                  }
                  final next =
                      (widget.baseDurationDays + deltaDays).clamp(1, 3650);
                  widget.onCommit(next);
                }
              : null,
          child: Container(
            width: 12,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
