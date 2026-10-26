import 'package:go_router/go_router.dart';

import 'workflow_list_screen.dart';
import 'workflow_creation_screen.dart';
import 'workflow_editor_screen.dart';

final workflowRouter = GoRoute(
  path: '/workflows',
  name: 'workflows',
  builder: (context, state) => const WorkflowListScreen(),
  routes: [
    GoRoute(
      path: 'create',
      name: 'workflowCreate',
      builder: (context, state) => const WorkflowCreationScreen(),
    ),
    GoRoute(
      path: 'edit/:workflowId',
      name: 'workflowEdit',
      builder: (context, state) {
        final workflowId = state.pathParameters['workflowId']!;
        final workflowName = state.uri.queryParameters['name'] ?? 'Workflow';
        return WorkflowCreationScreen(
          workflowId: workflowId,
          workflowName: workflowName,
        );
      },
    ),
    GoRoute(
      path: 'view/:workflowId',
      name: 'workflowView',
      builder: (context, state) {
        final workflowId = state.pathParameters['workflowId']!;
        return WorkflowEditorScreen(
          workflowId: workflowId,
          workflowName: state.uri.queryParameters['name'] ?? 'Workflow',
        );
      },
    ),
  ],
);
