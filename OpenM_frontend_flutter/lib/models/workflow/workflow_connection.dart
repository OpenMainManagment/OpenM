class WorkflowConnection {
  final String id;
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;

  WorkflowConnection({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
  });

  factory WorkflowConnection.fromJson(Map<String, dynamic> json) {
    return WorkflowConnection(
      id: json['id'] as String,
      sourceNodeId: json['sourceNodeId'] as String,
      sourcePortId: json['sourcePortId'] as String,
      targetNodeId: json['targetNodeId'] as String,
      targetPortId: json['targetPortId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceNodeId': sourceNodeId,
      'sourcePortId': sourcePortId,
      'targetNodeId': targetNodeId,
      'targetPortId': targetPortId,
    };
  }
}
