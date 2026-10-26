import 'workflow_node.dart';
import 'workflow_connection.dart';

class WorkflowGraph {
  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;

  WorkflowGraph({required this.nodes, required this.connections});

  factory WorkflowGraph.fromJson(Map<String, dynamic> json) {
    return WorkflowGraph(
      nodes: (json['nodes'] as List<dynamic>? ?? const [])
          .map((item) => WorkflowNode.fromJson(item as Map<String, dynamic>))
          .toList(),
      connections: (json['connections'] as List<dynamic>? ?? const [])
          .map(
            (item) => WorkflowConnection.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'connections': connections
          .map((connection) => connection.toJson())
          .toList(),
    };
  }
}
