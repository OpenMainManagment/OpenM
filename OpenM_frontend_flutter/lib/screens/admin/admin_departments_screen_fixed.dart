import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminDepartmentsScreen extends ConsumerStatefulWidget {
  const AdminDepartmentsScreen({super.key});

  @override
  ConsumerState<AdminDepartmentsScreen> createState() =>
      _AdminDepartmentsScreenState();
}

class _AdminDepartmentsScreenState
    extends ConsumerState<AdminDepartmentsScreen> {
  List<CompanyRoleDto> _roles = const [];
  List<DepartmentDto> _departments = const [];
  List<EmployeeDto> _employees = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);

      // Get list of companies to use the first one as context
      final companies = await api.companies();
      if (companies.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _departments = const [];
          _loading = false;
        });
        return;
      }

      // Use the first company's ID to load departments
      final companyId = companies.first.id;
      final departments = await api.departments(companyId);
      final roles = await api.companyRoles(companyId);
      final employees = await api.adminEmployees();

      if (!mounted) {
        return;
      }
      setState(() {
        _departments = departments;
        _roles = roles;
        _employees = employees;
      });
    } on DioException catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      String? detail;
      if (error.response?.data is Map<String, dynamic>) {
        final data = error.response?.data as Map<String, dynamic>;
        detail = data['detail'] as String?;
        // Try to get more detailed error info
        detail ??= data['message'] as String?;
        detail ??= data['error'] as String?;
      }
      setState(() {
        _error =
            detail ??
            'Failed to load departments. Status: ${error.response?.statusCode}. Error: $error. Stack: $stackTrace';
      });
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error =
            'Failed to load departments. Error: $error. Stack: $stackTrace';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadDepartments() async {
    await _loadDepartments();
  }

  Future<void> _openDepartmentDialog({DepartmentDto? department}) async {
    // Get current company ID or the first available company
    final companies = await ref.read(apiClientProvider).companies();
    if (companies.isEmpty) {
      setState(() {
        _error = 'No companies available. Please create a company first.';
      });
      return;
    }

    final currentCompanyId = companies.first.id;

    // Simplified dialog without company ID dependency
    final nameCtrl = TextEditingController(text: department?.name ?? '');
    final templateCtrl = TextEditingController();
    final selectedRoleIds = <String>{...?(department?.roleIds)};
    final folderTemplates = <String>[...?(department?.folderTemplates)];
    final projectActions = <String>[...?(department?.projectActions)];
    final selectedEmployeeIds = <String>{
      for (final employee in _employees)
        if ((employee.department ?? '').trim().toLowerCase() ==
            (department?.name ?? '').trim().toLowerCase())
          employee.id,
    };

    List<CompanyRoleDto> availableRoles() {
      // Simplified - no filtering by company
      return _roles;
    }

    List<CompanyRoleDto> assignedRoles() {
      final roleMap = {for (final role in _roles) role.id: role};
      final result = <CompanyRoleDto>[];
      for (final roleId in selectedRoleIds) {
        final role = roleMap[roleId];
        if (role != null) {
          result.add(role);
        }
      }
      return result;
    }

    List<EmployeeDto> availableEmployees() {
      return _employees
          .where((employee) => !selectedEmployeeIds.contains(employee.id))
          .toList();
    }

    List<EmployeeDto> assignedEmployees() {
      return _employees
          .where((employee) => selectedEmployeeIds.contains(employee.id))
          .toList();
    }

    String employeeLabel(EmployeeDto employee) {
      final fullName = '${employee.firstName} ${employee.lastName}'.trim();
      if (fullName.isEmpty) {
        return employee.loginName;
      }
      return '$fullName (${employee.loginName})';
    }

    Widget buildRoleCard(CompanyRoleDto role) {
      return Draggable<String>(
        data: role.id,
        feedback: Material(
          color: AppColors.transparent,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(role.name),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: Chip(label: Text(role.name)),
        ),
        child: Chip(label: Text(role.name)),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            department == null ? 'Add Department' : 'Edit Department',
          ),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Department name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Roles in department',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (_roles.isEmpty)
                    const Text(
                      'No roles available. Create roles first in Employees > Role Editor.',
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (details) {
                              return selectedRoleIds.contains(details.data);
                            },
                            onAcceptWithDetails: (details) {
                              selectedRoleIds.remove(details.data);
                              setDialogState(() {});
                            },
                            builder: (context, _, _) => Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.adminDropZoneBorder,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Available roles (drag to right)'),
                                  const SizedBox(height: 8),
                                  if (availableRoles().isEmpty)
                                    const Text('No available roles')
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: availableRoles()
                                          .map(buildRoleCard)
                                          .toList(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (details) {
                              return !selectedRoleIds.contains(details.data);
                            },
                            onAcceptWithDetails: (details) {
                              selectedRoleIds.add(details.data);
                              setDialogState(() {});
                            },
                            builder: (context, _, _) => Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.adminDropZoneBorder,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Assigned roles (drag to left)'),
                                  const SizedBox(height: 8),
                                  if (assignedRoles().isEmpty)
                                    const Text('No assigned roles')
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: assignedRoles()
                                          .map(buildRoleCard)
                                          .toList(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Employees in department',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (_employees.isEmpty)
                    const Text('No employees available')
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.adminDropZoneBorder,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Available employees'),
                                const SizedBox(height: 8),
                                if (availableEmployees().isEmpty)
                                  const Text('No available employees')
                                else
                                  ...availableEmployees().map(
                                    (employee) => CheckboxListTile(
                                      dense: true,
                                      value: false,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(employeeLabel(employee)),
                                      onChanged: (_) {
                                        selectedEmployeeIds.add(employee.id);
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.adminDropZoneBorder,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Assigned employees'),
                                const SizedBox(height: 8),
                                if (assignedEmployees().isEmpty)
                                  const Text('No assigned employees')
                                else
                                  ...assignedEmployees().map(
                                    (employee) => CheckboxListTile(
                                      dense: true,
                                      value: true,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(employeeLabel(employee)),
                                      onChanged: (_) {
                                        selectedEmployeeIds.remove(employee.id);
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Folder Templates',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: templateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Template name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (templateCtrl.text.trim().isNotEmpty) {
                            folderTemplates.add(templateCtrl.text.trim());
                            templateCtrl.clear();
                            setDialogState(() {});
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: folderTemplates
                              .map(
                                (template) => Chip(
                                  label: Text(template),
                                  deleteIcon: const Icon(Icons.close),
                                  onDeleted: () {
                                    folderTemplates.remove(template);
                                    setDialogState(() {});
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) {
                  return;
                }

                try {
                  final api = ref.read(apiClientProvider);
                  final newDepartment = DepartmentDto(
                    id:
                        department?.id ??
                        'new-${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    roleIds: selectedRoleIds.toList(),
                    folderTemplates: folderTemplates,
                    projectActions: projectActions,
                    roleNames: selectedRoleIds.map((roleId) {
                      final role = _roles.firstWhere(
                        (r) => r.id == roleId,
                        orElse: () => CompanyRoleDto(
                          id: roleId,
                          name: 'Unknown Role',
                          permissions: const [],
                        ),
                      );
                      return role.name;
                    }).toList(),
                  );

                  if (department == null) {
                    await api.createDepartment(
                      companyId: currentCompanyId,
                      name: newDepartment.name,
                      roleIds: newDepartment.roleIds,
                      folderTemplates: newDepartment.folderTemplates,
                      projectActions: newDepartment.projectActions,
                    );
                  } else {
                    await api.updateDepartment(
                      departmentId: newDepartment.id,
                      name: newDepartment.name,
                      roleIds: newDepartment.roleIds,
                      folderTemplates: newDepartment.folderTemplates,
                      projectActions: newDepartment.projectActions,
                    );
                  }

                  final previousDepartmentName = department?.name.trim();
                  final newDepartmentName = newDepartment.name.trim();
                  for (final employee in _employees) {
                    final currentDepartment = employee.department?.trim();
                    final isAssigned = selectedEmployeeIds.contains(
                      employee.id,
                    );
                    final wasInEditedDepartment =
                        previousDepartmentName != null &&
                        previousDepartmentName.isNotEmpty &&
                        (currentDepartment ?? '').toLowerCase() ==
                            previousDepartmentName.toLowerCase();

                    String? nextDepartment;
                    if (isAssigned) {
                      nextDepartment = newDepartmentName;
                    } else if (wasInEditedDepartment) {
                      nextDepartment = null;
                    } else {
                      continue;
                    }

                    if ((currentDepartment ?? '') == (nextDepartment ?? '')) {
                      continue;
                    }

                    await api.updateEmployee(
                      employeeId: employee.id,
                      department: nextDepartment,
                      companyId: currentCompanyId,
                    );
                  }

                  Navigator.of(context).pop();
                  await _reloadDepartments();
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _error = 'Failed to save department: $error';
                  });
                }
              },
              child: Text(department == null ? 'Create' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Admin Departments',
      onAdd: () => _openDepartmentDialog(),
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error loading departments',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_error!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadDepartments,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ListView.builder(
                      itemCount: _departments.length,
                      itemBuilder: (context, index) {
                        final department = _departments[index];
                        return Card(
                          child: ListTile(
                            title: Text(department.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (department.roleIds.isNotEmpty)
                                  Text(
                                    '${department.roleIds.length} roles assigned',
                                  ),
                                if (department.folderTemplates.isNotEmpty)
                                  Text(
                                    '${department.folderTemplates.length} folder templates',
                                  ),
                                Text(
                                  '${_employees.where((employee) => (employee.department ?? '').trim().toLowerCase() == department.name.trim().toLowerCase()).length} employees assigned',
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _openDepartmentDialog(department: department),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
