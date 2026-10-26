import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/auth_state.dart';
import '../../widgets/app_shell.dart';

class KanboardScreen extends ConsumerStatefulWidget {
  const KanboardScreen({super.key});

  @override
  ConsumerState<KanboardScreen> createState() => _KanboardScreenState();
}

class _KanboardScreenState extends ConsumerState<KanboardScreen> {
  bool _loading = true;
  bool _moving = false;
  String? _error;
  List<TodoDto> _todos = const [];
  List<EmployeeDto> _employees = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final fetchedTodos = await api.todos();
      final todos = await _syncOverdueTodos(fetchedTodos);
      List<EmployeeDto> employees = const [];
      try {
        employees = await api.authEmployees();
      } catch (_) {
        employees = const [];
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _todos = todos;
        _employees = employees;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load the Kanboard: $error';
        _loading = false;
      });
    }
  }

  Future<List<TodoDto>> _syncOverdueTodos(List<TodoDto> todos) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidates = todos.where((todo) {
      if (_todoStatus(todo) != 'inWork') {
        return false;
      }
      final due = DateTime.tryParse(todo.endDate ?? '');
      if (due == null) {
        return false;
      }
      final dueDay = DateTime(due.year, due.month, due.day);
      return !dueDay.isAfter(today);
    }).toList();

    if (candidates.isEmpty) {
      return todos;
    }

    final api = ref.read(apiClientProvider);
    final byId = {for (final item in todos) item.id: item};

    for (final todo in candidates) {
      try {
        final updated = await api.updateTodo(
          todoId: todo.id,
          name: todo.name,
          companyId: todo.companyId,
          projectId: todo.projectId,
          folderId: todo.folderId,
          mainEmployer: todo.mainEmployer,
          coworkerLogins: todo.coworkerLogins,
          description: todo.description,
          startDate: todo.startDate,
          endDate: todo.endDate,
          projectStatus: 'Overdue',
        );
        byId[todo.id] = updated;
      } catch (_) {
        // Keep board usable even if one auto-update fails.
      }
    }

    return byId.values.toList();
  }

  String _normalized(String? value) => (value ?? '').trim().toLowerCase();

  String _normalizedStatusValue(String? value) {
    final normalized = _normalized(value);
    if (normalized == 'done' ||
        normalized == 'donelegacy' ||
        normalized == 'done') {
      return 'Done';
    }
    if (normalized == 'overdue' || normalized == 'overduelegacy') {
      return 'Overdue';
    }
    if (normalized == 'inwork' ||
        normalized == 'in work' ||
        normalized == 'in_work') {
      return 'inWork';
    }
    return normalized.isEmpty ? 'inWork' : normalized;
  }

  String _todoStatus(TodoDto todo) =>
      _normalizedStatusValue(todo.projectStatus);

  List<TodoDto> _workerTodos(String workerName) {
    final worker = _normalized(workerName);
    if (worker.isEmpty) {
      return const [];
    }

    return _todos.where((item) {
      final main = _normalized(item.mainEmployer);
      if (main == worker || main.contains(worker) || worker.contains(main)) {
        return true;
      }
      final coworkers = item.coworkerLogins.map(_normalized).toSet();
      return coworkers.contains(worker);
    }).toList();
  }

  bool _isCoworkerTaskForWorker(TodoDto todo, String workerName) {
    final worker = _normalized(workerName);
    if (worker.isEmpty) {
      return false;
    }
    if (_normalized(todo.mainEmployer) == worker) {
      return false;
    }
    final coworkers = todo.coworkerLogins.map(_normalized).toSet();
    return coworkers.contains(worker);
  }

  TodoDto _copyTodo(TodoDto source, {String? projectStatus, int? sortOrder}) {
    return TodoDto(
      id: source.id,
      name: source.name,
      sortOrder: sortOrder ?? source.sortOrder,
      companyId: source.companyId,
      projectId: source.projectId,
      folderId: source.folderId,
      department: source.department,
      mainEmployer: source.mainEmployer,
      coworkerLogins: source.coworkerLogins,
      description: source.description,
      startDate: source.startDate,
      endDate: source.endDate,
      projectStatus: projectStatus ?? source.projectStatus,
    );
  }

  String _workerDepartment(String workerName) {
    final worker = _normalized(workerName);
    if (worker.isEmpty) {
      return '';
    }

    for (final employee in _employees) {
      final login = _normalized(employee.loginName);
      final email = _normalized(employee.email);
      if (worker == login || worker == email) {
        return (employee.department ?? '').trim();
      }
    }

    return '';
  }

  List<TodoDto> _departmentTickets(String workerName) {
    final department = _normalized(_workerDepartment(workerName));
    if (department.isEmpty) {
      return const [];
    }

    final tickets = _todos.where((item) {
      final itemDepartment = _normalized(item.department);
      final hasOwner = _normalized(item.mainEmployer).isNotEmpty;
      return itemDepartment == department && !hasOwner;
    }).toList();

    tickets.sort((a, b) {
      final leftSort = a.sortOrder ?? 0;
      final rightSort = b.sortOrder ?? 0;
      if (leftSort != rightSort) {
        return leftSort.compareTo(rightSort);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return tickets;
  }

  List<TodoDto> _todosByStatus(String status, List<TodoDto> workerTasks) {
    final items = workerTasks
        .where((item) => _todoStatus(item) == _normalizedStatusValue(status))
        .toList();

    items.sort((a, b) {
      final leftSort = a.sortOrder ?? 0;
      final rightSort = b.sortOrder ?? 0;
      if (leftSort != rightSort) {
        return leftSort.compareTo(rightSort);
      }

      final leftDate = a.endDate ?? '9999-12-31';
      final rightDate = b.endDate ?? '9999-12-31';
      return leftDate.compareTo(rightDate);
    });

    return items;
  }

  void _applyLocalStatusOrder(String status, List<TodoDto> ordered) {
    final orderMap = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      orderMap[ordered[i].id] = i;
    }

    _todos = _todos.map((item) {
      final newIndex = orderMap[item.id];
      if (newIndex == null) {
        return item;
      }
      return _copyTodo(item, projectStatus: status, sortOrder: newIndex);
    }).toList();
  }

  Future<void> _persistStatusOrder(String status, List<TodoDto> ordered) async {
    await ref
        .read(apiClientProvider)
        .reorderTodos(
          projectStatus: status,
          orderedTodoIds: ordered.map((item) => item.id).toList(),
        );
  }

  Future<void> _handleDrop({
    required TodoDto todo,
    required String targetStatus,
    required int targetIndex,
    required List<TodoDto> workerTasks,
    required String workerName,
  }) async {
    if (_moving) {
      return;
    }

    final sourceStatus = _todoStatus(todo);

    final sourceWithoutDragged = _todosByStatus(
      sourceStatus,
      workerTasks,
    ).where((item) => item.id != todo.id).toList();

    final targetBase = sourceStatus == targetStatus
        ? List<TodoDto>.from(sourceWithoutDragged)
        : _todosByStatus(
            targetStatus,
            workerTasks,
          ).where((item) => item.id != todo.id).toList();

    final insertIndex = targetIndex.clamp(0, targetBase.length);
    targetBase.insert(insertIndex, todo);

    setState(() {
      if (sourceStatus == targetStatus) {
        _applyLocalStatusOrder(targetStatus, targetBase);
      } else {
        _applyLocalStatusOrder(sourceStatus, sourceWithoutDragged);
        _applyLocalStatusOrder(targetStatus, targetBase);
      }
    });

    setState(() {
      _moving = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final normalizedWorker = workerName.trim();
      final shouldAssignOwner =
          normalizedWorker.isNotEmpty && _normalized(todo.mainEmployer).isEmpty;

      if (sourceStatus != targetStatus || shouldAssignOwner) {
        final updated = await api.updateTodo(
          todoId: todo.id,
          name: todo.name,
          companyId: todo.companyId,
          projectId: todo.projectId,
          folderId: todo.folderId,
          department: todo.department,
          mainEmployer: shouldAssignOwner
              ? normalizedWorker
              : todo.mainEmployer,
          coworkerLogins: todo.coworkerLogins,
          description: todo.description,
          startDate: todo.startDate,
          endDate: todo.endDate,
          projectStatus: targetStatus,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _todos = _todos
              .map((item) => item.id == updated.id ? updated : item)
              .toList();
        });
      }

      await _persistStatusOrder(targetStatus, targetBase);
      if (sourceStatus != targetStatus) {
        await _persistStatusOrder(sourceStatus, sourceWithoutDragged);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save board order.')),
        );
      }
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _moving = false;
        });
      }
    }
  }

  Future<void> _deleteTodo(TodoDto todo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task'),
        content: Text('Delete "${todo.name}"?'),
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

    if (confirm != true) {
      return;
    }

    try {
      await ref.read(apiClientProvider).deleteTodo(todo.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _todos = _todos.where((item) => item.id != todo.id).toList();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not delete task.')));
    }
  }

  Future<void> _addCoworkersToTask(TodoDto todo) async {
    if (_employees.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No coworkers available to select.')),
      );
      return;
    }

    final currentWorkerName =
        ref.read(authStateProvider).employeeName?.trim() ?? '';
    final selectableEmployees = _employees
        .where(
          (employee) =>
              _normalized(employee.loginName) != _normalized(currentWorkerName),
        )
        .toList();

    if (selectableEmployees.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other coworkers available.')),
      );
      return;
    }

    final selected = todo.coworkerLogins.toSet();
    String search = '';

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add coworkers'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search coworkers',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        search = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  for (final employee in selectableEmployees.where((employee) {
                    final query = search.trim().toLowerCase();
                    if (query.isEmpty) {
                      return true;
                    }
                    final fullName =
                        '${employee.firstName} ${employee.lastName}'
                            .toLowerCase();
                    return fullName.contains(query) ||
                        employee.loginName.toLowerCase().contains(query) ||
                        employee.email.toLowerCase().contains(query);
                  }))
                    CheckboxListTile(
                      value: selected.contains(employee.loginName),
                      title: Text('${employee.firstName} ${employee.lastName}'),
                      subtitle: Text(employee.loginName),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(employee.loginName);
                          } else {
                            selected.remove(employee.loginName);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (save != true) {
      return;
    }

    try {
      final updated = await ref
          .read(apiClientProvider)
          .updateTodo(
            todoId: todo.id,
            name: todo.name,
            companyId: todo.companyId,
            projectId: todo.projectId,
            folderId: todo.folderId,
            department: todo.department,
            mainEmployer: todo.mainEmployer,
            coworkerLogins: selected.toList()..sort(),
            description: todo.description,
            startDate: todo.startDate,
            endDate: todo.endDate,
            projectStatus: todo.projectStatus,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _todos = _todos
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update coworkers.')),
      );
    }
  }

  Future<String?> _pickDateValue({String? initialDate}) async {
    final initial = DateTime.tryParse(initialDate ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return null;
    }
    return picked.toIso8601String().split('T').first;
  }

  DateTime? _parseDateOnly(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Future<void> _openRepresentationDialog(String workerName) async {
    final currentWorker = workerName.trim();
    if (currentWorker.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Worker not identified.')));
      return;
    }

    final selectableEmployees = _employees
        .where(
          (employee) =>
              _normalized(employee.loginName) != _normalized(currentWorker),
        )
        .toList();

    if (selectableEmployees.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No coworkers available.')));
      return;
    }

    final now = DateTime.now();
    String startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().split('T').first;
    String endDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7)).toIso8601String().split('T').first;
    String? selectedCoworker = selectableEmployees.first.loginName;
    String search = '';
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = selectableEmployees.where((employee) {
            final query = search.trim().toLowerCase();
            if (query.isEmpty) {
              return true;
            }
            final fullName = '${employee.firstName} ${employee.lastName}'
                .toLowerCase();
            return fullName.contains(query) ||
                employee.loginName.toLowerCase().contains(query) ||
                employee.email.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: const Text('Representation'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickDateValue(
                                initialDate: startDate,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.event_outlined),
                            label: Text('Start: $startDate'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickDateValue(
                                initialDate: endDate,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text('End: $endDate'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search coworker',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          search = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No coworker found.'),
                      )
                    else
                      ...filtered.map(
                        (employee) => RadioListTile<String>(
                          value: employee.loginName,
                          groupValue: selectedCoworker,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedCoworker = value;
                            });
                          },
                          title: Text(
                            '${employee.firstName} ${employee.lastName}',
                          ),
                          subtitle: Text(employee.loginName),
                        ),
                      ),
                  ],
                ),
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
                        final start = _parseDateOnly(startDate);
                        final end = _parseDateOnly(endDate);
                        final delegate = selectedCoworker;
                        if (start == null || end == null || delegate == null) {
                          return;
                        }
                        if (start.isAfter(end)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Start date must be before end date.',
                              ),
                            ),
                          );
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                        });

                        try {
                          final result = await ref
                              .read(apiClientProvider)
                              .createTodoRepresentation(
                                delegateLogin: delegate,
                                startDate: startDate,
                                endDate: endDate,
                              );
                          final updated =
                              (result['updated'] as num?)?.toInt() ?? 0;
                          final activatedNow =
                              (result['activated_now'] as num?)?.toInt() ?? 0;

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await _load();
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                updated == 0
                                    ? 'No own tasks found in selected date range.'
                                    : 'Representation saved: $updated tasks, active now: $activatedNow.',
                              ),
                            ),
                          );
                        } catch (_) {
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not transfer tasks.'),
                            ),
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Applying...' : 'Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEditTaskDialog(TodoDto todo) async {
    final titleCtrl = TextEditingController(text: todo.name);
    final descriptionCtrl = TextEditingController(text: todo.description ?? '');
    String? startDate = todo.startDate;
    String? endDate = todo.endDate;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Task title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateValue(
                            initialDate: startDate,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              startDate = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          startDate == null
                              ? 'Start date'
                              : 'Start: $startDate',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateValue(
                            initialDate: endDate,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              endDate = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          endDate == null ? 'End date' : 'End: $endDate',
                        ),
                      ),
                    ),
                  ],
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
                      if (title.isEmpty) {
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                      });
                      try {
                        final updated = await ref
                            .read(apiClientProvider)
                            .updateTodo(
                              todoId: todo.id,
                              name: title,
                              companyId: todo.companyId,
                              projectId: todo.projectId,
                              folderId: todo.folderId,
                              department: todo.department,
                              mainEmployer: todo.mainEmployer,
                              coworkerLogins: todo.coworkerLogins,
                              description: descriptionCtrl.text.trim().isEmpty
                                  ? null
                                  : descriptionCtrl.text.trim(),
                              startDate: startDate,
                              endDate: endDate,
                              projectStatus: todo.projectStatus,
                            );

                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _todos = _todos
                              .map(
                                (item) =>
                                    item.id == updated.id ? updated : item,
                              )
                              .toList();
                        });
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (_) {
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update task.'),
                          ),
                        );
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

  Future<void> _openAddTaskDialog(String workerName) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final now = DateTime.now();
    String startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().split('T').first;
    String endDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7)).toIso8601String().split('T').first;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Task title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateValue(
                            initialDate: startDate,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              startDate = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text('Start: $startDate'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickDateValue(
                            initialDate: endDate,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              endDate = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('End: $endDate'),
                      ),
                    ),
                  ],
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
                      if (title.isEmpty) {
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                      });

                      try {
                        await ref
                            .read(apiClientProvider)
                            .createTodo(
                              name: title,
                              department: _workerDepartment(workerName),
                              mainEmployer: workerName.trim().isEmpty
                                  ? null
                                  : workerName.trim(),
                              description: descriptionCtrl.text.trim().isEmpty
                                  ? null
                                  : descriptionCtrl.text.trim(),
                              startDate: startDate,
                              endDate: endDate,
                              projectStatus: 'inWork',
                            );

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                      } catch (_) {
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not create task.'),
                          ),
                        );
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    final workerName = ref.watch(authStateProvider).employeeName ?? '';
    final workerTasks = _workerTodos(workerName);
    final departmentTickets = _departmentTickets(workerName);
    final workerDepartment = _workerDepartment(workerName);
    final openTaskCount = workerTasks
        .where((todo) => _todoStatus(todo) != 'Done')
        .length;

    return AppShell(
      pageName: 'Kanboard',
      onAdd: _load,
      onSettings: _openSettings,
      child: _loading
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
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workerName.trim().isEmpty
                                  ? 'Worker: not identified'
                                  : 'Worker: $workerName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Tasks assigned: $openTaskCount'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _openAddTaskDialog(workerName),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Add Task'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _openRepresentationDialog(workerName),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Representation'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 1100;
                        final columns = [
                          _StatusColumn(
                            title: 'In Work',
                            color: AppColors.kanbanInWorkColumn,
                            todos: _todosByStatus('inWork', workerTasks),
                            currentWorkerName: workerName,
                            isCoworkerTaskForWorker: _isCoworkerTaskForWorker,
                            onEditTodo: _openEditTaskDialog,
                            onAddCoworkers: _addCoworkersToTask,
                            onDeleteTodo: _deleteTodo,
                            onTodoDroppedAt: (todo, index) => _handleDrop(
                              todo: todo,
                              targetStatus: 'inWork',
                              targetIndex: index,
                              workerTasks: workerTasks,
                              workerName: workerName,
                            ),
                          ),
                          _StatusColumn(
                            title: 'Done',
                            color: AppColors.kanbanDoneColumn,
                            todos: _todosByStatus('Done', workerTasks),
                            currentWorkerName: workerName,
                            isCoworkerTaskForWorker: _isCoworkerTaskForWorker,
                            onEditTodo: _openEditTaskDialog,
                            onAddCoworkers: _addCoworkersToTask,
                            onDeleteTodo: _deleteTodo,
                            onTodoDroppedAt: (todo, index) => _handleDrop(
                              todo: todo,
                              targetStatus: 'Done',
                              targetIndex: index,
                              workerTasks: workerTasks,
                              workerName: workerName,
                            ),
                          ),
                          _StatusColumn(
                            title: 'Overdue',
                            color: AppColors.kanbanOverdueColumn,
                            todos: _todosByStatus('Overdue', workerTasks),
                            currentWorkerName: workerName,
                            isCoworkerTaskForWorker: _isCoworkerTaskForWorker,
                            onEditTodo: _openEditTaskDialog,
                            onAddCoworkers: _addCoworkersToTask,
                            onDeleteTodo: _deleteTodo,
                            onTodoDroppedAt: (todo, index) => _handleDrop(
                              todo: todo,
                              targetStatus: 'Overdue',
                              targetIndex: index,
                              workerTasks: workerTasks,
                              workerName: workerName,
                            ),
                          ),
                        ];

                        if (compact) {
                          return ListView.separated(
                            itemCount: columns.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, index) =>
                                SizedBox(height: 260, child: columns[index]),
                          );
                        }

                        return Row(
                          children: [
                            for (var i = 0; i < columns.length; i++) ...[
                              Expanded(child: columns[i]),
                              if (i != columns.length - 1)
                                const SizedBox(width: 12),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DepartmentTicketBar(
                    department: workerDepartment,
                    tickets: departmentTickets,
                  ),
                ],
              ),
            ),
    );
  }
}

