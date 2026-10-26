import 'package:openm/models/workflow/workflow_model.dart';
import 'package:openm/services/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


final workflowsProvider = FutureProvider<List<Workflow>>((ref) {
  final api = ref.read(apiClientProvider);
  return api.getWorkflows();
});

final workflowProvider = FutureProvider.family<Workflow?, dynamic>((ref, id) {
  final api = ref.read(apiClientProvider);
  return api.getWorkflow(id: id);
});