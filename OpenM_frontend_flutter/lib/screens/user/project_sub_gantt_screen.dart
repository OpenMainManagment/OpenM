import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class ProjectSubGanttScreen extends ConsumerStatefulWidget {
  const ProjectSubGanttScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.stepId,
    required this.stepTitle,
  });

  final String projectId;
  final String projectName;
  final String stepId;
  final String stepTitle;

  @override
  ConsumerState<ProjectSubGanttScreen> createState() =>
      _ProjectSubGanttScreenState();
}

class _ProjectSubGanttScreenState extends ConsumerState<ProjectSubGanttScreen> {
  ProjectDto? _project;
  ProjectGanttStepTreeDto? _step;
  List<EmployeeDto> _employees = const [];
  String? _employeeRoleFilter;
  String? _employeeDepartmentFilter;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait<dynamic>([
        api.projectById(widget.projectId),
        api.projectGanttTree(widget.projectId),
        api.authEmployees(),
      ]);

      final project = results[0] as ProjectDto;
      final tree = results[1] as ProjectGanttTreeResponseDto;
      final employees = results[2] as List<EmployeeDto>;
      final step = tree.ganttSteps.where((item) => item.id == widget.stepId).firstOrNull;

      if (!mounted) {
        return;
      }

      setState(() {
        _project = project;
        _step = step;
        _employees = employees;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load sub gantt: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateSubStepDuration({
    required String subStepId,
    required int durationDays,
  }) async {
    if (_project == null || _isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.updateProjectGanttSubStepDuration(
        projectId: _project!.id,
        subStepId: subStepId,
        durationDays: durationDays,
      );
      final updatedStep = response.ganttSteps.where((item) => item.id == widget.stepId).firstOrNull;
      if (!mounted) {
        return;
      }
      setState(() {
        _project = response.project;
        _step = updatedStep;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update detail step: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _updateSubStepAssignees({
    required String subStepId,
    required List<String> assigneeLogins,
  }) async {
    if (_project == null || _isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.updateProjectGanttSubStepAssignees(
        projectId: _project!.id,
        subStepId: subStepId,
        assigneeLogins: assigneeLogins,
      );
      final updatedStep = response.ganttSteps.where((item) => item.id == widget.stepId).firstOrNull;
      if (!mounted) {
        return;
      }
      setState(() {
        _project = response.project;
        _step = updatedStep;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update assignees: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _createSubStep() async {
    if (_project == null || _step == null || _isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.createProjectGanttSubStep(
        projectId: _project!.id,
        stepId: _step!.id,
        title: '${_step!.title} Detail ${_step!.subSteps.length + 1}',
      );
      final updatedStep = response.ganttSteps.where((item) => item.id == widget.stepId).firstOrNull;
      if (!mounted) {
        return;
      }
      setState(() {
        _project = response.project;
        _step = updatedStep;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add deep step: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _deleteSubStep(String subStepId) async {
    if (_project == null || _isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.deleteProjectGanttSubStep(
        projectId: _project!.id,
        subStepId: subStepId,
      );
      final updatedStep = response.ganttSteps.where((item) => item.id == widget.stepId).firstOrNull;
      if (!mounted) {
        return;
      }
      setState(() {
        _project = response.project;
        _step = updatedStep;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete deep step: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (_isLoading) {
      return AppShell(
        pageName: '${widget.projectName} - ${widget.stepTitle}',
        onAdd: () {},
        onSettings: () {},
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null || step == null) {
      return AppShell(
        pageName: '${widget.projectName} - ${widget.stepTitle}',
        onAdd: () {},
        onSettings: () {},
        child: const Center(child: Text('Sub gantt step not found')),
      );
    }

    final roles = _employees
        .map((item) => (item.role ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final departments = _employees
        .map((item) => (item.department ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final filteredEmployees = _employees.where((employee) {
      final matchesRole = _employeeRoleFilter == null ||
          _employeeRoleFilter!.isEmpty ||
          (employee.role ?? '').trim() == _employeeRoleFilter;
      final matchesDepartment = _employeeDepartmentFilter == null ||
          _employeeDepartmentFilter!.isEmpty ||
          (employee.department ?? '').trim() == _employeeDepartmentFilter;
      return matchesRole && matchesDepartment;
    }).toList();

    return AppShell(
      pageName: '${widget.projectName} - ${widget.stepTitle}',
      onAdd: () {},
      onSettings: () {},
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.stepTitle.toLowerCase().contains('procurement'))
                _ProcurementPartsStatusCard(
                  projectId: widget.projectId,
                  projectName: widget.projectName,
                ),
              Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sub Gantt: ${step.title}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _isUpdating ? null : _createSubStep,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Deep Step'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Click a task name to assign multiple people.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _employeeRoleFilter,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All roles'),
                            ),
                            ...roles.map(
                              (role) => DropdownMenuItem<String?>(
                                value: role,
                                child: Text(role),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _employeeRoleFilter = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Filter assignees by role',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _employeeDepartmentFilter,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All departments'),
                            ),
                            ...departments.map(
                              (department) => DropdownMenuItem<String?>(
                                value: department,
                                child: Text(department),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _employeeDepartmentFilter = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Filter assignees by department',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (step.subSteps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No deep steps available yet.')),
                    )
                  else
                    _SubGanttChartView(
                      subSteps: step.subSteps,
                      employees: filteredEmployees,
                      isUpdating: _isUpdating,
                      onUpdateDuration: (subStepId, durationDays) =>
                          _updateSubStepDuration(
                        subStepId: subStepId,
                        durationDays: durationDays,
                      ),
                      onUpdateAssignees: (subStepId, assigneeLogins) =>
                          _updateSubStepAssignees(
                        subStepId: subStepId,
                        assigneeLogins: assigneeLogins,
                      ),
                      onDelete: (subStepId) => _deleteSubStep(subStepId),
                    ),
                ],
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single "Procurement" point on the sub gantt, summarizing the parts
/// order status with a fixed 4-week due date and a link to the full
/// Parts Status timeline screen.
class _ProcurementPartsStatusCard extends StatelessWidget {
  const _ProcurementPartsStatusCard({
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    final dueDate = DateTime.now().add(const Duration(days: 28));
    final formattedDue =
        '${dueDate.day.toString().padLeft(2, '0')}.${dueDate.month.toString().padLeft(2, '0')}.${dueDate.year}';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined),
                const SizedBox(width: 8),
                Text(
                  'Parts Order Status',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Due date: $formattedDue (4 weeks from quotation request)'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                final encodedName = Uri.encodeQueryComponent(projectName);
                context.push(
                  '/projects/$projectId/parts-status?name=$encodedName',
                );
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Parts Status'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubGanttChartView extends StatelessWidget {
  const _SubGanttChartView({
    required this.subSteps,
    required this.employees,
    required this.isUpdating,
    required this.onUpdateDuration,
    required this.onUpdateAssignees,
    required this.onDelete,
  });

  final List<ProjectGanttSubStepDto> subSteps;
  final List<EmployeeDto> employees;
  final bool isUpdating;
  final Future<void> Function(String subStepId, int durationDays) onUpdateDuration;
  final Future<void> Function(String subStepId, List<String> assigneeLogins)
      onUpdateAssignees;
  final Future<void> Function(String subStepId) onDelete;

  static const double _leftColumnWidth = 280;
  static const double _dayWidth = 26;
  static const double _rowHeight = 84;

  @override
  Widget build(BuildContext context) {
    final validStarts = subSteps
        .map((item) => DateTime.tryParse(item.plannedStartDate ?? ''))
        .whereType<DateTime>()
        .toList();
    final validEnds = subSteps
        .map((item) => DateTime.tryParse(item.plannedEndDate ?? ''))
        .whereType<DateTime>()
        .toList();
    final start = validStarts.reduce(
      (left, right) => left.isBefore(right) ? left : right,
    );
    final end = validEnds.reduce(
      (left, right) => left.isAfter(right) ? left : right,
    );
    final totalDays = end.difference(start).inDays + 1;
    final chartWidth = (totalDays * _dayWidth).clamp(640.0, 4000.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: _leftColumnWidth,
                  child: Text(
                    'Task',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Timeline',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _leftColumnWidth + chartWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubGanttTimelineHeader(
                      leftColumnWidth: _leftColumnWidth,
                      timelineWidth: chartWidth,
                      start: start,
                      totalDays: totalDays,
                    ),
                    const SizedBox(height: 8),
                    ...subSteps.map(
                      (subStep) => _SubGanttChartRow(
                        subStep: subStep,
                        employees: employees,
                        leftColumnWidth: _leftColumnWidth,
                        timelineWidth: chartWidth,
                        timelineStart: start,
                        totalDays: totalDays,
                        isUpdating: isUpdating,
                        onUpdateDuration: onUpdateDuration,
                        onUpdateAssignees: onUpdateAssignees,
                        onDelete: onDelete,
                        canDelete: subSteps.length > 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubGanttTimelineHeader extends StatelessWidget {
  const _SubGanttTimelineHeader({
    required this.leftColumnWidth,
    required this.timelineWidth,
    required this.start,
    required this.totalDays,
  });

  final double leftColumnWidth;
  final double timelineWidth;
  final DateTime start;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(width: leftColumnWidth),
          SizedBox(
            width: timelineWidth,
            child: Stack(
              children: List.generate(totalDays, (index) {
                final day = start.add(Duration(days: index));
                final showLabel = index == 0 || index == totalDays - 1 || day.day == 1;
                return Positioned(
                  left: index * _SubGanttChartView._dayWidth,
                  width: _SubGanttChartView._dayWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    alignment: Alignment.topCenter,
                    child: showLabel
                        ? Text(
                            '${day.month}/${day.day}',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubGanttChartRow extends StatelessWidget {
  const _SubGanttChartRow({
    required this.subStep,
    required this.employees,
    required this.leftColumnWidth,
    required this.timelineWidth,
    required this.timelineStart,
    required this.totalDays,
    required this.isUpdating,
    required this.onUpdateDuration,
    required this.onUpdateAssignees,
    required this.onDelete,
    required this.canDelete,
  });

  final ProjectGanttSubStepDto subStep;
  final List<EmployeeDto> employees;
  final double leftColumnWidth;
  final double timelineWidth;
  final DateTime timelineStart;
  final int totalDays;
  final bool isUpdating;
  final Future<void> Function(String subStepId, int durationDays) onUpdateDuration;
  final Future<void> Function(String subStepId, List<String> assigneeLogins)
      onUpdateAssignees;
  final Future<void> Function(String subStepId) onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(subStep.plannedStartDate ?? '');
    final end = DateTime.tryParse(subStep.plannedEndDate ?? '');
    final duration = _durationDays(subStep.plannedStartDate, subStep.plannedEndDate);
    final currentAssignees = subStep.assigneeLogins.isNotEmpty
        ? subStep.assigneeLogins
        : (subStep.assigneeLogin == null
            ? <String>[]
            : <String>[subStep.assigneeLogin!]);
    final assigneeLabel = _assigneeLabel(currentAssignees, employees);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: leftColumnWidth,
            child: InkWell(
              onTap: isUpdating
                  ? null
                  : () async {
                      final picked = await _showAssigneePicker(
                        context: context,
                        employees: employees,
                        currentAssignees: currentAssignees,
                        taskTitle: subStep.title,
                      );
                      if (picked == null) {
                        return;
                      }
                      await onUpdateAssignees(subStep.id, picked);
                    },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            subStep.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete deep step',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: (!isUpdating && canDelete)
                              ? () => onDelete(subStep.id)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateRange(subStep.plannedStartDate, subStep.plannedEndDate),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      assigneeLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey.shade700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _DraggableDurationControl(
                        value: duration,
                        enabled: !isUpdating,
                        onCommit: (nextDuration) => onUpdateDuration(subStep.id, nextDuration),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: timelineWidth,
            height: _SubGanttChartView._rowHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: List.generate(
                      totalDays,
                      (index) => Container(
                        width: _SubGanttChartView._dayWidth,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Colors.grey.shade200),
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (start != null && end != null)
                  Positioned(
                    left: start.difference(timelineStart).inDays * _SubGanttChartView._dayWidth,
                    top: 18,
                    width: (end.difference(start).inDays + 1) * _SubGanttChartView._dayWidth,
                    height: 24,
                    child: _SubGanttBar(
                      assigneeLabel: assigneeLabel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>?> _showAssigneePicker({
    required BuildContext context,
    required List<EmployeeDto> employees,
    required List<String> currentAssignees,
    required String taskTitle,
  }) async {
    final selected = <String>{...currentAssignees};
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Assign people: $taskTitle'),
              content: SizedBox(
                width: 420,
                child: employees.isEmpty
                    ? const Text('No employees available for current filters.')
                    : ListView(
                        shrinkWrap: true,
                        children: employees
                            .map(
                              (employee) => CheckboxListTile(
                                dense: true,
                                value: selected.contains(employee.loginName),
                                title: Text(_employeeLabel(employee)),
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked ?? false) {
                                      selected.add(employee.loginName);
                                    } else {
                                      selected.remove(employee.loginName);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, selected.toList()..sort()),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _employeeLabel(EmployeeDto employee) {
    final fullName = '${employee.firstName} ${employee.lastName}'.trim();
    return fullName.isEmpty ? employee.loginName : '$fullName (${employee.loginName})';
  }

  String _assigneeLabel(List<String> assigneeLogins, List<EmployeeDto> employees) {
    if (assigneeLogins.isEmpty) {
      return 'Unassigned';
    }
    final labels = assigneeLogins.map((login) {
      final match = employees.where((item) => item.loginName == login).firstOrNull;
      if (match == null) {
        return login;
      }
      final fullName = '${match.firstName} ${match.lastName}'.trim();
      return fullName.isEmpty ? match.loginName : fullName;
    }).toList();
    return labels.join(', ');
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

class _SubGanttBar extends StatelessWidget {
  const _SubGanttBar({
    required this.assigneeLabel,
  });

  final String assigneeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.indigo.shade500,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  assigneeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
