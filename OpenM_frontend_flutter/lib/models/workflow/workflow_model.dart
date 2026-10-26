class Workflow {
  final String id;
  final String name;
  final String description;
  final String companyId;
  final String workflowStage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String>? nodeIds;
  final String? nodeGraph;

  const Workflow({
    required this.id,
    required this.name,
    required this.description,
    required this.companyId,
    required this.workflowStage,
    required this.createdAt,
    required this.updatedAt,
    this.nodeIds,
    this.nodeGraph,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      companyId: json['company_id'] as String? ??
          json['organization_id'] as String? ??
          json['companyId'] as String,
      workflowStage:
          json['workflow_stage'] as String? ?? json['workflowStage'] as String,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? json['createdAt'] as String,
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['updatedAt'] as String,
      ),
      nodeIds: (json['node_ids'] as List<dynamic>?)
          ?.map((item) => item as String)
          .toList(),
      nodeGraph: json['node_graph'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'company_id': companyId,
      'workflow_stage': workflowStage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'node_ids': nodeIds,
      'node_graph': nodeGraph,
    };
  }
}

class WorkflowNode {
  final String id;
  final String name;
  final String type;
  final String workflowId;
  final Map<String, dynamic> configuration;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final int? positionX;
  final int? positionY;

  const WorkflowNode({
    required this.id,
    required this.name,
    required this.type,
    required this.workflowId,
    required this.configuration,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.positionX,
    this.positionY,
  });

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      workflowId:
          json['workflow_id'] as String? ?? json['workflowId'] as String,
      configuration:
          (json['configuration'] as Map<String, dynamic>?) ??
          <String, dynamic>{},
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? json['createdAt'] as String,
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['updatedAt'] as String,
      ),
      description: json['description'] as String?,
      positionX: json['position_x'] as int? ?? json['positionX'] as int?,
      positionY: json['position_y'] as int? ?? json['positionY'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'workflow_id': workflowId,
      'configuration': configuration,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'description': description,
      'position_x': positionX,
      'position_y': positionY,
    };
  }
}
