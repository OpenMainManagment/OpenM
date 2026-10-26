import 'package:flutter/material.dart';

class WorkflowNode {
  final String id;
  final String name;
  final String type;
  final Offset position;
  final Size size;
  final List<NodePort> inputs;
  final List<NodePort> outputs;
  final Map<String, dynamic> data;

  WorkflowNode({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    required this.size,
    required this.inputs,
    required this.outputs,
    required this.data,
  });

  WorkflowNode copyWith({
    String? id,
    String? name,
    String? type,
    Offset? position,
    Size? size,
    List<NodePort>? inputs,
    List<NodePort>? outputs,
    Map<String, dynamic>? data,
  }) {
    return WorkflowNode(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      position: position ?? this.position,
      size: size ?? this.size,
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      data: data ?? this.data,
    );
  }

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      position: Offset(
        (json['position'] as Map<String, dynamic>)['x'] as double,
        (json['position'] as Map<String, dynamic>)['y'] as double,
      ),
      size: Size(
        (json['size'] as Map<String, dynamic>)['width'] as double,
        (json['size'] as Map<String, dynamic>)['height'] as double,
      ),
      inputs: (json['inputs'] as List<dynamic>? ?? const [])
          .map((item) => NodePort.fromJson(item as Map<String, dynamic>))
          .toList(),
      outputs: (json['outputs'] as List<dynamic>? ?? const [])
          .map((item) => NodePort.fromJson(item as Map<String, dynamic>))
          .toList(),
      data: json['data'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'position': {'x': position.dx, 'y': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'inputs': inputs.map((input) => input.toJson()).toList(),
      'outputs': outputs.map((output) => output.toJson()).toList(),
      'data': data,
    };
  }
}

class NodePort {
  final String id;
  final String name;
  final String type;
  final bool multiConnections;

  NodePort({
    required this.id,
    required this.name,
    required this.type,
    required this.multiConnections,
  });

  factory NodePort.fromJson(Map<String, dynamic> json) {
    return NodePort(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      multiConnections: json['multiConnections'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'multiConnections': multiConnections,
    };
  }
}