class _DepartmentTicketBar extends StatelessWidget {
  const _DepartmentTicketBar({required this.department, required this.tickets});

  final String department;
  final List<TodoDto> tickets;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              department.trim().isEmpty
                  ? 'Department Tickets (no department assigned to worker)'
                  : 'Department Tickets: $department',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (tickets.isEmpty)
              const Text('No open tickets in this department.')
            else
              SizedBox(
                height: 96,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final ticket = tickets[index];
                      final tile = Container(
                        width: 260,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.black12),
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              ticket.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ticket.description ?? 'No description',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );

                      return Draggable<TodoDto>(
                        data: ticket,
                        feedback: Material(
                          elevation: 6,
                          color: AppColors.transparent,
                          child: SizedBox(width: 260, child: tile),
                        ),
                        childWhenDragging: Opacity(opacity: 0.35, child: tile),
                        child: tile,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.title,
    required this.color,
    required this.todos,
    required this.currentWorkerName,
    required this.isCoworkerTaskForWorker,
    required this.onEditTodo,
    required this.onAddCoworkers,
    required this.onDeleteTodo,
    required this.onTodoDroppedAt,
  });

  final String title;
  final Color color;
  final List<TodoDto> todos;
  final String currentWorkerName;
  final bool Function(TodoDto todo, String workerName) isCoworkerTaskForWorker;
  final Future<void> Function(TodoDto todo) onEditTodo;
  final Future<void> Function(TodoDto todo) onAddCoworkers;
  final Future<void> Function(TodoDto todo) onDeleteTodo;
  final Future<void> Function(TodoDto todo, int index) onTodoDroppedAt;

  Widget _dropLine({required int index}) {
    return DragTarget<TodoDto>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onTodoDroppedAt(details.data, index),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 4),
          height: hovering ? 14 : 8,
          decoration: BoxDecoration(
            color: hovering ? AppColors.kanbanDropHover : AppColors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title (${todos.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: todos.isEmpty
                  ? _dropLine(index: 0)
                  : ListView.builder(
                      itemCount: todos.length * 2 + 1,
                      itemBuilder: (_, rowIndex) {
                        if (rowIndex.isEven) {
                          final dropIndex = rowIndex ~/ 2;
                          return _dropLine(index: dropIndex);
                        }

                        final todoIndex = rowIndex ~/ 2;
                        final todo = todos[todoIndex];
                        final due = todo.endDate ?? '-';
                        final isCoworker = isCoworkerTaskForWorker(
                          todo,
                          currentWorkerName,
                        );
                        final hasCoworkers = todo.coworkerLogins.isNotEmpty;

                        final tile = Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: (isCoworker || hasCoworkers)
                                ? AppColors.coworkerHighlight
                                : AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.black12),
                          ),
                          child: ListTile(
                            title: Text(todo.name),
                            subtitle: Text(
                              'Due: $due\n${todo.description ?? ''}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit task',
                                  onPressed: () => onEditTodo(todo),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Add coworkers',
                                  onPressed: () => onAddCoworkers(todo),
                                  icon: const Icon(Icons.group_add_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete task',
                                  onPressed: () => onDeleteTodo(todo),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                                const Icon(Icons.drag_indicator),
                              ],
                            ),
                          ),
                        );

                        return Draggable<TodoDto>(
                          data: todo,
                          feedback: Material(
                            elevation: 6,
                            color: AppColors.transparent,
                            child: SizedBox(width: 280, child: tile),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: tile,
                          ),
                          child: tile,
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
