import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_shell.dart';

class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      pageName: 'Admin Overviews',
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      onAdd: () {},
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildAdminItem(
              context,
              icon: Icons.person,
              title: 'Employees',
              route: '/admin/employees',
            ),
            _buildAdminItem(
              context,
              icon: Icons.inventory_2,
              title: 'Parts',
              route: '/admin/parts',
            ),
            _buildAdminItem(
              context,
              icon: Icons.folder,
              title: 'Folder Files',
              route: '/admin/folder-files',
            ),
            _buildAdminItem(
              context,
              icon: Icons.apartment,
              title: 'Departments',
              route: '/admin/departments',
            ),
            _buildAdminItem(
              context,
              icon: Icons.check_circle,
              title: 'Todos',
              route: '/admin/todos',
            ),
            _buildAdminItem(
              context,
              icon: Icons.settings,
              title: 'Actions',
              route: '/admin/actions',
            ),
            _buildAdminItem(
              context,
              icon: Icons.sync_alt,
              title: 'Workflows',
              route: '/admin/workflows',
            ),
            _buildAdminItem(
              context,
              icon: Icons.workspace_premium,
              title: 'Projects',
              route: '/admin/projects',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminItem(BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: AppColors.primaryDark,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}