import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import '../../models/workflow/workflow_graph.dart';
import '../../models/workflow/workflow_node.dart';
import '../../models/workflow/workflow_connection.dart';

class WorkflowService {
  static final WorkflowService _instance = WorkflowService._internal();

  factory WorkflowService() {
    return _instance;
  }

  WorkflowService._internal();

  // Simulate loading a workflow from backend
  Future<WorkflowGraph> loadWorkflow(String workflowId) async {
    // In a real implementation, this would make an API call to fetch the workflow
    // For now, we'll return a default workflow or mock data

    // This is where you'd normally fetch from a backend
    // Example:
    // final response = await http.get(Uri.parse('$baseUrl/workflows/$workflowId'));
    // final data = json.decode(response.body);

    // Return a default empty workflow for now
    return WorkflowGraph(nodes: [], connections: []);
  }

  // Simulate saving a workflow to backend
  Future<void> saveWorkflow(String workflowId, WorkflowGraph graph) async {
    // In a real implementation, this would make an API call to save the workflow
    // Example:
    // final response = await http.post(
    //   Uri.parse('$baseUrl/workflows/$workflowId'),
    //   body: json.encode(graph.toJson()),
    // );

    // For now, we'll just print to console
    if (kDebugMode) {
      print('Saving workflow $workflowId');
      print(jsonEncode(graph.toJson()));
    }
  }

  // Create a new workflow node with default properties
  WorkflowNode createDefaultNode(
    String nodeId,
    String nodeName,
    String nodeType,
  ) {
    return WorkflowNode(
      id: nodeId,
      name: nodeName,
      type: nodeType,
      position: const Offset(100, 100),
      size: const Size(200, 100),
      inputs: [
        NodePort(
          id: '${nodeId}_input',
          name: 'input',
          type: 'trigger',
          multiConnections: false,
        ),
      ],
      outputs: [
        NodePort(
          id: '${nodeId}_output',
          name: 'output',
          type: 'result',
          multiConnections: true,
        ),
      ],
      data: {},
    );
  }

  // Create a connection between nodes
  WorkflowConnection createConnection(
    String connectionId,
    String sourceNodeId,
    String sourcePortId,
    String targetNodeId,
    String targetPortId,
  ) {
    return WorkflowConnection(
      id: connectionId,
      sourceNodeId: sourceNodeId,
      sourcePortId: sourcePortId,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
    );
  }
}
