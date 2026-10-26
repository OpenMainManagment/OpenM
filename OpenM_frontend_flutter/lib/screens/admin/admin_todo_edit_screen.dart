import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminTodoEditScreen extends ConsumerStatefulWidget {
  const AdminTodoEditScreen({super.key});

  @override
  ConsumerState<AdminTodoEditScreen> createState() =>
      _AdminTodoEditScreenState();
}

class _AdminTodoEditScreenState extends ConsumerState<AdminTodoEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mainEmployerCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  List<TodoDto> _todos = const [];
  List<CompanyDto> _companies = const [];
  List<EmployeeDto> _employees = const [];
  Map<String, List<ProjectDto>> _projectsByCompany = const {};

  bool _loading = true;
  bool _saving = false;
  String? _selectedTodoId;
  String _scope = 'company';
  String? _selectedCompanyId;
  String? _selectedProjectId;
  Set<String> _selectedCoworkerLogins = {};
  String _projectStatus = 'inWork';
  String? _startDate;
  String? _endDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mainEmployerCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  List<ProjectDto> get _selectedCompanyProjects {
    if (_selectedCompanyId == null) {
      return const [];
    }
    return _projectsByCompany[_selectedCompanyId!] ?? const [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final companies = await api.companies();
      final todos = await api.todos();
      final employees = await api.adminEmployees();

      final projectsByCompany = <String, List<ProjectDto>>{};
      if (companies.isNotEmpty) {
        final loaded = await Future.wait(
          companies.map((c) => api.projectsByMainCompany(c.id)),
        );
        for (var i = 0; i < companies.length; i++) {
          projectsByCompany[companies[i].id] = loaded[i];
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _companies = companies;
        _employees = employees;
        _todos = todos;
        _projectsByCompany = projectsByCompany;
        _loading = false;
      });

      if (_selectedTodoId != null) {
        final match = _todos
            .where((item) => item.id == _selectedTodoId)
            .firstOrNull;
        if (match != null) {
          _loadTodoIntoForm(match);
        }
      }
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? '${detail['detail']}'
          : 'Could not load ToDos.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() {
        _loading = false;
      });
    }
  }

  void _clearForm() {
    setState(() {
      _selectedTodoId = null;
      _nameCtrl.clear();
      _mainEmployerCtrl.clear();
      _descriptionCtrl.clear();
      _scope = 'company';
      _selectedCompanyId = _companies.isEmpty ? null : _companies.first.id;
      _selectedProjectId = null;
      _selectedCoworkerLogins = {};
      _projectStatus = 'inWork';
      _startDate = null;
      _endDate = null;
    });
  }

  void _loadTodoIntoForm(TodoDto todo) {
    final hasProject = todo.projectId != null && todo.projectId!.isNotEmpty;
    setState(() {
      _selectedTodoId = todo.id;
      _nameCtrl.text = todo.name;
      _mainEmployerCtrl.text = todo.mainEmployer ?? '';
      _descriptionCtrl.text = todo.description ?? '';
      _scope = hasProject ? 'project' : 'company';
      _selectedCompanyId = todo.companyId;
      _selectedProjectId = todo.projectId;
      _selectedCoworkerLogins = todo.coworkerLogins.toSet();
      _projectStatus = todo.projectStatus ?? 'inWork';
      _startDate = todo.startDate;
      _endDate = todo.endDate;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = DateTime.tryParse(
      isStart ? (_startDate ?? '') : (_endDate ?? ''),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    final value = picked.toIso8601String().split('T').first;
    setState(() {
      if (isStart) {
        _startDate = value;
      } else {
        _endDate = value;
      }
    });
  }

  Future<void> _saveTodo() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _selectedCompanyId == null) {
      return;
    }
    if (_scope == 'project' &&
        (_selectedProjectId == null || _selectedProjectId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project for project action.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final payload = {
        'name': _nameCtrl.text.trim(),
        'companyId': _selectedCompanyId,
        'projectId': _scope == 'project' ? _selectedProjectId : null,
        'mainEmployer': _mainEmployerCtrl.text.trim().isEmpty
            ? null
            : _mainEmployerCtrl.text.trim(),
        'coworkerLogins': _selectedCoworkerLogins.toList()..sort(),
        'description': _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        'startDate': _startDate,
        'endDate': _endDate,
        'projectStatus': _projectStatus,
      };

      if (_selectedTodoId == null) {
        await api.createTodo(
          name: payload['name'] as String,
          companyId: payload['companyId'] as String?,
          projectId: payload['projectId'] as String?,
          mainEmployer: payload['mainEmployer'] as String?,
          coworkerLogins: payload['coworkerLogins'] as List<String>,
          description: payload['description'] as String?,
          startDate: payload['startDate'] as String?,
          endDate: payload['endDate'] as String?,
          projectStatus: payload['projectStatus'] as String,
        );
      } else {
        await api.updateTodo(
          todoId: _selectedTodoId!,
          name: payload['name'] as String,
          companyId: payload['companyId'] as String?,
          projectId: payload['projectId'] as String?,
          mainEmployer: payload['mainEmployer'] as String?,
          coworkerLogins: payload['coworkerLogins'] as List<String>,
          description: payload['description'] as String?,
          startDate: payload['startDate'] as String?,
          endDate: payload['endDate'] as String?,
          projectStatus: payload['projectStatus'] as String,
        );
      }

      if (!mounted) {
        return;
      }

      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedTodoId == null ? 'ToDo created.' : 'ToDo updated.',
          ),
        ),
      );
      _clearForm();
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? '${detail['detail']}'
          : 'Could not save ToDo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteSelectedTodo() async {
    if (_selectedTodoId == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ToDo'),
        content: const Text('Delete the selected ToDo action?'),
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
      await ref.read(apiClientProvider).deleteTodo(_selectedTodoId!);
      if (!mounted) {
        return;
      }
      await _load();
      _clearForm();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ToDo deleted.')));
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      final message = detail is Map && detail['detail'] != null
          ? '${detail['detail']}'
          : 'Could not delete ToDo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _companyLabel(String? companyId) {
    if (companyId == null) {
      return 'No company';
    }
    final company = _companies
        .where((item) => item.id == companyId)
        .firstOrNull;
    return company?.uniqueName ?? 'Unknown company';
  }

  String _projectLabel(String? companyId, String? projectId) {
    if (projectId == null || companyId == null) {
      return '-';
    }
    final projects = _projectsByCompany[companyId] ?? const [];
    final project = projects.where((item) => item.id == projectId).firstOrNull;
    return project?.name ?? '-';
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Admin ToDo Edit',
      onAdd: _clearForm,
      onSettings: _openSettings,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Describe and schedule actions that happen in project timelines or at company level.',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'ToDo Actions',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: _todos.isEmpty
                                      ? const Center(
                                          child: Text('No ToDos yet'),
                                        )
                                      : ListView.separated(
                                          itemCount: _todos.length,
                                          separatorBuilder: (_, _) =>
                                              const Divider(height: 1),
                                          itemBuilder: (_, index) {
                                            final todo = _todos[index];
                                            final selected =
                                                _selectedTodoId == todo.id;
                                            final actionScope =
                                                todo.projectId == null
                                                ? 'Company action'
                                                : 'Project action';
                                            final timing =
                                                '${todo.startDate ?? '-'} -> ${todo.endDate ?? '-'}';
                                            final coworkerInfo =
                                                todo.coworkerLogins.isEmpty
                                                ? 'no coworkers'
                                                : '${todo.coworkerLogins.length} coworkers';
                                            return ListTile(
                                              selected: selected,
                                              title: Text(todo.name),
                                              subtitle: Text(
                                                '$actionScope | ${_companyLabel(todo.companyId)} | ${_projectLabel(todo.companyId, todo.projectId)} | $timing | $coworkerInfo',
                                              ),
                                              onTap: () =>
                                                  _loadTodoIntoForm(todo),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 6,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Form(
                                key: _formKey,
                                child: ListView(
                                  children: [
                                    Text(
                                      _selectedTodoId == null
                                          ? 'Create ToDo Action'
                                          : 'Edit ToDo Action',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _nameCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Action title',
                                        hintText:
                                            'e.g. Contract review reminder',
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter an action title';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    SegmentedButton<String>(
                                      segments: const [
                                        ButtonSegment<String>(
                                          value: 'company',
                                          label: Text('Company action'),
                                        ),
                                        ButtonSegment<String>(
                                          value: 'project',
                                          label: Text('Project action'),
                                        ),
                                      ],
                                      selected: {_scope},
                                      onSelectionChanged: (selection) {
                                        final scope = selection.first;
                                        setState(() {
                                          _scope = scope;
                                          if (_scope == 'company') {
                                            _selectedProjectId = null;
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedCompanyId,
                                      decoration: const InputDecoration(
                                        labelText: 'Company',
                                      ),
                                      items: _companies
                                          .map(
                                            (company) =>
                                                DropdownMenuItem<String>(
                                                  value: company.id,
                                                  child: Text(
                                                    company.uniqueName,
                                                  ),
                                                ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedCompanyId = value;
                                          final projectIds =
                                              _selectedCompanyProjects
                                                  .map((item) => item.id)
                                                  .toSet();
                                          if (!projectIds.contains(
                                            _selectedProjectId,
                                          )) {
                                            _selectedProjectId = null;
                                          }
                                        });
                                      },
                                      validator: (value) => value == null
                                          ? 'Please select a company'
                                          : null,
                                    ),
                                    if (_scope == 'project') ...[
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedProjectId,
                                        decoration: const InputDecoration(
                                          labelText: 'Project',
                                        ),
                                        items: _selectedCompanyProjects
                                            .map(
                                              (project) =>
                                                  DropdownMenuItem<String>(
                                                    value: project.id,
                                                    child: Text(project.name),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedProjectId = value;
                                          });
                                        },
                                        validator: (value) {
                                          if (_scope == 'project' &&
                                              value == null) {
                                            return 'Please select a project';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _mainEmployerCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Main responsible employee',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Coworkers (can see and edit)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _employees.map((employee) {
                                        final login = employee.loginName;
                                        final selected = _selectedCoworkerLogins
                                            .contains(login);
                                        return FilterChip(
                                          label: Text(
                                            '${employee.firstName} ${employee.lastName}',
                                          ),
                                          selected: selected,
                                          onSelected: (value) {
                                            setState(() {
                                              if (value) {
                                                _selectedCoworkerLogins.add(
                                                  login,
                                                );
                                              } else {
                                                _selectedCoworkerLogins.remove(
                                                  login,
                                                );
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _descriptionCtrl,
                                      minLines: 3,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        labelText: 'Action description',
                                        hintText:
                                            'Describe what should happen and when.',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      initialValue: _projectStatus,
                                      decoration: const InputDecoration(
                                        labelText: 'Status',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'inWork',
                                          child: Text('In Work'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Done',
                                          child: Text('Done'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Overdue',
                                          child: Text('Overdue'),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          _projectStatus = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _pickDate(isStart: true),
                                            icon: const Icon(
                                              Icons.event_outlined,
                                            ),
                                            label: Text(
                                              _startDate == null
                                                  ? 'Select start date'
                                                  : 'Start: $_startDate',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _pickDate(isStart: false),
                                            icon: const Icon(
                                              Icons.event_available_outlined,
                                            ),
                                            label: Text(
                                              _endDate == null
                                                  ? 'Select end date'
                                                  : 'End: $_endDate',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        FilledButton(
                                          onPressed: _saving ? null : _saveTodo,
                                          child: Text(
                                            _saving ? 'Saving...' : 'Save ToDo',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: _saving
                                              ? null
                                              : _clearForm,
                                          child: const Text('New'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed:
                                              _saving || _selectedTodoId == null
                                              ? null
                                              : _deleteSelectedTodo,
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
