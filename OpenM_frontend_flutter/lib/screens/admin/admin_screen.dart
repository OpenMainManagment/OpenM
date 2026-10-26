import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../widgets/app_shell.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      pageName: 'Admin',
      onAdd: () {},
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Employees'),
                subtitle: const Text('Manage employees and roles'),
                onTap: () => context.push('/admin/employees'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.precision_manufacturing_outlined),
                title: const Text('Parts'),
                subtitle: const Text('Manage parts administration pages'),
                onTap: () => context.push('/admin/parts'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Folder Structure & Files'),
                subtitle: const Text('Manage folders and files settings'),
                onTap: () => context.push('/admin/folder-files'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rtl_outlined),
                title: const Text('ToDos'),
                subtitle: const Text(
                  'Manage timed actions for companies and projects',
                ),
                onTap: () => context.push('/admin/todos'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: const Text('Departments'),
                subtitle: const Text(
                  'Manage departments, roles and basic folders',
                ),
                onTap: () => context.push('/admin/departments'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.import_contacts_outlined),
                title: const Text('Project Actions'),
                subtitle: const Text(
                  'Manage project action buttons and workflow nodes',
                ),
                onTap: () => context.push('/admin/actions'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Workflows'),
                subtitle: const Text('Manage workflow definitions'),
                onTap: () => context.push('/admin/workflows'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.list_outlined),
                title: const Text('Project Overview'),
                subtitle: const Text('View all projects'),
                onTap: () => context.push('/admin/projects'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.timeline_outlined),
                title: const Text('Gantt Templates'),
                subtitle: const Text('Edit default project gantt steps'),
                onTap: () => context.push('/admin/project-gantt-templates'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server Settings'),
                subtitle: const Text(
                  'Email server (SMTP) and AI server (Ollama / LM Studio) presets',
                ),
                onTap: () => context.push('/admin/server-settings'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.factory_outlined),
                title: const Text('Manufacturers'),
                subtitle: const Text(
                  'Companies and websites parts can be ordered from',
                ),
                onTap: () => context.push('/admin/manufacturers'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
