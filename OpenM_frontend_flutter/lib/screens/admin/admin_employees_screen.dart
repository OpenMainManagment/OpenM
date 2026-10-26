import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminEmployeesScreen extends ConsumerStatefulWidget {
  const AdminEmployeesScreen({super.key});

  @override
  ConsumerState<AdminEmployeesScreen> createState() =>
      _AdminEmployeesScreenState();
}

class _AdminEmployeesScreenState extends ConsumerState<AdminEmployeesScreen> {
  static const List<MapEntry<String, String>> _rolePermissionOptions = [
    MapEntry<String, String>('employees.add', 'Add Employees'),
    MapEntry<String, String>('employees.edit', 'Edit Employees'),
    MapEntry<String, String>('employees.delete', 'Delete Employees'),
    MapEntry<String, String>('parts.add', 'Add Parts'),
    MapEntry<String, String>('parts.edit', 'Edit Parts'),
    MapEntry<String, String>('parts.delete', 'Delete Parts'),
    MapEntry<String, String>('projects.add', 'Add Projects'),
    MapEntry<String, String>('projects.edit', 'Edit Projects'),
    MapEntry<String, String>('folders.add', 'Add Folders'),
    MapEntry<String, String>('files.upload', 'Upload Files'),
  ];

  List<EmployeeDto> _employees = const [];
  List<CompanyDto> _companies = const [];
  bool _loading = true;
  String? _error;

  String _permissionLabel(String key) {
    for (final option in _rolePermissionOptions) {
      if (option.key == key) {
        return option.value;
      }
    }
    return key;
  }

