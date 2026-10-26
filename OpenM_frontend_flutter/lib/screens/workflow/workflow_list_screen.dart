import 'package:openm/screens/admin/admin_actions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/workflow_provider.dart';
import '../../core/localization.dart';
import '../../services/api_client.dart';

class WorkflowListScreen extends ConsumerWidget {
  const WorkflowListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final workflowsAsync = ref.watch(workflowsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n?.translate('workflows') ?? 'Workflows')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/admin/workflows/create');
        },
        child: const Icon(Icons.add),
      ),
      body: workflowsAsync.when(
        data: (workflows) {
          if (workflows.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n?.translate('noWorkflows') ?? 'No workflows found'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      context.push('/admin/workflows/create');
                    },
                    child: Text(
                      l10n?.translate('createWorkflow') ?? 'Create Workflow',
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: workflows.length,
            itemBuilder: (context, index) {
              final workflow = workflows[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(workflow.name),
                  subtitle: Text(workflow.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          context.push('/admin/workflows/${workflow.id}/edit');
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final shouldDelete = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                l10n?.translate('deleteWorkflow') ??
                                    'Delete Workflow',
                              ),
                              content: Text(
                                l10n?.translate('confirmDeleteWorkflow') ??
                                    'Are you sure you want to delete this workflow?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => context.pop(false),
                                  child: Text(
                                    l10n?.translate('cancel') ?? 'Cancel',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.pop(true),
                                  child: Text(
                                    l10n?.translate('delete') ?? 'Delete',
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (shouldDelete == true) {
                            try {
                              final api = ref.read(apiClientProvider);
                              await (api as dynamic).deleteWorkflow(
                                workflowId: workflow.id,
                              );
                              // Refresh the list
                              ref.invalidate(workflowsProvider);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${l10n?.translate('error') ?? 'Error'}: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActionNodeEditorScreen(
                          initialActionId: workflow.id,
                          initialActionName: workflow.name,
                          initialNodeGraph: workflow.nodeGraph,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('${l10n?.translate('error') ?? 'Error'}: $error'),
        ),
      ),
    );
  }
}
