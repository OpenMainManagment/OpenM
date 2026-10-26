import 'package:openm/screens/admin/admin_projects_screen.dart';
import 'package:openm/screens/workflow/workflow_creation_screen.dart';
import 'package:openm/screens/workflow/workflow_editor_screen.dart';
import 'package:openm/screens/workflow/workflow_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/user/companies_screen.dart';
import '../screens/user/company_projects_screen.dart';
import '../screens/user/company_customers_screen.dart';
import '../screens/user/project_note_screen.dart';
import '../screens/user/folder_files_screen.dart';
import '../screens/user/login_screen.dart';
import '../screens/user/project_folders_screen.dart';
import '../screens/user/project_order_screen.dart';
import '../screens/user/offer_for_customer_screen.dart';
import '../screens/user/project_parts_status_screen.dart';
import '../screens/user/project_part_decisions_screen.dart';
import '../screens/user/project_detail_screen.dart';
import '../screens/user/project_sub_gantt_screen.dart';
import '../screens/user/project_overview_screen.dart';
import '../screens/user/kanboard_screen.dart';
import '../screens/user/calendar_screen.dart';
import '../screens/user/ticket_screen.dart';

import '../screens/admin/admin_screen.dart';
import '../screens/admin/admin_manufacturers_screen.dart';
import '../screens/admin/admin_server_settings_screen.dart';
import '../screens/user/mail_settings_screen.dart';
import '../screens/user/profile_editor_screen.dart';
import '../screens/admin/admin_employees_screen.dart';
import '../screens/admin/admin_parts_screen.dart';
import '../screens/admin/admin_part_create_screen.dart';
import '../screens/admin/admin_part_edit_screen.dart';
import '../screens/admin/admin_folder_files_screen.dart';
import '../screens/admin/admin_departments_screen_fixed.dart';
import '../screens/admin/admin_todo_edit_screen.dart';
import '../screens/admin/admin_actions_screen.dart';
import '../screens/admin/admin_project_gantt_templates_screen.dart';
import '../screens/management_dashboard/dashboard_screen.dart';
import '../services/auth_state.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoginRoute = state.matchedLocation == '/login';
      final isRootRoute = state.matchedLocation == '/';
      if (!auth.isAuthenticated && !isLoginRoute && !isRootRoute) {
        return '/login';
      }
      if (auth.isAuthenticated && (isLoginRoute || isRootRoute)) {
        return '/companies';
      }
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.matchedLocation}'),
      ),
    ),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/companies', builder: (_, _) => const CompaniesScreen()),
      GoRoute(
        path: '/projectsoverview',
        builder: (_, _) => const ProjectOverviewScreen(),
      ),
      GoRoute(path: '/kanboard', builder: (_, _) => const KanboardScreen()),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/ticket', builder: (_, _) => const TicketScreen()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileEditorScreen()),
      GoRoute(
        path: '/management-dashboard',
        builder: (_, _) => const ManagementDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/employees',
        builder: (_, _) => const AdminEmployeesScreen(),
      ),
      GoRoute(
        path: '/admin/parts',
        builder: (_, _) => const AdminPartsScreen(),
      ),
      GoRoute(
        path: '/admin/parts/new',
        builder: (_, _) => const AdminPartCreateScreen(),
      ),
      GoRoute(
        path: '/admin/parts/:partId/edit',
        builder: (_, state) =>
            AdminPartEditScreen(partId: state.pathParameters['partId']!),
      ),
      GoRoute(
        path: '/admin/folder-files',
        builder: (_, _) => const AdminFolderFilesScreen(),
      ),
      GoRoute(
        path: '/admin/departments',
        builder: (_, _) => const AdminDepartmentsScreen(),
      ),
      GoRoute(
        path: '/admin/todos',
        builder: (_, _) => const AdminTodoEditScreen(),
      ),
      GoRoute(
        path: '/admin/actions',
        builder: (_, _) => const ActionNodeEditorScreen(),
      ),
      GoRoute(
        path: '/companies/:companyId/projects',
        builder: (_, state) => CompanyProjectsScreen(
          companyId: state.pathParameters['companyId']!,
          companyName: state.uri.queryParameters['name'] ?? 'Company',
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/projects/new-note',
        builder: (_, state) => ProjectNoteScreen(
          companyId: state.pathParameters['companyId']!,
          companyName: state.uri.queryParameters['name'] ?? 'Company',
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/customers',
        builder: (_, state) => CompanyCustomersScreen(
          companyId: state.pathParameters['companyId']!,
          companyName: state.uri.queryParameters['name'] ?? 'Company',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/folders',
        builder: (_, state) => ProjectFoldersScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/details',
        builder: (_, state) => ProjectDetailScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
          companyId: state.uri.queryParameters['companyId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/gantt/:stepId',
        builder: (_, state) => ProjectSubGanttScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
          stepId: state.pathParameters['stepId']!,
          stepTitle: state.uri.queryParameters['stepTitle'] ?? 'Step',
        ),
      ),
      GoRoute(
        path: '/companies/:companyId/projects/:projectId/notes',
        builder: (_, state) => ProjectNoteScreen(
          companyId: state.pathParameters['companyId']!,
          companyName: state.uri.queryParameters['name'] ?? 'Company',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/order',
        builder: (_, state) => ProjectOrderScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/offer',
        builder: (_, state) => OfferForCustomerScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
          documentId: state.uri.queryParameters['documentId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/parts-status',
        builder: (_, state) => ProjectPartsStatusScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/order-parts',
        builder: (_, state) => ProjectPartDecisionsScreen(
          projectId: state.pathParameters['projectId']!,
          projectName: state.uri.queryParameters['name'] ?? 'Project',
        ),
      ),
      GoRoute(
        path: '/folders/:folderId/files',
        builder: (_, state) => FolderFilesScreen(
          folderId: state.pathParameters['folderId']!,
          folderName: state.uri.queryParameters['name'] ?? 'Folder',
          projectId: state.uri.queryParameters['projectId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/admin/workflows',
        builder: (_, _) => const WorkflowListScreen(),
      ),
      GoRoute(
        path: '/admin/workflows/create',
        builder: (_, _) => const WorkflowCreationScreen(),
      ),
      GoRoute(
        path: '/admin/workflows/:workflowId/edit',
        builder: (_, state) => WorkflowEditorScreen(
          workflowId: state.pathParameters['workflowId']!,
          workflowName: state.uri.queryParameters['name'] ?? 'Workflow',
        ),
      ),
      GoRoute(
        path: '/workflows',
        builder: (_, _) => const WorkflowListScreen(),
      ),
      GoRoute(
        path: '/workflows/new',
        builder: (_, _) => const WorkflowCreationScreen(),
      ),
      GoRoute(
        path: '/workflows/:workflowId',
        builder: (_, state) => WorkflowEditorScreen(
          workflowId: state.pathParameters['workflowId']!,
        ),
      ),
      GoRoute(
        path: '/admin/projects',
        builder: (_, _) => const AdminProjectsScreen(),
      ),
      GoRoute(
        path: '/admin/project-gantt-templates',
        builder: (_, _) => const AdminProjectGanttTemplatesScreen(),
      ),
      GoRoute(
        path: '/admin/server-settings',
        builder: (_, _) => const AdminServerSettingsScreen(),
      ),
      GoRoute(
        path: '/admin/manufacturers',
        builder: (_, _) => const AdminManufacturersScreen(),
      ),
      GoRoute(
        path: '/account/mail-settings',
        builder: (_, _) => const MailSettingsScreen(),
      ),


      GoRoute(
        path: '/dashboard/overview',
        builder: (_, _) => const ManagementDashboardScreen(),
      ),
    ],
  );
});