  List<String> _orderedPermissionKeys(Set<String> selectedPermissions) {
    final optionOrder = _rolePermissionOptions.map((item) => item.key).toList();
    final known = <String>[];
    final unknown = <String>[];
    for (final key in selectedPermissions) {
      if (optionOrder.contains(key)) {
        known.add(key);
      } else {
        unknown.add(key);
      }
    }
    known.sort(
      (a, b) => optionOrder.indexOf(a).compareTo(optionOrder.indexOf(b)),
    );
    unknown.sort();
    return [...known, ...unknown];
  }

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
      final employees = await api.adminEmployees();
      final companies = await api.companies();
      if (!mounted) {
        return;
      }
      setState(() {
        _employees = employees;
        _companies = companies;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data is Map<String, dynamic>
          ? (error.response?.data['detail'] as String?)
          : null;
      setState(() {
        _error = detail ?? 'Only Admin users can open this screen.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load employees.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addEmployeeDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: 'User');
    final selectedCompanyId = _companies.isNotEmpty
        ? _companies.first.id
        : null;
    final selectedCompanyName = _companies.isNotEmpty
        ? _companies.first.uniqueName
        : 'No company';
    List<CompanyRoleDto> roles = selectedCompanyId == null
        ? const []
        : await ref.read(apiClientProvider).companyRoles(selectedCompanyId);
    String? selectedRole = roles.any((role) => role.name == 'User')
        ? 'User'
        : (roles.isNotEmpty ? roles.first.name : null);
    if (selectedRole != null &&
        !roles.any((role) => role.name == selectedRole)) {
      selectedRole = null;
    }
    if (selectedRole != null) {
      roleCtrl.text = selectedRole;
    }
    final departments = selectedCompanyId == null
        ? const <DepartmentDto>[]
        : await ref.read(apiClientProvider).departments(selectedCompanyId);
    String? selectedDepartment;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Employee'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Company: $selectedCompanyName',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First Name'),
              ),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last Name'),
              ),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: loginCtrl,
                decoration: const InputDecoration(labelText: 'Login Name'),
              ),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: roles
                    .map(
                      (role) => DropdownMenuItem<String>(
                        value: role.name,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  selectedRole = value;
                  if (value != null) {
                    roleCtrl.text = value;
                  }
                },
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: selectedDepartment,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No department'),
                  ),
                  ...departments.map(
                    (department) => DropdownMenuItem<String?>(
                      value: department.name,
                      child: Text(department.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  selectedDepartment = value;
                },
                decoration: const InputDecoration(labelText: 'Department'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(apiClientProvider)
                  .createEmployee(
                    firstName: firstCtrl.text.trim(),
                    lastName: lastCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    loginName: loginCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                    role: (selectedRole ?? roleCtrl.text.trim()).isEmpty
                        ? 'User'
                        : (selectedRole ?? roleCtrl.text.trim()),
                    department: selectedDepartment,
                    companyId: selectedCompanyId,
                  );
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editEmployeeDialog(EmployeeDto employee) async {
    final firstCtrl = TextEditingController(text: employee.firstName);
    final lastCtrl = TextEditingController(text: employee.lastName);
    final emailCtrl = TextEditingController(text: employee.email);
    final roleCtrl = TextEditingController(text: employee.role ?? 'User');
    final selectedCompanyId = _companies.isNotEmpty
        ? _companies.first.id
        : employee.companyId;
    final selectedCompanyName = _companies.isNotEmpty
        ? _companies.first.uniqueName
        : 'No company';
    List<CompanyRoleDto> roles = selectedCompanyId == null
        ? const []
        : await ref.read(apiClientProvider).companyRoles(selectedCompanyId);
    String? selectedRole = employee.role;
    if (selectedRole != null &&
        !roles.any((role) => role.name == selectedRole)) {
      selectedRole = roles.isNotEmpty ? roles.first.name : null;
    }
    if (selectedRole != null && selectedRole.isNotEmpty) {
      roleCtrl.text = selectedRole;
    }
    final departments = selectedCompanyId == null
        ? const <DepartmentDto>[]
        : await ref.read(apiClientProvider).departments(selectedCompanyId);
    String? selectedDepartment = employee.department;
    if (selectedDepartment != null &&
        selectedDepartment.isNotEmpty &&
        !departments.any(
          (department) => department.name == selectedDepartment,
        )) {
      selectedDepartment = null;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Employee'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Company: $selectedCompanyName',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First Name'),
              ),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last Name'),
              ),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: roles
                    .map(
                      (role) => DropdownMenuItem<String>(
                        value: role.name,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  selectedRole = value;
                  if (value != null) {
                    roleCtrl.text = value;
                  }
                },
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: selectedDepartment,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No department'),
                  ),
                  ...departments.map(
                    (department) => DropdownMenuItem<String?>(
                      value: department.name,
                      child: Text(department.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  selectedDepartment = value;
                },
                decoration: const InputDecoration(labelText: 'Department'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(apiClientProvider)
                  .updateEmployee(
                    employeeId: employee.id,
                    firstName: firstCtrl.text.trim(),
                    lastName: lastCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    role: (selectedRole ?? roleCtrl.text.trim()).isEmpty
                        ? 'User'
                        : (selectedRole ?? roleCtrl.text.trim()),
                    department: selectedDepartment,
                    companyId: selectedCompanyId,
                  );
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _roleEditorDialog() async {
    if (_companies.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a company first.')));
      return;
    }

    final roleNameCtrl = TextEditingController();
    final selectedPermissions = <String>{};
    final selectedCompanyId = _companies.first.id;
    final selectedCompanyName = _companies.first.uniqueName;
    List<CompanyRoleDto> roles = await ref
        .read(apiClientProvider)
        .companyRoles(selectedCompanyId);

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Company Role Editor'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Company: $selectedCompanyName',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roleNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'New role name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final roleName = roleNameCtrl.text.trim();
                        if (roleName.isEmpty) {
                          return;
                        }
                        await ref
                            .read(apiClientProvider)
                            .createCompanyRole(
                              companyId: selectedCompanyId,
                              name: roleName,
                              permissions: _orderedPermissionKeys(
                                selectedPermissions,
                              ),
                            );
                        roleNameCtrl.clear();
                        selectedPermissions.clear();
                        roles = await ref
                            .read(apiClientProvider)
                            .companyRoles(selectedCompanyId);
                        setDialogState(() {});
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rights for new role',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: ListView(
                    shrinkWrap: true,
                    children: _rolePermissionOptions
                        .map(
                          (option) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedPermissions.contains(option.key),
                            onChanged: (checked) {
                              if (checked ?? false) {
                                selectedPermissions.add(option.key);
                              } else {
                                selectedPermissions.remove(option.key);
                              }
                              setDialogState(() {});
                            },
                            title: Text(option.value),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(height: 24),
                SizedBox(
                  height: 260,
                  child: ListView(
                    shrinkWrap: true,
                    children: roles
                        .map(
                          (role) => ListTile(
                            dense: true,
                            title: Text(role.name),
                            subtitle: Text(
                              role.permissions.isEmpty
                                  ? 'No rights selected'
                                  : role.permissions
                                        .map(_permissionLabel)
                                        .join(', '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final editRoleNameCtrl =
                                        TextEditingController(text: role.name);
                                    final editPermissions = role.permissions
                                        .toSet();

                                    await showDialog<void>(
                                      context: context,
                                      builder: (context) => StatefulBuilder(
                                        builder:
                                            (
                                              context,
                                              setEditDialogState,
                                            ) => AlertDialog(
                                              title: const Text(
                                                'Edit Role Rights',
                                              ),
                                              content: SizedBox(
                                                width: 520,
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextField(
                                                        controller:
                                                            editRoleNameCtrl,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  'Role name',
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      ..._rolePermissionOptions.map(
                                                        (
                                                          option,
                                                        ) => CheckboxListTile(
                                                          dense: true,
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                          value: editPermissions
                                                              .contains(
                                                                option.key,
                                                              ),
                                                          onChanged: (checked) {
                                                            if (checked ??
                                                                false) {
                                                              editPermissions
                                                                  .add(
                                                                    option.key,
                                                                  );
                                                            } else {
                                                              editPermissions
                                                                  .remove(
                                                                    option.key,
                                                                  );
                                                            }
                                                            setEditDialogState(
                                                              () {},
                                                            );
                                                          },
                                                          title: Text(
                                                            option.value,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    final editedName =
                                                        editRoleNameCtrl.text
                                                            .trim();
                                                    if (editedName.isEmpty) {
                                                      return;
                                                    }
                                                    await ref
                                                        .read(apiClientProvider)
                                                        .updateCompanyRole(
                                                          roleId: role.id,
                                                          name: editedName,
                                                          permissions:
                                                              _orderedPermissionKeys(
                                                                editPermissions,
                                                              ),
                                                        );
                                                    if (context.mounted) {
                                                      Navigator.pop(context);
                                                    }
                                                  },
                                                  child: const Text('Save'),
                                                ),
                                              ],
                                            ),
                                      ),
                                    );

                                    roles = await ref
                                        .read(apiClientProvider)
                                        .companyRoles(selectedCompanyId);
                                    setDialogState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await ref
                                        .read(apiClientProvider)
                                        .deleteCompanyRole(role.id);
                                    roles = await ref
                                        .read(apiClientProvider)
                                        .companyRoles(selectedCompanyId);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );

    await _load();
  }

  Future<void> _deleteEmployeeDialog(EmployeeDto employee) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Delete ${employee.firstName} ${employee.lastName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiClientProvider).deleteEmployee(employee.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Admin Employees',
      onAdd: _addEmployeeDialog,
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _roleEditorDialog,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Role Editor'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _employees.length,
                      itemBuilder: (_, index) {
                        final e = _employees[index];
                        return Card(
                          child: ListTile(
                            title: Text('${e.firstName} ${e.lastName}'),
                            subtitle: Text(
                              '${e.email} | ${e.role ?? 'User'} | ${e.department ?? '-'}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editEmployeeDialog(e);
                                } else if (value == 'delete') {
                                  _deleteEmployeeDialog(e);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
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
