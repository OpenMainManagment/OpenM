import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization.dart';
import '../../services/api_client.dart';

class WorkflowCreateScreen extends ConsumerStatefulWidget {
  const WorkflowCreateScreen({super.key});

  @override
  ConsumerState<WorkflowCreateScreen> createState() =>
      _WorkflowCreateScreenState();
}

class _WorkflowCreateScreenState extends ConsumerState<WorkflowCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createWorkflow() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      await api.createWorkflow(
        uniqueName: _nameController.text,
        description: _descriptionController.text,
        workflowStage: 'draft',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.of(context)?.translate('workflowCreated') ??
                  'Workflow created successfully',
            ),
          ),
        );

        // Navigate back to workflow list
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.translate('createWorkflow') ?? 'Create Workflow'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
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
                  labelText: l10n?.translate('workflowName') ?? 'Workflow Name',
                  border: OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.work_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n?.translate('enterWorkflowName') ??
                        'Please enter a workflow name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText:
                      l10n?.translate('workflowDescription') ??
                      'Workflow Description',
                  border: OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n?.translate('enterWorkflowDescription') ??
                        'Please enter a workflow description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    child: Text(l10n?.translate('cancel') ?? 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _createWorkflow,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(l10n?.translate('create') ?? 'Create'),
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
