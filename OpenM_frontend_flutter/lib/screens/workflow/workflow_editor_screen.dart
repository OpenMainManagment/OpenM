import 'package:openm/screens/admin/admin_actions_screen.dart';
import 'package:openm/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization.dart';

class WorkflowEditorScreen extends ConsumerStatefulWidget {
  final String workflowId;
  final String? workflowName;

  const WorkflowEditorScreen({
    super.key,
    required this.workflowId,
    this.workflowName,
  });

  @override
  ConsumerState<WorkflowEditorScreen> createState() =>
      _WorkflowEditorScreenState();
}

class _WorkflowEditorScreenState extends ConsumerState<WorkflowEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _nodeGraph;

  @override
  void initState() {
    super.initState();
    _loadWorkflowData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkflowData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final workflow = await api.getWorkflow(id: widget.workflowId);

      if (mounted) {
        _nameController.text = workflow.name;
        _descriptionController.text = workflow.description;
        _nodeGraph = workflow.nodeGraph;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _saveWorkflow() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      await api.updateWorkflow(
        workflowId: widget.workflowId,
        uniqueName: _nameController.text,
        description: _descriptionController.text,
        workflowStage: 'draft',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.of(context)?.translate('workflowUpdated') ??
                  'Workflow updated successfully',
            ),
          ),
        );

        // Navigate back to workflow list
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.of(context)?.translate('error') ?? 'An error occurred',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.workflowName ??
              l10n?.translate('editWorkflow') ??
              'Edit Workflow',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveWorkflow,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText:
                            l10n?.translate('workflowName') ?? 'Workflow Name',
                        border: OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n?.translate('nameRequired') ??
                              'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText:
                            l10n?.translate('description') ?? 'Description',
                        border: OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.description),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n?.translate('descriptionRequired') ??
                              'Description is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n?.translate('workflowProperties') ??
                                  'Workflow Properties',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.settings,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n?.translate('workflowStage') ??
                                      'Workflow Stage',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _saveWorkflow,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                  l10n?.translate('draft') ?? 'Draft',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: _isLoading
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                ActionNodeEditorScreen(
                                                  initialActionId:
                                                      widget.workflowId,
                                                  initialActionName:
                                                      _nameController.text,
                                                  initialNodeGraph:
                                                      _nodeGraph,
                                                ),
                                          ),
                                        );
                                        // The node editor saves directly via
                                        // the API, so refresh our local copy
                                        // (node graph / node ids) once it's
                                        // closed.
                                        if (mounted) {
                                          _loadWorkflowData();
                                        }
                                      },
                                icon: const Icon(Icons.account_tree_outlined),
                                label: Text(
                                  l10n?.translate('openNodeEditor') ??
                                      'Open Node Editor',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            context.pop();
                          },
                          child: Text(l10n?.translate('cancel') ?? 'Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveWorkflow,
                          icon: const Icon(Icons.save),
                          label: Text(l10n?.translate('save') ?? 'Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}