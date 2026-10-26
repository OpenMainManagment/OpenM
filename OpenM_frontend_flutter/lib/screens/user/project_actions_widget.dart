import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';

final projectActionsProvider =
    FutureProvider.family<List<ProjectActionDto>, String>((
      ref,
      projectId,
    ) async {
      return ref.watch(apiClientProvider).getProjectActions();
    });

final projectExecutionsProvider =
    FutureProvider.family<List<ProjectActionExecutionDto>, String>((
      ref,
      projectId,
    ) async {
      return ref.watch(apiClientProvider).getProjectActionExecutions(projectId);
    });

class ProjectActionsWidget extends ConsumerWidget {
  final String projectId;
  final String projectName;

  const ProjectActionsWidget({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final actionsAsync = ref.watch(projectActionsProvider(projectId));

    return actionsAsync.when(
      data: (actions) {
        if (actions.isEmpty) {
          return Center(
            child: Text(
              L10n.of(context)?.translate('noActionsAvailable') ??
                  'No actions available',
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context)?.translate('projectActions') ??
                    'Project Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ...actions.map(
                (action) => ProjectActionWidget(
                  action: action,
                  projectId: projectId,
                  projectName: projectName,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                L10n.of(context)?.translate('executionHistory') ??
                    'Execution History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ExecutionHistoryWidget(projectId: projectId),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('${l10n?.translate('error') ?? 'Error'}: $error')),
    );
  }
}

class ProjectActionWidget extends ConsumerWidget {
  final ProjectActionDto action;
  final String projectId;
  final String projectName;

  const ProjectActionWidget({
    super.key,
    required this.action,
    required this.projectId,
    required this.projectName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.uniqueName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action.description != null) ...[
              const SizedBox(height: 8),
              Text(
                action.description!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(apiClientProvider)
                          .executeProjectAction(
                            projectId: projectId,
                            actionButtonId: action.id,
                            executionInput: {
                              'project_id': projectId,
                              'project_name': projectName,
                              'action_button_id': action.id,
                              'action_button_name': action.uniqueName,
                            },
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n?.translate('actionExecutedSuccessfully') ??
                                  'Action executed successfully',
                            ),
                          ),
                        );
                        // Refresh executions
                        ref.invalidate(projectExecutionsProvider(projectId));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${l10n?.translate('error') ?? 'Error'}: $e',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    L10n.of(context)?.translate('execute') ?? 'Execute',
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(action.uniqueName),
                        content: Text(
                          action.description ??
                              (l10n?.translate('noDescription') ??
                                  'No description'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n?.translate('close') ?? 'Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExecutionHistoryWidget extends ConsumerWidget {
  final String projectId;

  const ExecutionHistoryWidget({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final executionsAsync = ref.watch(projectExecutionsProvider(projectId));

    return executionsAsync.when(
      data: (executions) {
        if (executions.isEmpty) {
          return Text(
            L10n.of(context)?.translate('noExecutions') ?? 'No executions yet',
          );
        }

        return Column(
          children: executions
              .map((execution) => ExecutionHistoryCard(execution: execution))
              .toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('${l10n?.translate('error') ?? 'Error'}: $error')),
    );
  }
}

class ExecutionHistoryCard extends StatelessWidget {
  final ProjectActionExecutionDto execution;

  const ExecutionHistoryCard({super.key, required this.execution});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final statusLabel = switch (execution.executionStatus) {
      'Success' => l10n?.translate('success') ?? 'Success',
      'Failed' => l10n?.translate('failed') ?? 'Failed',
      'Running' => l10n?.translate('running') ?? 'Running',
      'Cancelled' => l10n?.translate('cancelled') ?? 'Cancelled',
      _ => l10n?.translate('pending') ?? 'Pending',
    };

    Color statusColor;
    switch (execution.executionStatus) {
      case 'Success':
        statusColor = Colors.green;
        break;
      case 'Failed':
        statusColor = Colors.red;
        break;
      case 'Running':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        title: Text(execution.actionButtonId),
        subtitle: Text(execution.createdAt.toString()),
        trailing: Text(statusLabel, style: TextStyle(color: statusColor)),
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                l10n?.translate('executionDetails') ?? 'Execution Details',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n?.translate('status') ?? 'Status'}: $statusLabel',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n?.translate('created') ?? 'Created'}: ${execution.createdAt}',
                  ),
                  if (execution.startedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l10n?.translate('started') ?? 'Started'}: ${execution.startedAt}',
                    ),
                  ],
                  if (execution.completedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l10n?.translate('completed') ?? 'Completed'}: ${execution.completedAt}',
                    ),
                  ],
                  if (execution.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l10n?.translate('error') ?? 'Error'}: ${execution.errorMessage}',
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n?.translate('close') ?? 'Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
