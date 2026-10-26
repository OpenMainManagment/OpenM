import 'dart:convert';

import 'package:openm/services/auth_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:node_editor/node_editor.dart';
import 'package:node_editor/src/inherit.dart';
import 'package:node_editor/src/node_widget.dart';

import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import 'workflow_node_editor_utils.dart';

final projectActionsProvider = FutureProvider<List<ProjectActionDto>>((
  ref,
) async {
  return ref.watch(apiClientProvider).getProjectActions();
});

final workflowNodesProvider = FutureProvider<List<WorkflowNodeDto>>((
  ref,
) async {
  return ref.watch(apiClientProvider).getWorkflowNodes();
});

class AdminActionsScreen extends ConsumerWidget {
  const AdminActionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context)?.translate('actions') ?? 'Actions'),
          bottom: TabBar(
            tabs: [
              Tab(
                text:
                    L10n.of(context)?.translate('projectActions') ??
                    'Project Actions',
              ),
              Tab(
                text:
                    L10n.of(context)?.translate('workflowNodes') ??
                    'Workflow Nodes',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ProjectActionsTab(), WorkflowNodesTab()],
        ),
      ),
    );
  }
}

class ProjectActionsTab extends ConsumerWidget {
  const ProjectActionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final buttonsAsync = ref.watch(projectActionsProvider);

    return buttonsAsync.when(
      data: (buttons) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const ProjectActionDialog(),
                  );
                },
                child: Text(
                  L10n.of(context)?.translate('createNew') ?? 'Create New',
                ),
              ),
            ),
            ...buttons.map(
              (button) => ProjectActionCard(
                action: button,
                onEdit: () {
                  showDialog(
                    context: context,
                    builder: (context) => ProjectActionDialog(action: button),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('${l10n?.translate('error') ?? 'Error'}: $error')),
    );
  }
}

class ProjectActionCard extends StatelessWidget {
  final ProjectActionDto action;
  final VoidCallback onEdit;

  const ProjectActionCard({
    super.key,
    required this.action,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(action.uniqueName),
        subtitle: Text(action.description ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                // TODO: Implement delete
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectActionDialog extends ConsumerStatefulWidget {
  final ProjectActionDto? action;

  const ProjectActionDialog({super.key, this.action});

  @override
  ConsumerState<ProjectActionDialog> createState() =>
      _ProjectActionDialogState();
}

class _ProjectActionDialogState extends ConsumerState<ProjectActionDialog> {
  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController workflowStageController;
  String? _draftNodeGraph;
  bool isActive = true;
  List<DepartmentDto> _departments = const [];
  bool _departmentsLoading = true;
  String? _departmentsError;
  final Set<String> _selectedDepartmentIds = {};

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.action?.uniqueName ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.action?.description ?? '',
    );
    workflowStageController = TextEditingController(
      text: widget.action?.workflowStage ?? '',
    );
    isActive = widget.action?.isActive ?? true;
    _draftNodeGraph = widget.action?.nodeGraph;
    _selectedDepartmentIds.addAll(
      widget.action?.departments.map((department) => department.departmentId) ??
          [],
    );
    _loadDepartments();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    workflowStageController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      setState(() {
        _departmentsLoading = true;
        _departmentsError = null;
      });

      final authState = ref.read(authStateProvider);
      String? companyId = authState.companyId;

      if (companyId == null || companyId.isEmpty) {
        final companies = await ref.read(apiClientProvider).companies();
        companyId = companies.isNotEmpty ? companies.first.id : null;
      }

      if (companyId == null || companyId.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _departments = const [];
          _departmentsLoading = false;
          _departmentsError = 'No company available for departments.';
        });
        return;
      }

      final departments = await ref
          .read(apiClientProvider)
          .departments(companyId);

      if (!mounted) {
        return;
      }

      setState(() {
        _departments = departments;
        _departmentsLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _departments = const [];
        _departmentsLoading = false;
        _departmentsError = 'Failed to load departments: $e';
      });
    }
  }

  Future<void> _saveProjectAction() async {
    final api = ref.read(apiClientProvider);
    final uniqueName = nameController.text.trim();
    final description = descriptionController.text.trim();
    final workflowStage = workflowStageController.text.trim();

    if (widget.action == null) {
      await api.createProjectAction(
        uniqueName: uniqueName,
        description: description.isEmpty ? null : description,
        nodeGraph: _draftNodeGraph,
        workflowStage: workflowStage.isEmpty ? null : workflowStage,
        isActive: isActive,
        departmentIds: _selectedDepartmentIds.toList(),
      );
    } else {
      await api.updateProjectAction(
        buttonId: widget.action!.id,
        uniqueName: uniqueName,
        description: description.isEmpty ? null : description,
        nodeGraph: _draftNodeGraph,
        workflowStage: workflowStage.isEmpty ? null : workflowStage,
        isActive: isActive,
        departmentIds: _selectedDepartmentIds.toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return AlertDialog(
      title: Text(
        widget.action == null
            ? l10n?.translate('createActionButton') ?? 'Create Project Action'
            : l10n?.translate('editActionButton') ?? 'Edit Project Action',
      ),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: l10n?.translate('name') ?? 'Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: l10n?.translate('description') ?? 'Description',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: workflowStageController,
              decoration: InputDecoration(
                labelText: l10n?.translate('workflowStage') ?? 'Workflow Stage',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n?.translate('projectActionDepartments') ?? 'Departments',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_departmentsLoading)
              const LinearProgressIndicator()
            else if (_departmentsError != null)
              Text(
                _departmentsError ?? '',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_departments.isEmpty)
              Text(
                l10n?.translate('noDepartmentsAvailable') ??
                    'No departments available',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _departments.map((department) {
                  return FilterChip(
                    label: Text(department.name),
                    selected: _selectedDepartmentIds.contains(department.id),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDepartmentIds.add(department.id);
                        } else {
                          _selectedDepartmentIds.remove(department.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: Text(l10n?.translate('active') ?? 'Active'),
              value: isActive,
              onChanged: (value) {
                setState(() {
                  isActive = value ?? true;
                });
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final nodeGraph = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => ActionNodeEditorScreen(
                        initialActionId: widget.action?.id,
                        initialActionName: widget.action?.uniqueName,
                        initialNodeGraph:
                            _draftNodeGraph ?? widget.action?.nodeGraph,
                      ),
                    ),
                  );
                  if (!mounted || nodeGraph == null || nodeGraph.isEmpty) {
                    return;
                  }
                  setState(() {
                    _draftNodeGraph = nodeGraph;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Node graph attached to this action.'),
                    ),
                  );
                },
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(
                  l10n?.translate('openNodeEditor') ?? 'Open Node Editor',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.translate('cancel') ?? 'Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              await _saveProjectAction();
              if (!context.mounted) {
                return;
              }
              ref.invalidate(projectActionsProvider);
              Navigator.pop(context);
            } catch (error) {
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${l10n?.translate('error') ?? 'Error'}: $error',
                  ),
                ),
              );
            }
          },
          child: Text(l10n?.translate('save') ?? 'Save'),
        ),
      ],
    );
  }
}

class ActionNodeEditorScreen extends ConsumerStatefulWidget {
  final String? initialActionId;
  final String? initialActionName;
  final String? initialNodeGraph;

  const ActionNodeEditorScreen({
    super.key,
    this.initialActionId,
    this.initialActionName,
    this.initialNodeGraph,
  });

  @override
  ConsumerState<ActionNodeEditorScreen> createState() =>
      _ActionNodeEditorScreenState();
}

class _ActionNodeEditorScreenState
    extends ConsumerState<ActionNodeEditorScreen> {
  static const String _actionButtonTriggerNodeName = 'Action Button Trigger';
  static const String _actionButtonTriggerValue =
      defaultActionButtonTriggerInput;
  static const String _helloWorldMenuValue = '__hello_world_builtin__';
  static const String _ticketMenuValue = '__ticket_builtin__';
  static const String _projectPartsMailMenuValue =
      '__project_parts_mail_builtin__';
  static const String _addFolderMenuValue = '__add_folder_builtin__';
  static const String _fileToTodoMenuValue = '__file_to_todo_builtin__';
  static const String _personMenuValue = '__person_builtin__';
  static const String _customerMenuValue = '__customer_builtin__';
  static const String _partsOfferMenuValue = '__parts_offer_builtin__';
  static const String _partsOrderMenuValue = '__parts_order_builtin__';
  static const String _aiTextMenuValue = '__ai_text_builtin__';
  static const String _saveEmailDraftMenuValue = '__save_email_draft_builtin__';
  bool _isEnsuringStartNode = false;

  late final NodeEditorController _nodeController;
  late final FocusNode _nodeFocus;
  List<WorkflowNodeDto> _nodeTypes = const [];
  bool _isLoadingNodeTypes = true;
  String? _nodeTypesError;
  final Map<String, _NodeRuntimeMetadata> _nodeMetadataByName = {};
  final Map<String, _TodoNodeConfig> _todoNodeConfigByName = {};
  final Map<String, _TicketNodeConfig> _ticketNodeConfigByName = {};
  final Map<String, _ProjectPartsMailNodeConfig> _projectPartsMailConfigByName =
      {};
  final Map<String, _AddFolderNodeConfig> _addFolderNodeConfigByName = {};
  final Map<String, _FileTodoNodeConfig> _fileTodoNodeConfigByName = {};
  final Map<String, _PersonNodeConfig> _personNodeConfigByName = {};
  final Map<String, _CustomerNodeConfig> _customerNodeConfigByName = {};
  final Map<String, _PartsOfferNodeConfig> _partsOfferNodeConfigByName = {};
  final Map<String, _PartsOrderNodeConfig> _partsOrderNodeConfigByName = {};
  final Map<String, _AiTextNodeConfig> _aiTextNodeConfigByName = {};
  final Map<String, _SaveEmailDraftNodeConfig> _saveEmailDraftNodeConfigByName =
      {};
  bool _isSavingGraph = false;

  @override
  void initState() {
    super.initState();
    _nodeController = NodeEditorController();
    _nodeFocus = FocusNode();
    _nodeController.focusNode = _nodeFocus;
    _nodeController.addListener(_ensureStartNode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loaded = _loadSavedGraph();
      if (!loaded) {
        _ensureStartNode();
        final helloWorldName = _nextUniqueNodeName('Hello World');
        _nodeController.addNode(
          _helloWorldNode(context, name: helloWorldName),
          const NodePosition.custom(Offset(420, 120)),
        );
        _registerNodeMetadata(
          name: helloWorldName,
          typeName: 'Hello World',
          category: 'AddFunctions',
          functionLabel: 'hello_world',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
        );
      }
      _nodeController.notify();
    });
    _loadNodeTypes();
  }

  bool _loadSavedGraph() {
    final raw = widget.initialNodeGraph?.trim();
    if (raw == null || raw.isEmpty || raw == '{}') {
      return false;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return false;
    }

    if (decoded is! Map<String, dynamic>) {
      return false;
    }

    final nodes = decoded['nodes'];
    if (nodes is! List) {
      return false;
    }

    bool loadedAnyNode = false;

    // Adding nodes below fires _nodeController's listeners synchronously.
    // _ensureStartNode is one of them, and if it runs mid-loop (before we've
    // reached the serialized "Action Button Trigger" entry) it would insert
    // its own default-position start node first. When the loop later reaches
    // the real trigger entry from the saved graph, adding a second node with
    // the same name would throw. Detach the listener for the duration of the
    // load and call it once, manually, at the end instead.
    _nodeController.removeListener(_ensureStartNode);
    try {
      for (final entry in nodes) {
        if (entry is! Map) {
          continue;
        }

        final node = entry.map((key, value) => MapEntry(key.toString(), value));

        final nodeName = ((node['name'] ?? node['id'])?.toString().trim() ?? '');
        if (nodeName.isEmpty) {
          continue;
        }

        // Defensive guard: never try to add a node name that's already on
        // the canvas (e.g. a corrupted/duplicated saved graph), since the
        // node editor controller does not support duplicate node names.
        if (_nodeController.nodes.containsKey(nodeName)) {
          continue;
        }

        final typeName =
            _readString(node, const ['type']) ??
            _readString(node, const ['runtime_metadata', 'type_name']) ??
            nodeName;
        final category =
            _readString(node, const ['runtime_metadata', 'category']) ??
            'Information';
        final functionLabel = _readString(node, const [
          'runtime_metadata',
          'function_label',
        ]);
        final endpointLabel = _readString(node, const [
          'runtime_metadata',
          'endpoint_label',
        ]);
        final triggerInput = normalizeWorkflowTriggerInput(
          _readString(node, const ['runtime_metadata', 'trigger_input']),
        );

        final x = _readDouble(node, const ['position', 'x']) ?? 220;
        final y = _readDouble(node, const ['position', 'y']) ?? 160;

        if (nodeName == _actionButtonTriggerNodeName ||
            typeName.toLowerCase() == 'action button trigger') {
          _nodeController.addNode(
            _startNode(context),
            NodePosition.custom(Offset(x, y)),
          );
          loadedAnyNode = true;
          continue;
        }

        final configuration = _nodeConfigFromSerialized(node);
        _registerNodeMetadata(
          name: nodeName,
          typeName: typeName,
          category: category,
          functionLabel: functionLabel,
          endpointLabel: endpointLabel,
          triggerInput: triggerInput,
          configuration: configuration,
        );

        final inputPortName = _normalizeInputPortName(_firstInputPortName(node));

        _nodeController.addNode(
          _workflowTypeNode(
            context,
            name: nodeName,
            typeName: typeName,
            category: category,
            functionLabel: functionLabel,
            endpointLabel: endpointLabel,
            triggerInput: triggerInput,
            position: Offset(x, y),
            inputPortName: inputPortName,
            inputPortLabel: inputPortName.toLowerCase().contains('trigger')
                ? 'Trigger In'
                : 'Execution In',
          ),
          NodePosition.custom(Offset(x, y)),
        );
        loadedAnyNode = true;
      }

      if (!loadedAnyNode) {
        return false;
      }

      final connections = decoded['connections'];
      if (connections is List) {
        for (final entry in connections) {
          if (entry is! Map) {
            continue;
          }
          final connection = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );

          final outNode = _readString(connection, const ['sourceNodeId']);
          final inNode = _readString(connection, const ['targetNodeId']);
          final outPort =
              _readString(connection, const ['sourceOutputId']) ??
              _readString(connection, const ['sourcePortId']);
          final inPort =
              _readString(connection, const ['targetInputId']) ??
              _readString(connection, const ['targetPortId']);

          if (outNode == null ||
              inNode == null ||
              outPort == null ||
              inPort == null ||
              !_nodeController.nodes.containsKey(outNode) ||
              !_nodeController.nodes.containsKey(inNode)) {
            continue;
          }

          try {
            _nodeController.setConnecting(outNode, outPort);
            _nodeController.addConnectionByTap(inNode: inNode, inPort: inPort);
          } catch (_) {
            _nodeController.unsetConnecting();
          }
        }
        _nodeController.unsetConnecting();
      }

      return true;
    } finally {
      // Always re-attach, and reconcile once, whether loading succeeded,
      // partially failed, or threw.
      _nodeController.addListener(_ensureStartNode);
      _ensureStartNode();
    }
  }

  String? _readString(Map<String, dynamic> source, List<String> path) {
    dynamic value = source;
    for (final key in path) {
      if (value is! Map) {
        return null;
      }
      value = value[key];
    }
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'unknown') {
      return null;
    }
    return text;
  }

  double? _readDouble(Map<String, dynamic> source, List<String> path) {
    dynamic value = source;
    for (final key in path) {
      if (value is! Map) {
        return null;
      }
      value = value[key];
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  String? _firstInputPortName(Map<String, dynamic> node) {
    final inputs = node['inputs'];
    if (inputs is! List) {
      return null;
    }
    for (final item in inputs) {
      if (item is! Map) {
        continue;
      }
      final name = item['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return null;
  }

  String _normalizeInputPortName(String? portName) {
    if (portName == null || portName.trim().isEmpty) {
      return 'trigger';
    }

    final normalized = portName.trim().toLowerCase();
    if (normalized.contains('trigger')) {
      return portName.trim();
    }

    return 'trigger';
  }

  Map<String, dynamic> _nodeConfigFromSerialized(Map<String, dynamic> node) {
    final config = <String, dynamic>{};

    void mergeValue(String key) {
      final value = node[key];
      if (value is Map<String, dynamic>) {
        config.addAll(value);
      } else if (value is Map) {
        config.addAll(value.map((k, v) => MapEntry(k.toString(), v)));
      }
    }

    mergeValue('todo_config');
    mergeValue('ticket_config');
    mergeValue('mail_parts_config');
    mergeValue('folder_files_config');
    mergeValue('file_todo_config');
    mergeValue('person_config');
    mergeValue('customer_config');
    mergeValue('parts_offer_config');
    mergeValue('parts_order_config');
    mergeValue('ai_text_config');
    mergeValue('save_email_draft_config');

    return config;
  }

  bool _isTodoCategory(String category) {
    return category.trim().toLowerCase() == 'todos';
  }

  bool _isTicketFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'create_ticket';
  }

  bool _isProjectPartsMailFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'send_project_parts_email';
  }

  bool _isAddFolderFunction(String? functionLabel) {
    final value = functionLabel?.trim().toLowerCase();
    return value == 'add_folder' || value == 'create_folder';
  }

  bool _isFileToTodoFunction(String? functionLabel) {
    final value = functionLabel?.trim().toLowerCase();
    return value == 'file_to_todo' || value == 'file_consumer';
  }

  bool _isPersonFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'assign_person';
  }

  bool _isCustomerFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'assign_customer';
  }

  bool _isPartsOfferFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'send_parts_offer_email';
  }

  bool _isPartsOrderFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'send_parts_order_email';
  }

  bool _isAiTextFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'ai_text_generate';
  }

  bool _isSaveEmailDraftFunction(String? functionLabel) {
    return functionLabel?.trim().toLowerCase() == 'save_email_draft';
  }

  String _filePortName(String fileName) {
    final normalized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'file_${normalized.isEmpty ? 'file' : normalized}';
  }

  /// One accent color per node "family" so related nodes are instantly
  /// recognizable and connections are visually traceable, similar to how
  /// n8n colors its node headers by category.
  Color _categoryAccentColor({
    required String? functionLabel,
    required String category,
  }) {
    final function = functionLabel?.trim().toLowerCase() ?? '';

    if (function == 'hello_world') return const Color(0xFFF5A623); // trigger amber
    if (function == 'create_ticket') return const Color(0xFFE0631E); // ticket orange
    if (function == 'send_project_parts_mail' ||
        function == 'send_parts_offer_email' ||
        function == 'send_parts_order_email') {
      return const Color(0xFF8E44AD); // parts/mail purple
    }
    if (_isAddFolderFunction(functionLabel) ||
        function == 'file_to_todo' ||
        function == 'file_consumer') {
      return const Color(0xFF17A2B8); // files/folders cyan
    }
    if (function == 'assign_person' || function == 'assign_customer') {
      return const Color(0xFF16A085); // data-source teal
    }
    if (function == 'ai_text_generate') return const Color(0xFFD6336C); // AI pink
    if (function == 'save_email_draft') return const Color(0xFF3B5BDB); // email indigo
    if (_isTodoCategory(category)) return const Color(0xFF2F80ED); // todo blue

    return AppColors.primaryDark; // fallback / unrecognized node types
  }

  /// Matching icon for each node family, shown in the node's title bar.
  IconData _categoryIcon({
    required String? functionLabel,
    required String category,
  }) {
    final function = functionLabel?.trim().toLowerCase() ?? '';

    if (function == 'hello_world') return Icons.play_circle_fill;
    if (function == 'create_ticket') return Icons.confirmation_number_outlined;
    if (function == 'send_project_parts_mail') return Icons.mail_outline;
    if (function == 'send_parts_offer_email') return Icons.local_offer_outlined;
    if (function == 'send_parts_order_email') return Icons.inventory_2_outlined;
    if (_isAddFolderFunction(functionLabel)) return Icons.create_new_folder_outlined;
    if (function == 'file_to_todo' || function == 'file_consumer') {
      return Icons.insert_drive_file_outlined;
    }
    if (function == 'assign_person') return Icons.person_outline;
    if (function == 'assign_customer') return Icons.business_outlined;
    if (function == 'ai_text_generate') return Icons.smart_toy_outlined;
    if (function == 'save_email_draft') return Icons.drafts_outlined;
    if (_isTodoCategory(category)) return Icons.checklist_outlined;

    return Icons.account_tree_outlined;
  }

  _NodePortLabels _portLabelsFor({
    required String? functionLabel,
    required String category,
    required bool isAddFolderNode,
  }) {
    final function = functionLabel?.trim().toLowerCase() ?? '';

    if (function == 'hello_world') {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Fires execution',
      );
    }
    if (function == 'create_ticket') {
      return const _NodePortLabels(
        inputDescription: 'Trigger + inherited Person (optional assignee)',
        outputDescription: 'Ticket id, name, assignee',
      );
    }
    if (function == 'send_project_parts_mail' || _isProjectPartsMailFunction(functionLabel)) {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Recipient, parts count, send result',
      );
    }
    if (isAddFolderNode) {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Folder id + one output per file',
      );
    }
    if (function == 'file_to_todo' || function == 'file_consumer') {
      return const _NodePortLabels(
        inputDescription: 'File (from an Add Folder node)',
        outputDescription: 'Todo id created from the file',
      );
    }
    if (function == 'assign_person') {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Person: id, name, email, login, department',
      );
    }
    if (function == 'assign_customer') {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Customer: id, name, contact email',
      );
    }
    if (function == 'send_parts_offer_email') {
      return const _NodePortLabels(
        inputDescription: 'Trigger + inherited Person/Customer email (optional)',
        outputDescription: 'One email sent per selected part + attachments',
      );
    }
    if (function == 'send_parts_order_email') {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Order email sent to department',
      );
    }
    if (function == 'ai_text_generate') {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Generated text (ai_text)',
      );
    }
    if (function == 'save_email_draft') {
      return const _NodePortLabels(
        inputDescription: 'Trigger + inherited AI text / email (optional)',
        outputDescription: 'Draft saved in your mailbox',
      );
    }
    if (_isTodoCategory(category)) {
      return const _NodePortLabels(
        inputDescription: 'Trigger only',
        outputDescription: 'Todo id, name',
      );
    }
    return const _NodePortLabels(
      inputDescription: 'Trigger / execution',
      outputDescription: 'Execution result',
    );
  }

  Map<String, dynamic> _parseWorkflowNodeConfiguration(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Ignore invalid configuration JSON from node definitions.
    }

    return const <String, dynamic>{};
  }

  void _registerNodeMetadata({
    required String name,
    required String typeName,
    required String category,
    required String? functionLabel,
    required String? endpointLabel,
    required String triggerInput,
    Map<String, dynamic>? configuration,
  }) {
    _nodeMetadataByName[name] = _NodeRuntimeMetadata(
      typeName: typeName,
      category: category,
      functionLabel: functionLabel,
      endpointLabel: endpointLabel,
      triggerInput: normalizeWorkflowTriggerInput(triggerInput),
    );

    if (_isTicketFunction(functionLabel)) {
      final existing = _ticketNodeConfigByName[name];
      _ticketNodeConfigByName[name] =
          existing ?? _TicketNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isProjectPartsMailFunction(functionLabel)) {
      final existing = _projectPartsMailConfigByName[name];
      _projectPartsMailConfigByName[name] =
          existing ??
          _ProjectPartsMailNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isAddFolderFunction(functionLabel)) {
      final existing = _addFolderNodeConfigByName[name];
      _addFolderNodeConfigByName[name] =
          existing ?? _AddFolderNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isFileToTodoFunction(functionLabel)) {
      final existing = _fileTodoNodeConfigByName[name];
      _fileTodoNodeConfigByName[name] =
          existing ?? _FileTodoNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isPersonFunction(functionLabel)) {
      final existing = _personNodeConfigByName[name];
      _personNodeConfigByName[name] =
          existing ?? _PersonNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isCustomerFunction(functionLabel)) {
      final existing = _customerNodeConfigByName[name];
      _customerNodeConfigByName[name] =
          existing ?? _CustomerNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isPartsOfferFunction(functionLabel)) {
      final existing = _partsOfferNodeConfigByName[name];
      _partsOfferNodeConfigByName[name] =
          existing ?? _PartsOfferNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isPartsOrderFunction(functionLabel)) {
      final existing = _partsOrderNodeConfigByName[name];
      _partsOrderNodeConfigByName[name] =
          existing ?? _PartsOrderNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isAiTextFunction(functionLabel)) {
      final existing = _aiTextNodeConfigByName[name];
      _aiTextNodeConfigByName[name] =
          existing ?? _AiTextNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isSaveEmailDraftFunction(functionLabel)) {
      final existing = _saveEmailDraftNodeConfigByName[name];
      _saveEmailDraftNodeConfigByName[name] =
          existing ??
          _SaveEmailDraftNodeConfig.fromMap(configuration ?? const {});
      return;
    }

    if (_isTodoCategory(category)) {
      final existing = _todoNodeConfigByName[name];
      _todoNodeConfigByName[name] =
          existing ?? _TodoNodeConfig.fromMap(configuration ?? const {});
    }
  }

  Future<String?> _resolveCompanyId() async {
    final authState = ref.read(authStateProvider);
    final currentCompanyId = authState.companyId?.trim();
    if (currentCompanyId != null && currentCompanyId.isNotEmpty) {
      return currentCompanyId;
    }

    final companies = await ref.read(apiClientProvider).companies();
    return companies.isNotEmpty ? companies.first.id : null;
  }

  String? _dateToApiString(DateTime? value) {
    if (value == null) {
      return null;
    }
    final dateOnly = DateTime(value.year, value.month, value.day);
    return dateOnly.toIso8601String().split('T').first;
  }

  String _dateLabel(DateTime? value) {
    final apiDate = _dateToApiString(value);
    return apiDate ?? 'Not set';
  }

  List<String> _splitLogins(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _openTodoNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isTodoCategory(metadata.category)) {
      return;
    }

    final api = ref.read(apiClientProvider);
    List<String> departments;
    List<EmployeeDto> employees;

    try {
      final results = await Future.wait<dynamic>([
        api.authDepartments(),
        api.authEmployees(),
      ]);
      departments = results[0] as List<String>;
      employees = results[1] as List<EmployeeDto>;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load Todo recipients: $error')),
      );
      return;
    }

    final currentConfig =
        _todoNodeConfigByName[nodeName] ??
        _TodoNodeConfig.fromMap({'name': nodeName});

    final nameController = TextEditingController(text: currentConfig.name);
    final descriptionController = TextEditingController(
      text: currentConfig.description,
    );
    final coworkerController = TextEditingController(
      text: currentConfig.coworkerLogins.join(', '),
    );
    final companyIdController = TextEditingController(
      text: currentConfig.companyId,
    );
    final projectIdController = TextEditingController(
      text: currentConfig.projectId,
    );
    final folderIdController = TextEditingController(
      text: currentConfig.folderId,
    );

    var assigneeType = currentConfig.assigneeType;
    var selectedDepartment = departments.contains(currentConfig.department)
        ? currentConfig.department
        : null;
    var selectedMainEmployer =
        employees.any(
          (employee) => employee.loginName == currentConfig.mainEmployer,
        )
        ? currentConfig.mainEmployer
        : null;
    var startDate = currentConfig.startDate;
    var endDate = currentConfig.endDate;
    var projectStatus = currentConfig.projectStatus;

    final result = await showDialog<_TodoNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> pickDate({required bool isStartDate}) async {
              final initial =
                  (isStartDate ? startDate : endDate) ?? DateTime.now();
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) {
                return;
              }

              setLocalState(() {
                if (isStartDate) {
                  startDate = picked;
                } else {
                  endDate = picked;
                }
              });
            }

            return AlertDialog(
              title: Text('Edit Todo Node: $nodeName'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Todo Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_TodoAssigneeType>(
                        initialValue: assigneeType,
                        decoration: const InputDecoration(
                          labelText: 'Assign To',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: _TodoAssigneeType.person,
                            child: Text('Person'),
                          ),
                          DropdownMenuItem(
                            value: _TodoAssigneeType.department,
                            child: Text('Department'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setLocalState(() {
                            assigneeType = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (assigneeType == _TodoAssigneeType.department)
                        DropdownButtonFormField<String>(
                          initialValue: selectedDepartment,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                          ),
                          items: departments
                              .map(
                                (department) => DropdownMenuItem(
                                  value: department,
                                  child: Text(department),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setLocalState(() {
                              selectedDepartment = value;
                            });
                          },
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: selectedMainEmployer,
                          decoration: const InputDecoration(
                            labelText: 'Main Person',
                          ),
                          items: employees
                              .map(
                                (employee) => DropdownMenuItem(
                                  value: employee.loginName,
                                  child: Text(
                                    '${employee.firstName} ${employee.lastName} (${employee.loginName})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setLocalState(() {
                              selectedMainEmployer = value;
                            });
                          },
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: coworkerController,
                        decoration: const InputDecoration(
                          labelText: 'Coworker Logins',
                          hintText: 'comma,separated,logins',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStartDate: true),
                              icon: const Icon(Icons.event),
                              label: Text('Start: ${_dateLabel(startDate)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(isStartDate: false),
                              icon: const Icon(Icons.event_available),
                              label: Text('End: ${_dateLabel(endDate)}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: projectStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(
                            value: 'inWork',
                            child: Text('inWork'),
                          ),
                          DropdownMenuItem(
                            value: 'backlog',
                            child: Text('backlog'),
                          ),
                          DropdownMenuItem(value: 'done', child: Text('done')),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setLocalState(() {
                            projectStatus = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: companyIdController,
                        decoration: const InputDecoration(
                          labelText: 'Company ID (optional override)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectIdController,
                        decoration: const InputDecoration(
                          labelText: 'Project ID (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: folderIdController,
                        decoration: const InputDecoration(
                          labelText: 'Folder ID (optional)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final todoName = nameController.text.trim();
                    if (todoName.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Todo name is required.')),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _TodoNodeConfig(
                        name: todoName,
                        assigneeType: assigneeType,
                        department: selectedDepartment ?? '',
                        mainEmployer: selectedMainEmployer ?? '',
                        coworkerLogins: _splitLogins(coworkerController.text),
                        description: descriptionController.text.trim(),
                        startDate: startDate,
                        endDate: endDate,
                        projectStatus: projectStatus,
                        companyId: companyIdController.text.trim(),
                        projectId: projectIdController.text.trim(),
                        folderId: folderIdController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save Todo Config'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
    coworkerController.dispose();
    companyIdController.dispose();
    projectIdController.dispose();
    folderIdController.dispose();

    if (result == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _todoNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openTicketNodeEditor(String nodeName) async {
    List<String> departments;
    try {
      departments = await ref.read(apiClientProvider).authDepartments();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load departments: $error')),
      );
      return;
    }

    final currentConfig =
        _ticketNodeConfigByName[nodeName] ??
        _TicketNodeConfig.fromMap({'name': nodeName});

    final nameController = TextEditingController(text: currentConfig.name);
    final textController = TextEditingController(text: currentConfig.text);
    final companyIdController = TextEditingController(
      text: currentConfig.companyId,
    );
    final projectIdController = TextEditingController(
      text: currentConfig.projectId,
    );
    final folderIdController = TextEditingController(
      text: currentConfig.folderId,
    );

    var selectedDepartment = departments.contains(currentConfig.department)
        ? currentConfig.department
        : null;

    final result = await showDialog<_TicketNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit Ticket Node: $nodeName'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Ticket Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Ticket Text',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDepartment,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                        ),
                        items: departments
                            .map(
                              (department) => DropdownMenuItem(
                                value: department,
                                child: Text(department),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setLocalState(() {
                            selectedDepartment = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: companyIdController,
                        decoration: const InputDecoration(
                          labelText: 'Company ID (optional override)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectIdController,
                        decoration: const InputDecoration(
                          labelText: 'Project ID (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: folderIdController,
                        decoration: const InputDecoration(
                          labelText: 'Folder ID (optional)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final ticketName = nameController.text.trim();
                    if (ticketName.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Ticket name is required.'),
                        ),
                      );
                      return;
                    }
                    if ((selectedDepartment ?? '').trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Department is required.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _TicketNodeConfig(
                        name: ticketName,
                        text: textController.text.trim(),
                        department: selectedDepartment ?? '',
                        companyId: companyIdController.text.trim(),
                        projectId: projectIdController.text.trim(),
                        folderId: folderIdController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save Ticket Config'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    textController.dispose();
    companyIdController.dispose();
    projectIdController.dispose();
    folderIdController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _ticketNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openProjectPartsMailNodeEditor(String nodeName) async {
    final currentConfig =
        _projectPartsMailConfigByName[nodeName] ??
        _ProjectPartsMailNodeConfig.fromMap({
          'project_id': '',
          'subject': '',
          'recipient_email': '',
        });

    final recipientController = TextEditingController(
      text: currentConfig.recipientEmail,
    );
    final subjectController = TextEditingController(
      text: currentConfig.subject,
    );
    final projectIdController = TextEditingController(
      text: currentConfig.projectId,
    );

    final result = await showDialog<_ProjectPartsMailNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Edit Project Parts Mail Node: $nodeName'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: recipientController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Recipient Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: projectIdController,
                    decoration: const InputDecoration(
                      labelText: 'Project ID (optional override)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wenn Project ID leer ist, wird die ID aus dem Action-Trigger verwendet.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final recipient = recipientController.text.trim();
                if (recipient.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Recipient email is required.'),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop(
                  _ProjectPartsMailNodeConfig(
                    recipientEmail: recipient,
                    subject: subjectController.text.trim(),
                    projectId: projectIdController.text.trim(),
                  ),
                );
              },
              child: const Text('Save Mail Config'),
            ),
          ],
        );
      },
    );

    recipientController.dispose();
    subjectController.dispose();
    projectIdController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _projectPartsMailConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openAddFolderNodeEditor(String nodeName) async {
    final currentConfig =
        _addFolderNodeConfigByName[nodeName] ??
        _AddFolderNodeConfig.fromMap({'folder_name': nodeName, 'files': []});

    final folderNameController = TextEditingController(
      text: currentConfig.folderName,
    );
    final projectIdController = TextEditingController(
      text: currentConfig.projectId,
    );
    final localFiles = <_FolderFileSpec>[...currentConfig.files];

    final result = await showDialog<_AddFolderNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> pickFiles() async {
              final picked = await FilePicker.platform.pickFiles(
                allowMultiple: true,
                withData: true,
              );
              if (picked == null) {
                return;
              }
              setLocalState(() {
                for (final file in picked.files) {
                  final bytes = file.bytes;
                  if (bytes == null || bytes.isEmpty) {
                    continue;
                  }
                  localFiles.add(
                    _FolderFileSpec(
                      name: file.name,
                      content: '',
                      bytesBase64: base64Encode(bytes),
                      mimeType: file.extension == null
                          ? null
                          : _guessMimeType(file.extension!),
                    ),
                  );
                }
              });
            }

            return AlertDialog(
              title: Text('Edit Add Folder Node: $nodeName'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: folderNameController,
                        decoration: const InputDecoration(
                          labelText: 'Folder Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectIdController,
                        decoration: const InputDecoration(
                          labelText: 'Project ID (optional override)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: pickFiles,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Upload Files'),
                      ),
                      const SizedBox(height: 10),
                      if (localFiles.isEmpty)
                        Text(
                          'No files selected.',
                          style: Theme.of(dialogContext).textTheme.bodySmall,
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: localFiles.length,
                            itemBuilder: (context, index) {
                              final entry = localFiles[index];
                              return ListTile(
                                dense: true,
                                title: Text(entry.name),
                                subtitle: Text(
                                  entry.bytesBase64 == null
                                      ? 'Text template entry'
                                      : 'Uploaded binary file',
                                ),
                                trailing: IconButton(
                                  onPressed: () {
                                    setLocalState(() {
                                      localFiles.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Each uploaded file creates a dedicated output port on this node.',
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final folderName = folderNameController.text.trim();
                    if (folderName.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Folder name is required.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _AddFolderNodeConfig(
                        folderName: folderName,
                        projectId: projectIdController.text.trim(),
                        files: [...localFiles],
                      ),
                    );
                  },
                  child: const Text('Save Folder Config'),
                ),
              ],
            );
          },
        );
      },
    );

    folderNameController.dispose();
    projectIdController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _addFolderNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  String? _guessMimeType(String extension) {
    final ext = extension.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return null;
    }
  }

  Future<void> _openFileTodoNodeEditor(String nodeName) async {
    List<String> departments;
    try {
      departments = await ref.read(apiClientProvider).authDepartments();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load departments: $error')),
      );
      return;
    }

    final currentConfig =
        _fileTodoNodeConfigByName[nodeName] ??
        _FileTodoNodeConfig.fromMap({
          'name': 'File Follow-up',
          'department': '',
        });

    final nameController = TextEditingController(text: currentConfig.name);
    final descriptionController = TextEditingController(
      text: currentConfig.description,
    );
    final companyIdController = TextEditingController(
      text: currentConfig.companyId,
    );
    final projectIdController = TextEditingController(
      text: currentConfig.projectId,
    );

    var selectedDepartment = departments.contains(currentConfig.department)
        ? currentConfig.department
        : null;

    final result = await showDialog<_FileTodoNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit File To Todo Node: $nodeName'),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Todo Title Prefix',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDepartment,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                        ),
                        items: departments
                            .map(
                              (department) => DropdownMenuItem(
                                value: department,
                                child: Text(department),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setLocalState(() {
                            selectedDepartment = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: companyIdController,
                        decoration: const InputDecoration(
                          labelText: 'Company ID (optional override)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectIdController,
                        decoration: const InputDecoration(
                          labelText: 'Project ID (optional override)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final titlePrefix = nameController.text.trim();
                    if (titlePrefix.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Todo title prefix is required.'),
                        ),
                      );
                      return;
                    }
                    if ((selectedDepartment ?? '').trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Department is required.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _FileTodoNodeConfig(
                        name: titlePrefix,
                        department: selectedDepartment ?? '',
                        description: descriptionController.text.trim(),
                        companyId: companyIdController.text.trim(),
                        projectId: projectIdController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save File Todo Config'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
    companyIdController.dispose();
    projectIdController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _fileTodoNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _sendGoogleTestMailForNode(String nodeName) async {
    final config = _projectPartsMailConfigByName[nodeName];
    if (config == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mail config not found for node.')),
      );
      return;
    }

    final recipient = config.recipientEmail.trim();
    if (recipient.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst Recipient Email eintragen.'),
        ),
      );
      return;
    }

    final projectId = config.projectId.trim();
    final customSubject = config.subject.trim();

    try {
      final response = await ref
          .read(apiClientProvider)
          .sendGoogleTestMail(
            recipientEmail: recipient,
            subject: customSubject.isEmpty ? null : customSubject,
            projectId: projectId.isEmpty ? null : projectId,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Google Test-Mail gesendet an ${response['recipient_email'] ?? recipient}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google Test-Mail fehlgeschlagen: $error')),
      );
    }
  }

  Future<void> _openPersonNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isPersonFunction(metadata.functionLabel)) {
      return;
    }

    List<EmployeeDto> employees;
    try {
      employees = await ref.read(apiClientProvider).adminEmployees();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load employees: $error')),
      );
      return;
    }

    final currentConfig =
        _personNodeConfigByName[nodeName] ??
        const _PersonNodeConfig(employeeId: '', employeeLabel: '');
    var selectedEmployeeId = employees.any(
      (employee) => employee.id == currentConfig.employeeId,
    )
        ? currentConfig.employeeId
        : null;

    final result = await showDialog<_PersonNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit Person Node: $nodeName'),
              content: SizedBox(
                width: 420,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedEmployeeId,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: employees
                      .map(
                        (employee) => DropdownMenuItem(
                          value: employee.id,
                          child: Text(
                            '${employee.firstName} ${employee.lastName}'
                            '${(employee.department ?? '').isNotEmpty ? ' (${employee.department})' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setLocalState(() {
                      selectedEmployeeId = value;
                    });
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedEmployeeId == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Please select an employee.'),
                        ),
                      );
                      return;
                    }
                    final employee = employees.firstWhere(
                      (item) => item.id == selectedEmployeeId,
                    );
                    Navigator.of(dialogContext).pop(
                      _PersonNodeConfig(
                        employeeId: employee.id,
                        employeeLabel:
                            '${employee.firstName} ${employee.lastName}',
                      ),
                    );
                  },
                  child: const Text('Save Person'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _personNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openCustomerNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isCustomerFunction(metadata.functionLabel)) {
      return;
    }

    List<CompanyDto> customers;
    try {
      customers = await ref.read(apiClientProvider).clientCompanies();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load customers: $error')),
      );
      return;
    }

    final currentConfig =
        _customerNodeConfigByName[nodeName] ??
        const _CustomerNodeConfig(customerCompanyId: '', customerLabel: '');
    var selectedCustomerId = customers.any(
      (customer) => customer.id == currentConfig.customerCompanyId,
    )
        ? currentConfig.customerCompanyId
        : null;

    final result = await showDialog<_CustomerNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit Customer Node: $nodeName'),
              content: SizedBox(
                width: 420,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedCustomerId,
                  decoration: const InputDecoration(labelText: 'Customer'),
                  items: customers
                      .map(
                        (customer) => DropdownMenuItem(
                          value: customer.id,
                          child: Text(customer.uniqueName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setLocalState(() {
                      selectedCustomerId = value;
                    });
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedCustomerId == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a customer.'),
                        ),
                      );
                      return;
                    }
                    final customer = customers.firstWhere(
                      (item) => item.id == selectedCustomerId,
                    );
                    Navigator.of(dialogContext).pop(
                      _CustomerNodeConfig(
                        customerCompanyId: customer.id,
                        customerLabel: customer.uniqueName,
                      ),
                    );
                  },
                  child: const Text('Save Customer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _customerNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openPartsOfferNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isPartsOfferFunction(metadata.functionLabel)) {
      return;
    }

    List<PartDto> parts;
    try {
      parts = await ref.read(apiClientProvider).parts(includeAll: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load parts: $error')));
      return;
    }

    final currentConfig =
        _partsOfferNodeConfigByName[nodeName] ??
        const _PartsOfferNodeConfig(items: [], recipientEmail: '');
    final noteControllers = <String, TextEditingController>{
      for (final entry in currentConfig.items)
        entry.partId: TextEditingController(text: entry.note),
    };
    final selected = <String>{
      for (final entry in currentConfig.items) entry.partId,
    };
    final recipientController = TextEditingController(
      text: currentConfig.recipientEmail,
    );

    final result = await showDialog<_PartsOfferNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit Parts Offer Node: $nodeName'),
              content: SizedBox(
                width: 480,
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Select parts to offer. Each checked part is sent as '
                      'its own email (with its CAD/CNC file and drawings '
                      'attached) to the recipient below.',
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: parts.length,
                        itemBuilder: (context, index) {
                          final part = parts[index];
                          final isSelected = selected.contains(part.id);
                          noteControllers.putIfAbsent(
                            part.id,
                            () => TextEditingController(),
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: isSelected,
                                title: Text(part.name),
                                subtitle: part.idNumber != null
                                    ? Text('Nr: ${part.idNumber}')
                                    : null,
                                onChanged: (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selected.add(part.id);
                                    } else {
                                      selected.remove(part.id);
                                    }
                                  });
                                },
                              ),
                              if (isSelected)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 32,
                                    right: 8,
                                    bottom: 8,
                                  ),
                                  child: TextField(
                                    controller: noteControllers[part.id],
                                    decoration: const InputDecoration(
                                      labelText: 'Note for this email',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: recipientController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Email',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final items = <_PartSelectionEntry>[
                      for (final part in parts)
                        if (selected.contains(part.id))
                          _PartSelectionEntry(
                            partId: part.id,
                            partName: part.name,
                            note: noteControllers[part.id]?.text.trim() ?? '',
                          ),
                    ];
                    Navigator.of(dialogContext).pop(
                      _PartsOfferNodeConfig(
                        items: items,
                        recipientEmail: recipientController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save Parts Offer'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in noteControllers.values) {
      controller.dispose();
    }
    recipientController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _partsOfferNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openPartsOrderNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isPartsOrderFunction(metadata.functionLabel)) {
      return;
    }

    List<PartDto> parts;
    List<String> departments;
    try {
      final results = await Future.wait<dynamic>([
        ref.read(apiClientProvider).parts(includeAll: true),
        ref.read(apiClientProvider).authDepartments(),
      ]);
      parts = results[0] as List<PartDto>;
      departments = results[1] as List<String>;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load parts/departments: $error')),
      );
      return;
    }

    final currentConfig =
        _partsOrderNodeConfigByName[nodeName] ??
        const _PartsOrderNodeConfig(items: [], department: '', text: '');
    final selected = <String>{
      for (final entry in currentConfig.items) entry.partId,
    };
    final quantityControllers = <String, TextEditingController>{
      for (final entry in currentConfig.items)
        entry.partId: TextEditingController(text: entry.note),
    };
    var selectedDepartment = departments.contains(currentConfig.department)
        ? currentConfig.department
        : null;
    final textController = TextEditingController(text: currentConfig.text);

    final result = await showDialog<_PartsOrderNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit Parts Order Node: $nodeName'),
              content: SizedBox(
                width: 480,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Select the parts to order. One combined email with '
                      'the list below and your message will be sent to the '
                      'chosen department.',
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: parts.length,
                        itemBuilder: (context, index) {
                          final part = parts[index];
                          final isSelected = selected.contains(part.id);
                          quantityControllers.putIfAbsent(
                            part.id,
                            () => TextEditingController(),
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: isSelected,
                                title: Text(part.name),
                                onChanged: (value) {
                                  setLocalState(() {
                                    if (value == true) {
                                      selected.add(part.id);
                                    } else {
                                      selected.remove(part.id);
                                    }
                                  });
                                },
                              ),
                              if (isSelected)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 32,
                                    right: 8,
                                    bottom: 8,
                                  ),
                                  child: TextField(
                                    controller: quantityControllers[part.id],
                                    decoration: const InputDecoration(
                                      labelText: 'Quantity / note',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDepartment,
                      decoration: const InputDecoration(
                        labelText: 'Send to Department',
                      ),
                      items: departments
                          .map(
                            (department) => DropdownMenuItem(
                              value: department,
                              child: Text(department),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setLocalState(() {
                          selectedDepartment = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedDepartment == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a department.'),
                        ),
                      );
                      return;
                    }
                    final items = <_PartSelectionEntry>[
                      for (final part in parts)
                        if (selected.contains(part.id))
                          _PartSelectionEntry(
                            partId: part.id,
                            partName: part.name,
                            note:
                                quantityControllers[part.id]?.text.trim() ??
                                '',
                          ),
                    ];
                    Navigator.of(dialogContext).pop(
                      _PartsOrderNodeConfig(
                        items: items,
                        department: selectedDepartment!,
                        text: textController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save Parts Order'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    textController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _partsOrderNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openAiTextNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isAiTextFunction(metadata.functionLabel)) {
      return;
    }

    List<AiServerConfigDto> aiServers;
    try {
      aiServers = (await ref.read(apiClientProvider).getServerSettings()).aiServers;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load AI servers: $error')),
      );
      return;
    }

    if (aiServers.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No AI servers configured yet. Add one under Admin > Server Settings.',
          ),
        ),
      );
      return;
    }

    final currentConfig =
        _aiTextNodeConfigByName[nodeName] ??
        const _AiTextNodeConfig(aiServerName: '', task: '', personality: '');
    var selectedServerName = aiServers.any(
      (server) => server.name == currentConfig.aiServerName,
    )
        ? currentConfig.aiServerName
        : null;
    final taskController = TextEditingController(text: currentConfig.task);
    final personalityController = TextEditingController(
      text: currentConfig.personality,
    );

    final result = await showDialog<_AiTextNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text('Edit AI Text Node: $nodeName'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedServerName,
                      decoration: const InputDecoration(labelText: 'AI Server'),
                      items: aiServers
                          .map(
                            (server) => DropdownMenuItem(
                              value: server.name,
                              child: Text(server.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setLocalState(() {
                          selectedServerName = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: personalityController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Personality (system prompt)',
                        hintText: 'e.g. Friendly, concise customer support agent',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: taskController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Task',
                        hintText: 'e.g. Write a short follow-up email about ...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedServerName == null ||
                        taskController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a server and enter a task.'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _AiTextNodeConfig(
                        aiServerName: selectedServerName!,
                        task: taskController.text.trim(),
                        personality: personalityController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save AI Text Node'),
                ),
              ],
            );
          },
        );
      },
    );

    taskController.dispose();
    personalityController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _aiTextNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _openSaveEmailDraftNodeEditor(String nodeName) async {
    final metadata = _nodeMetadataByName[nodeName];
    if (metadata == null || !_isSaveEmailDraftFunction(metadata.functionLabel)) {
      return;
    }

    final currentConfig =
        _saveEmailDraftNodeConfigByName[nodeName] ??
        const _SaveEmailDraftNodeConfig(
          recipientEmail: '',
          subject: '',
          body: '',
        );
    final recipientController = TextEditingController(
      text: currentConfig.recipientEmail,
    );
    final subjectController = TextEditingController(text: currentConfig.subject);
    final bodyController = TextEditingController(text: currentConfig.body);

    final result = await showDialog<_SaveEmailDraftNodeConfig>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Edit Save Email Draft Node: $nodeName'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Saves this email as a draft in your own mailbox '
                  '(configured under My Account > Mail Settings). Leave '
                  'Subject/Body blank to use text from an upstream AI Text node.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: recipientController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Email (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Body (optional, inherits AI Text if blank)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  _SaveEmailDraftNodeConfig(
                    recipientEmail: recipientController.text.trim(),
                    subject: subjectController.text.trim(),
                    body: bodyController.text.trim(),
                  ),
                );
              },
              child: const Text('Save Email Draft Node'),
            ),
          ],
        );
      },
    );

    recipientController.dispose();
    subjectController.dispose();
    bodyController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _saveEmailDraftNodeConfigByName[nodeName] = result;
    });
    _nodeController.notify();
  }

  Future<void> _loadNodeTypes() async {
    try {
      final nodeTypes = await ref.read(apiClientProvider).getWorkflowNodes();
      if (!mounted) {
        return;
      }
      setState(() {
        _nodeTypes = nodeTypes;
        _isLoadingNodeTypes = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nodeTypesError = error.toString();
        _isLoadingNodeTypes = false;
      });
    }
  }

  Future<void> _openWorkflowNodeCreator() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const WorkflowNodeDialog(),
    );

    if (saved == true) {
      ref.invalidate(workflowNodesProvider);
      await _loadNodeTypes();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workflow node type created.')),
      );
    }
  }

  Future<void> _openAddNodeMenu({
    required Offset globalPosition,
    required Offset localPosition,
  }) async {
    if (_isLoadingNodeTypes) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Loading node types...')));
      return;
    }

    if (_nodeTypesError != null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load node types: $_nodeTypesError')),
      );
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selectedType = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: _helloWorldMenuValue,
          child: Text('Hello World'),
        ),
        const PopupMenuItem<String>(
          value: _ticketMenuValue,
          child: Text('Ticket Node'),
        ),
        const PopupMenuItem<String>(
          value: _projectPartsMailMenuValue,
          child: Text('Project Parts Mail Node'),
        ),
        const PopupMenuItem<String>(
          value: _addFolderMenuValue,
          child: Text('Add Folder Node'),
        ),
        const PopupMenuItem<String>(
          value: _fileToTodoMenuValue,
          child: Text('File To Todo Node'),
        ),
        const PopupMenuItem<String>(
          value: _personMenuValue,
          child: Text('Person Node'),
        ),
        const PopupMenuItem<String>(
          value: _customerMenuValue,
          child: Text('Customer Node'),
        ),
        const PopupMenuItem<String>(
          value: _partsOfferMenuValue,
          child: Text('Parts Offer Node'),
        ),
        const PopupMenuItem<String>(
          value: _partsOrderMenuValue,
          child: Text('Parts Order Node'),
        ),
        const PopupMenuItem<String>(
          value: _aiTextMenuValue,
          child: Text('AI Text Node'),
        ),
        const PopupMenuItem<String>(
          value: _saveEmailDraftMenuValue,
          child: Text('Save Email Draft Node'),
        ),
        ..._nodeTypes.map(
          (nodeType) => PopupMenuItem<String>(
            value: nodeType.id,
            child: Text('${nodeType.name} (${nodeType.category})'),
          ),
        ),
      ],
    );

    if (selectedType == null) {
      return;
    }

    if (selectedType == _helloWorldMenuValue) {
      final helloWorldName = _nextUniqueNodeName('Hello World');
      _nodeController.addNode(
        _helloWorldNode(context, name: helloWorldName),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: helloWorldName,
        typeName: 'Hello World',
        category: 'AddFunctions',
        functionLabel: 'hello_world',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _ticketMenuValue) {
      final ticketNodeName = _nextUniqueNodeName('Ticket Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: ticketNodeName,
          typeName: 'Ticket Node',
          category: 'Todos',
          functionLabel: 'create_ticket',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: ticketNodeName,
        typeName: 'Ticket Node',
        category: 'Todos',
        functionLabel: 'create_ticket',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'name': 'New Ticket',
          'text': '',
          'department': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _projectPartsMailMenuValue) {
      final nodeName = _nextUniqueNodeName('Project Parts Mail Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Project Parts Mail Node',
          category: 'Information',
          functionLabel: 'send_project_parts_email',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Project Parts Mail Node',
        category: 'Information',
        functionLabel: 'send_project_parts_email',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'recipient_email': '',
          'subject': '',
          'project_id': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _addFolderMenuValue) {
      final nodeName = _nextUniqueNodeName('Add Folder Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Add Folder Node',
          category: 'Information',
          functionLabel: 'add_folder',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
          inputPortName: 'trigger',
          inputPortLabel: 'Trigger In',
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Add Folder Node',
        category: 'Information',
        functionLabel: 'add_folder',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'folder_name': 'New Folder',
          'project_id': '',
          'files': <Map<String, dynamic>>[],
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _fileToTodoMenuValue) {
      final nodeName = _nextUniqueNodeName('File To Todo Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'File To Todo Node',
          category: 'Todos',
          functionLabel: 'file_to_todo',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'File To Todo Node',
        category: 'Todos',
        functionLabel: 'file_to_todo',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'name': 'File Follow-up',
          'department': '',
          'description': '',
          'company_id': '',
          'project_id': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _personMenuValue) {
      final nodeName = _nextUniqueNodeName('Person Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Person Node',
          category: 'Data',
          functionLabel: 'assign_person',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Person Node',
        category: 'Data',
        functionLabel: 'assign_person',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'employee_id': '',
          'employee_label': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _customerMenuValue) {
      final nodeName = _nextUniqueNodeName('Customer Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Customer Node',
          category: 'Data',
          functionLabel: 'assign_customer',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Customer Node',
        category: 'Data',
        functionLabel: 'assign_customer',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'customer_company_id': '',
          'customer_label': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _partsOfferMenuValue) {
      final nodeName = _nextUniqueNodeName('Parts Offer Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Parts Offer Node',
          category: 'Parts',
          functionLabel: 'send_parts_offer_email',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Parts Offer Node',
        category: 'Parts',
        functionLabel: 'send_parts_offer_email',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'items': <Map<String, dynamic>>[],
          'recipient_email': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _partsOrderMenuValue) {
      final nodeName = _nextUniqueNodeName('Parts Order Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Parts Order Node',
          category: 'Parts',
          functionLabel: 'send_parts_order_email',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Parts Order Node',
        category: 'Parts',
        functionLabel: 'send_parts_order_email',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'items': <Map<String, dynamic>>[],
          'department': '',
          'text': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _aiTextMenuValue) {
      final nodeName = _nextUniqueNodeName('AI Text Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'AI Text Node',
          category: 'AI',
          functionLabel: 'ai_text_generate',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'AI Text Node',
        category: 'AI',
        functionLabel: 'ai_text_generate',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'ai_server_name': '',
          'task': '',
          'personality': '',
        },
      );
      _nodeController.notify();
      return;
    }

    if (selectedType == _saveEmailDraftMenuValue) {
      final nodeName = _nextUniqueNodeName('Save Email Draft Node');
      _nodeController.addNode(
        _workflowTypeNode(
          context,
          name: nodeName,
          typeName: 'Save Email Draft Node',
          category: 'Email',
          functionLabel: 'save_email_draft',
          endpointLabel: null,
          triggerInput: _actionButtonTriggerValue,
          position: localPosition,
        ),
        NodePosition.custom(localPosition),
      );
      _registerNodeMetadata(
        name: nodeName,
        typeName: 'Save Email Draft Node',
        category: 'Email',
        functionLabel: 'save_email_draft',
        endpointLabel: null,
        triggerInput: _actionButtonTriggerValue,
        configuration: const <String, dynamic>{
          'recipient_email': '',
          'subject': '',
          'body': '',
        },
      );
      _nodeController.notify();
      return;
    }

    final selectedNodeType = _nodeTypes
        .where((nodeType) => nodeType.id == selectedType)
        .firstOrNull;

    if (selectedNodeType == null) {
      return;
    }

    final newNodeName = _nextUniqueNodeName(selectedNodeType.name);
    _nodeController.addNode(
      _workflowTypeNode(
        context,
        name: newNodeName,
        typeName: selectedNodeType.name,
        category: selectedNodeType.category,
        functionLabel: selectedNodeType.function,
        endpointLabel: selectedNodeType.endpoint,
        triggerInput:
            selectedNodeType.triggerInput ?? _actionButtonTriggerValue,
        position: localPosition,
      ),
      NodePosition.custom(localPosition),
    );
    _registerNodeMetadata(
      name: newNodeName,
      typeName: selectedNodeType.name,
      category: selectedNodeType.category,
      functionLabel: selectedNodeType.function,
      endpointLabel: selectedNodeType.endpoint,
      triggerInput: selectedNodeType.triggerInput ?? _actionButtonTriggerValue,
      configuration: _parseWorkflowNodeConfiguration(
        selectedNodeType.configuration,
      ),
    );
    _nodeController.notify();
  }

  Future<void> _openAddNodeMenuFromButton() async {
    final viewportOffset = _nodeController.getViewportOffset();
    final localPosition = const Offset(280, 180) + viewportOffset;
    await _openAddNodeMenu(
      globalPosition: const Offset(220, 160),
      localPosition: localPosition,
    );
  }

  void _ensureStartNode() {
    if (_isEnsuringStartNode) {
      return;
    }
    if (_nodeController.nodes.containsKey(_actionButtonTriggerNodeName)) {
      return;
    }
    _isEnsuringStartNode = true;
    _nodeController.addNode(
      _startNode(context),
      const NodePosition.custom(Offset(120, 120)),
    );
    _nodeController.notify();
    _isEnsuringStartNode = false;
  }

  String _nextUniqueNodeName(String baseName) {
    if (!_nodeController.nodes.containsKey(baseName)) {
      return baseName;
    }
    var suffix = 2;
    while (_nodeController.nodes.containsKey('$baseName $suffix')) {
      suffix += 1;
    }
    return '$baseName $suffix';
  }

  void _deleteNodeFromWorkflow(String nodeName) {
    if (nodeName == _actionButtonTriggerNodeName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Start node cannot be deleted.')),
      );
      return;
    }

    for (final nodeModel in _nodeController.nodes.values) {
      nodeModel.selected = false;
    }

    final node = _nodeController.nodes[nodeName];
    if (node == null) {
      return;
    }

    node.selected = true;
    _nodeController.deleteSelectedNodes();
    _nodeMetadataByName.remove(nodeName);
    _todoNodeConfigByName.remove(nodeName);
    _ticketNodeConfigByName.remove(nodeName);
    _projectPartsMailConfigByName.remove(nodeName);
    _addFolderNodeConfigByName.remove(nodeName);
    _fileTodoNodeConfigByName.remove(nodeName);
    _nodeController.notify();
  }

  Future<void> _runTriggerTest() async {
    final startNode = _actionButtonTriggerNodeName;
    final adjacency = <String, Set<String>>{};

    for (final connection in _nodeController.connections) {
      final sourceNodeName = connection.outNode.name;
      final targetNodeName = connection.inNode.name;
      final sourcePortName = connection.outPort.name.toLowerCase();
      final targetPortName = connection.inPort.name.toLowerCase();

      final isTriggerEdge =
          sourcePortName.contains('execution') ||
          sourcePortName.contains('trigger') ||
          targetPortName.contains('execution') ||
          targetPortName.contains('trigger');

      if (!isTriggerEdge) {
        continue;
      }

      adjacency
          .putIfAbsent(sourceNodeName, () => <String>{})
          .add(targetNodeName);
    }

    final executed = <String>[];
    final visited = <String>{startNode};
    final queue = <String>[startNode];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final nextNodes = adjacency[current] ?? <String>{};
      for (final next in nextNodes) {
        if (!visited.add(next)) {
          continue;
        }
        executed.add(next);
        queue.add(next);
      }
    }

    for (final nodeModel in _nodeController.nodes.values) {
      nodeModel.selected = false;
    }
    for (final nodeName in <String>[startNode, ...executed]) {
      final node = _nodeController.nodes[nodeName];
      if (node != null) {
        node.selected = true;
      }
    }
    _nodeController.notify();

    if (executed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Trigger fired, but no nodes are connected to the Start trigger.',
          ),
        ),
      );
      return;
    }

    final helloWorldHits = executed
        .where((name) => name.toLowerCase().contains('hello world'))
        .toList();

    final ticketNodes = executed
        .where(
          (name) => _isTicketFunction(_nodeMetadataByName[name]?.functionLabel),
        )
        .toList();

    final projectPartsMailNodes = executed
        .where(
          (name) => _isProjectPartsMailFunction(
            _nodeMetadataByName[name]?.functionLabel,
          ),
        )
        .toList();

    final todoNodes = executed
        .where(
          (name) =>
              _isTodoCategory(_nodeMetadataByName[name]?.category ?? '') &&
              !_isTicketFunction(_nodeMetadataByName[name]?.functionLabel),
        )
        .toList();

    final ticketResults = <String>[];
    if (ticketNodes.isNotEmpty) {
      final api = ref.read(apiClientProvider);
      for (final nodeName in ticketNodes) {
        final config = _ticketNodeConfigByName[nodeName];
        if (config == null) {
          ticketResults.add('$nodeName: skipped (no Ticket configuration)');
          continue;
        }

        final ticketName = config.name.trim().isEmpty ? nodeName : config.name;
        final requestedDepartment = config.department.trim();
        final requestedCompanyId = config.companyId.trim();
        final requestedProjectId = config.projectId.trim();
        final requestedFolderId = config.folderId.trim();

        if (requestedDepartment.isEmpty) {
          ticketResults.add('$nodeName: skipped (department missing)');
          continue;
        }

        try {
          await api.createTodo(
            name: ticketName,
            companyId: requestedCompanyId.isEmpty
                ? await _resolveCompanyId()
                : requestedCompanyId,
            projectId: requestedProjectId.isEmpty ? null : requestedProjectId,
            folderId: requestedFolderId.isEmpty ? null : requestedFolderId,
            department: requestedDepartment,
            description: config.text.trim().isEmpty ? null : config.text,
          );
          ticketResults.add(
            '$nodeName: Ticket sent to department "$requestedDepartment"',
          );
        } catch (error) {
          ticketResults.add('$nodeName: failed ($error)');
        }
      }
    }

    final mailResults = <String>[];
    for (final nodeName in projectPartsMailNodes) {
      final config = _projectPartsMailConfigByName[nodeName];
      if (config == null) {
        mailResults.add('$nodeName: skipped (no mail configuration)');
        continue;
      }
      if (config.recipientEmail.trim().isEmpty) {
        mailResults.add('$nodeName: skipped (recipient email missing)');
        continue;
      }
      final targetProject = config.projectId.trim();
      mailResults.add(
        '$nodeName: Mail node ready (recipient ${config.recipientEmail}, project ${targetProject.isEmpty ? 'from runtime trigger' : targetProject})',
      );
    }

    final todoResults = <String>[];
    if (todoNodes.isNotEmpty) {
      final api = ref.read(apiClientProvider);
      for (final nodeName in todoNodes) {
        final config = _todoNodeConfigByName[nodeName];
        if (config == null) {
          todoResults.add('$nodeName: skipped (no Todo configuration)');
          continue;
        }

        final todoName = config.name.trim().isEmpty ? nodeName : config.name;
        final requestedDepartment = config.department.trim();
        final requestedMainEmployer = config.mainEmployer.trim();
        final requestedCompanyId = config.companyId.trim();
        final requestedProjectId = config.projectId.trim();
        final requestedFolderId = config.folderId.trim();

        try {
          if (config.assigneeType == _TodoAssigneeType.department) {
            if (requestedDepartment.isEmpty) {
              todoResults.add('$nodeName: skipped (department missing)');
              continue;
            }
            await api.createTodo(
              name: todoName,
              companyId: requestedCompanyId.isEmpty
                  ? await _resolveCompanyId()
                  : requestedCompanyId,
              projectId: requestedProjectId.isEmpty ? null : requestedProjectId,
              folderId: requestedFolderId.isEmpty ? null : requestedFolderId,
              department: requestedDepartment,
              description: config.description.trim().isEmpty
                  ? null
                  : config.description,
              startDate: _dateToApiString(config.startDate),
              endDate: _dateToApiString(config.endDate),
              projectStatus: config.projectStatus,
              coworkerLogins: config.coworkerLogins,
            );
            todoResults.add(
              '$nodeName: Todo sent to department "$requestedDepartment"',
            );
          } else {
            if (requestedMainEmployer.isEmpty) {
              todoResults.add('$nodeName: skipped (person missing)');
              continue;
            }

            await api.createTodo(
              name: todoName,
              companyId: requestedCompanyId.isEmpty
                  ? await _resolveCompanyId()
                  : requestedCompanyId,
              projectId: requestedProjectId.isEmpty ? null : requestedProjectId,
              folderId: requestedFolderId.isEmpty ? null : requestedFolderId,
              mainEmployer: requestedMainEmployer,
              coworkerLogins: config.coworkerLogins,
              description: config.description.trim().isEmpty
                  ? null
                  : config.description,
              startDate: _dateToApiString(config.startDate),
              endDate: _dateToApiString(config.endDate),
              projectStatus: config.projectStatus,
            );
            todoResults.add(
              '$nodeName: Todo sent to person "$requestedMainEmployer"',
            );
          }
        } catch (error) {
          todoResults.add('$nodeName: failed ($error)');
        }
      }
    }

    final lines = <String>[
      'Triggered nodes: ${executed.join(' -> ')}',
      if (helloWorldHits.isNotEmpty)
        ...helloWorldHits.map((name) => '$name output: Hello World'),
      if (ticketResults.isNotEmpty) ...ticketResults,
      if (mailResults.isNotEmpty) ...mailResults,
      if (todoResults.isNotEmpty) ...todoResults,
    ];

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(lines.join(' | '))));
  }

  NodeWidgetBase _startNode(BuildContext context) {
    const accentColor = Color(0xFFF5A623); // matches hello_world/trigger accent
    return TitleBarNodeWidget(
      name: _actionButtonTriggerNodeName,
      typeName: 'Action Button Trigger',
      width: 320,
      radius: 14,
      icon: const Icon(Icons.flag_circle, color: Colors.white),
      title: Text(
        _actionButtonTriggerNodeName,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      titleBarColor: accentColor,
      backgroundColor: const Color(0xFF20242C),
      selectedBorder: Border.all(color: accentColor, width: 2.5),
      contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Start',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Triggers when the workflow button is clicked.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TapPortTarget(
                  portName: 'execution',
                  isOutput: true,
                  child: OutPortWidget(
                    name: 'execution',
                    icon: const Icon(
                      Icons.circle,
                      color: accentColor,
                      size: 16,
                    ),
                    iconConnected: const Icon(
                      Icons.circle,
                      color: accentColor,
                      size: 16,
                    ),
                    multiConnections: true,
                    connectionTheme: ConnectionTheme(
                      color: accentColor,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sends: execution start',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _runTriggerTest,
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Test Trigger'),
            ),
          ),
        ],
      ),
    );
  }

  NodeWidgetBase _helloWorldNode(BuildContext context, {required String name}) {
    return _workflowTypeNode(
      context,
      name: name,
      typeName: 'Hello World',
      category: 'AddFunctions',
      functionLabel: 'hello_world',
      endpointLabel: null,
      triggerInput: _actionButtonTriggerValue,
      position: const Offset(420, 120),
      inputPortName: 'trigger',
      inputPortLabel: 'Trigger In',
      enableBodyDrag: true,
    );
  }

  NodeWidgetBase _workflowTypeNode(
    BuildContext context, {
    required String name,
    required String typeName,
    required String category,
    required String? functionLabel,
    required String? endpointLabel,
    required String triggerInput,
    required Offset position,
    String inputPortName = 'trigger',
    String inputPortLabel = 'Trigger In',
    bool enableBodyDrag = true,
  }) {
    final todoConfig = _todoNodeConfigByName[name];
    final ticketConfig = _ticketNodeConfigByName[name];
    final mailConfig = _projectPartsMailConfigByName[name];
    final addFolderConfig = _addFolderNodeConfigByName[name];
    final fileTodoConfig = _fileTodoNodeConfigByName[name];
    final personConfig = _personNodeConfigByName[name];
    final customerConfig = _customerNodeConfigByName[name];
    final partsOfferConfig = _partsOfferNodeConfigByName[name];
    final partsOrderConfig = _partsOrderNodeConfigByName[name];
    final aiTextConfig = _aiTextNodeConfigByName[name];
    final saveEmailDraftConfig = _saveEmailDraftNodeConfigByName[name];
    final isTicketNode = _isTicketFunction(functionLabel);
    final isProjectPartsMailNode = _isProjectPartsMailFunction(functionLabel);
    final isAddFolderNode = _isAddFolderFunction(functionLabel);
    final isFileToTodoNode = _isFileToTodoFunction(functionLabel);
    final isPersonNode = _isPersonFunction(functionLabel);
    final isCustomerNode = _isCustomerFunction(functionLabel);
    final isPartsOfferNode = _isPartsOfferFunction(functionLabel);
    final isPartsOrderNode = _isPartsOrderFunction(functionLabel);
    final isAiTextNode = _isAiTextFunction(functionLabel);
    final isSaveEmailDraftNode = _isSaveEmailDraftFunction(functionLabel);
    final isTodoNode =
        _isTodoCategory(category) && !isTicketNode && !isFileToTodoNode;

    final ioLabels = _portLabelsFor(
      functionLabel: functionLabel,
      category: category,
      isAddFolderNode: isAddFolderNode,
    );
    final accentColor = _categoryAccentColor(
      functionLabel: functionLabel,
      category: category,
    );
    final accentIcon = _categoryIcon(
      functionLabel: functionLabel,
      category: category,
    );

    final middleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      category,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if ((functionLabel ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        functionLabel!,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _deleteNodeFromWorkflow(name),
              tooltip: 'Delete node from workflow',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        if ((endpointLabel ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Endpoint: $endpointLabel',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Trigger input: $triggerInput',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        if (isTicketNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ticket Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Name: ${(ticketConfig?.name.trim().isNotEmpty ?? false) ? ticketConfig!.name : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Department: ${ticketConfig?.department.trim().isNotEmpty == true ? ticketConfig!.department : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Text: ${ticketConfig?.text.trim().isNotEmpty == true ? ticketConfig!.text : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openTicketNodeEditor(name),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Ticket'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isProjectPartsMailNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Project Parts Mail Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Recipient: ${mailConfig?.recipientEmail.trim().isNotEmpty == true ? mailConfig!.recipientEmail : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Subject: ${mailConfig?.subject.trim().isNotEmpty == true ? mailConfig!.subject : 'Auto'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Project ID: ${mailConfig?.projectId.trim().isNotEmpty == true ? mailConfig!.projectId : 'Runtime Trigger Project'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openProjectPartsMailNodeEditor(name),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Mail Node'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _sendGoogleTestMailForNode(name),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Test Google Mail senden'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isAddFolderNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Folder Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Folder: ${addFolderConfig?.folderName.trim().isNotEmpty == true ? addFolderConfig!.folderName : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Project ID: ${addFolderConfig?.projectId.trim().isNotEmpty == true ? addFolderConfig!.projectId : 'Runtime Trigger Project'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Files: ${addFolderConfig?.files.length ?? 0}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openAddFolderNodeEditor(name),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Edit Folder Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isFileToTodoNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File To Todo Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Title Prefix: ${fileTodoConfig?.name.trim().isNotEmpty == true ? fileTodoConfig!.name : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Department: ${fileTodoConfig?.department.trim().isNotEmpty == true ? fileTodoConfig!.department : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openFileTodoNodeEditor(name),
                      icon: const Icon(Icons.task_outlined),
                      label: const Text('Edit File Todo Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isPersonNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Person Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Employee: ${personConfig?.employeeLabel.trim().isNotEmpty == true ? personConfig!.employeeLabel : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openPersonNodeEditor(name),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Edit Person Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isCustomerNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Customer: ${customerConfig?.customerLabel.trim().isNotEmpty == true ? customerConfig!.customerLabel : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openCustomerNodeEditor(name),
                      icon: const Icon(Icons.business_outlined),
                      label: const Text('Edit Customer Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isPartsOfferNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parts Offer Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Parts: ${partsOfferConfig?.items.isNotEmpty == true ? partsOfferConfig!.items.length : 0} selected',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Recipient: ${partsOfferConfig?.recipientEmail.trim().isNotEmpty == true ? partsOfferConfig!.recipientEmail : 'Inherited / not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openPartsOfferNodeEditor(name),
                      icon: const Icon(Icons.local_offer_outlined),
                      label: const Text('Edit Parts Offer Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isPartsOrderNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parts Order Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Parts: ${partsOrderConfig?.items.isNotEmpty == true ? partsOrderConfig!.items.length : 0} selected',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Department: ${partsOrderConfig?.department.trim().isNotEmpty == true ? partsOrderConfig!.department : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openPartsOrderNodeEditor(name),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Edit Parts Order Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isAiTextNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Text Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Server: ${aiTextConfig?.aiServerName.trim().isNotEmpty == true ? aiTextConfig!.aiServerName : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Task: ${aiTextConfig?.task.trim().isNotEmpty == true ? aiTextConfig!.task : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openAiTextNodeEditor(name),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Edit AI Text Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isSaveEmailDraftNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save Email Draft Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Subject: ${saveEmailDraftConfig?.subject.trim().isNotEmpty == true ? saveEmailDraftConfig!.subject : 'Inherits AI Text (if any)'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Recipient: ${saveEmailDraftConfig?.recipientEmail.trim().isNotEmpty == true ? saveEmailDraftConfig!.recipientEmail : 'Inherited / not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openSaveEmailDraftNodeEditor(name),
                      icon: const Icon(Icons.drafts_outlined),
                      label: const Text('Edit Save Email Draft Node'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isTodoNode) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Todo Config',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Name: ${(todoConfig?.name.trim().isNotEmpty ?? false) ? todoConfig!.name : 'Not set'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'Assignee: ${todoConfig == null ? 'Not set' : (todoConfig.assigneeType == _TodoAssigneeType.department ? 'Department' : 'Person')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  if (todoConfig?.assigneeType == _TodoAssigneeType.department)
                    Text(
                      'Department: ${todoConfig?.department.trim().isNotEmpty == true ? todoConfig!.department : 'Not set'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    )
                  else
                    Text(
                      'Person: ${todoConfig?.mainEmployer.trim().isNotEmpty == true ? todoConfig!.mainEmployer : 'Not set'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  Text(
                    'Start: ${todoConfig == null ? 'Not set' : _dateLabel(todoConfig.startDate)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    'End: ${todoConfig == null ? 'Not set' : _dateLabel(todoConfig.endDate)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openTodoNodeEditor(name),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Todo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );

    final leftPortsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: ioLabels.inputDescription,
          waitDuration: const Duration(milliseconds: 300),
          child: _TapPortTarget(
            portName: inputPortName,
            isOutput: false,
            child: InPortWidget(
              name: inputPortName,
              onConnect: (String _, String _) => true,
              icon: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white70,
                size: 18,
              ),
              iconConnected: Icon(
                Icons.arrow_forward_rounded,
                color: accentColor,
                size: 18,
              ),
              multiConnections: false,
              connectionTheme: ConnectionTheme(
                color: accentColor,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 132,
          child: Text(
            inputPortLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 132,
          child: Text(
            ioLabels.inputDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white60,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );

    final rightPortsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Tooltip(
          message: ioLabels.outputDescription,
          waitDuration: const Duration(milliseconds: 300),
          child: _TapPortTarget(
            portName: 'execution',
            isOutput: true,
            child: OutPortWidget(
              name: 'execution',
              icon: Icon(Icons.circle, color: accentColor, size: 16),
              iconConnected: Icon(Icons.circle, color: accentColor, size: 16),
              multiConnections: true,
              connectionTheme: ConnectionTheme(
                color: accentColor,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 150,
          child: Text(
            'Output',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 150,
          child: Text(
            ioLabels.outputDescription,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white60,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
        if (isAddFolderNode)
          ...((addFolderConfig?.files ?? const <_FolderFileSpec>[]).map(
            (file) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'File output: ${file.name}',
                    waitDuration: const Duration(milliseconds: 300),
                    child: _TapPortTarget(
                      portName: _filePortName(file.name),
                      isOutput: true,
                      child: OutPortWidget(
                        name: _filePortName(file.name),
                        icon: Icon(
                          Icons.insert_drive_file_outlined,
                          color: accentColor,
                          size: 16,
                        ),
                        iconConnected: Icon(
                          Icons.insert_drive_file,
                          color: accentColor,
                          size: 16,
                        ),
                        multiConnections: true,
                        connectionTheme: ConnectionTheme(
                          color: accentColor,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 150,
                    child: Text(
                      'File: ${file.name}',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
      ],
    );

    final nodeBody = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leftPortsColumn,
        const SizedBox(width: 14),
        Expanded(child: middleContent),
        const SizedBox(width: 14),
        rightPortsColumn,
      ],
    );

    return TitleBarNodeWidget(
      name: name,
      typeName: typeName,
      width: 500,
      radius: 14,
      icon: Icon(accentIcon, color: Colors.white),
      title: Text(
        name,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      titleBarColor: accentColor,
      backgroundColor: const Color(0xFF20242C),
      selectedBorder: Border.all(color: accentColor, width: 2.5),
      contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: enableBodyDrag
          ? _NodeBodyDragRegion(nodeName: name, child: nodeBody)
          : nodeBody,
    );
  }

  Future<void> _onCanvasSecondaryTapDown(TapDownDetails details) async {
    final localPosition =
        details.localPosition + _nodeController.getViewportOffset();
    await _openAddNodeMenu(
      globalPosition: details.globalPosition,
      localPosition: localPosition,
    );
  }

  Future<void> _saveNodeGraph() async {
    if (_isSavingGraph) {
      return;
    }

    setState(() {
      _isSavingGraph = true;
    });

    try {
      final graph = await serializeGraph();
      final nodeGraph = jsonEncode(graph);
      final api = ref.read(apiClientProvider);

      String? targetActionId = widget.initialActionId?.trim();
      String? targetActionName = widget.initialActionName?.trim();

      if (targetActionId == null || targetActionId.isEmpty) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(nodeGraph);
        return;
      }

      await api.updateProjectAction(
        buttonId: targetActionId,
        nodeGraph: nodeGraph,
      );

      if (!mounted) {
        return;
      }

      ref.invalidate(projectActionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Node graph saved${(targetActionName ?? '').isEmpty ? '' : ' to "$targetActionName"'}.',
          ),
        ),
      );
      Navigator.of(context).pop(nodeGraph);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save node graph: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingGraph = false;
        });
      }
    }
  }

  // Serialize the node graph including nodes and connections
  Future<Map<String, dynamic>> serializeGraph() async {
    final nodes = _nodeController.nodes;
    final connections = _nodeController.connections;

    dynamic readProp(dynamic object, String propertyName) {
      if (object == null) {
        return null;
      }
      if (object is Map<String, dynamic>) {
        return object[propertyName];
      }
      try {
        final dynamic dynamicObject = object;
        switch (propertyName) {
          case 'id':
            return dynamicObject.id;
          case 'name':
            return dynamicObject.name;
          case 'type':
            return dynamicObject.type;
          case 'position':
            // NodeModel (node_editor package) exposes the canvas position
            // as `pos`, not `position` — this must match that field name
            // or every node silently serializes to (0, 0).
            return dynamicObject.pos;
          case 'size':
            return dynamicObject.size;
          case 'inputs':
            // NodeModel has no `inputs`/`outputs` fields, only a combined
            // `ports` map — split it by runtime type (InPort/OutPort are
            // not exported by node_editor, so this can't be a static `is`).
            return (dynamicObject.ports as Map).values.where(
              (port) => port.runtimeType.toString() == 'InPort',
            );
          case 'outputs':
            return (dynamicObject.ports as Map).values.where(
              (port) => port.runtimeType.toString() == 'OutPort',
            );
          case 'multiConnections':
            return dynamicObject.multiConnections;
          case 'sourceNodeId':
            return dynamicObject.sourceNodeId;
          case 'sourcePortId':
            return dynamicObject.sourcePortId;
          case 'targetNodeId':
            return dynamicObject.targetNodeId;
          case 'targetPortId':
            return dynamicObject.targetPortId;
          case 'sourceNode':
            return dynamicObject.sourceNode;
          case 'sourcePort':
            return dynamicObject.sourcePort;
          case 'targetNode':
            return dynamicObject.targetNode;
          case 'targetPort':
            return dynamicObject.targetPort;
          case 'outNode':
            return dynamicObject.outNode;
          case 'outPort':
            return dynamicObject.outPort;
          case 'inNode':
            return dynamicObject.inNode;
          case 'inPort':
            return dynamicObject.inPort;
          case 'dx':
            return dynamicObject.dx;
          case 'dy':
            return dynamicObject.dy;
          default:
            return null;
        }
      } catch (_) {
        return null;
      }
    }

    // Create a serializable representation of nodes
    final nodeData = <Map<String, dynamic>>[];

    // Handle different possible node formats (map vs list)
    for (final entry in nodes.entries) {
      final node = entry.value;
      final nodeId = entry.key;
      final nodePosition = readProp(node, 'position');
      final nodeSize = readProp(node, 'size');
      final inputPorts =
          (readProp(node, 'inputs') as Iterable<dynamic>?) ?? const <dynamic>[];
      final outputPorts =
          (readProp(node, 'outputs') as Iterable<dynamic>?) ??
          const <dynamic>[];

      nodeData.add({
        'id': nodeId,
        'name': readProp(node, 'name') ?? 'node_$nodeId',
        'type': readProp(node, 'type') ?? 'workflow_node',
        'runtime_metadata': _nodeMetadataByName[nodeId]?.toMap(),
        if (_todoNodeConfigByName.containsKey(nodeId))
          'todo_config': _todoNodeConfigByName[nodeId]?.toMap(),
        if (_ticketNodeConfigByName.containsKey(nodeId))
          'ticket_config': _ticketNodeConfigByName[nodeId]?.toMap(),
        if (_projectPartsMailConfigByName.containsKey(nodeId))
          'mail_parts_config': _projectPartsMailConfigByName[nodeId]?.toMap(),
        if (_addFolderNodeConfigByName.containsKey(nodeId))
          'folder_files_config': _addFolderNodeConfigByName[nodeId]?.toMap(),
        if (_fileTodoNodeConfigByName.containsKey(nodeId))
          'file_todo_config': _fileTodoNodeConfigByName[nodeId]?.toMap(),
          'person_config': _personNodeConfigByName[nodeId]?.toMap(),
          'customer_config': _customerNodeConfigByName[nodeId]?.toMap(),
          'parts_offer_config': _partsOfferNodeConfigByName[nodeId]?.toMap(),
          'parts_order_config': _partsOrderNodeConfigByName[nodeId]?.toMap(),
          'ai_text_config': _aiTextNodeConfigByName[nodeId]?.toMap(),
          'save_email_draft_config':
              _saveEmailDraftNodeConfigByName[nodeId]?.toMap(),
        'position': {
          'x':
              (readProp(nodePosition, 'dx') ?? readProp(nodePosition, 'x') ?? 0)
                  .toDouble(),
          'y':
              (readProp(nodePosition, 'dy') ?? readProp(nodePosition, 'y') ?? 0)
                  .toDouble(),
        },
        'size': {
          'width': (readProp(nodeSize, 'width') ?? 0).toDouble(),
          'height': (readProp(nodeSize, 'height') ?? 0).toDouble(),
        },
        'inputs': inputPorts
            .map(
              (input) => {
                'id': readProp(input, 'id') ?? '',
                'name': readProp(input, 'name') ?? '',
                'type': readProp(input, 'type') ?? '',
                'multiConnections':
                    (readProp(input, 'multiConnections') as bool?) ?? false,
              },
            )
            .toList(),
        'outputs': outputPorts
            .map(
              (output) => {
                'id': readProp(output, 'id') ?? '',
                'name': readProp(output, 'name') ?? '',
                'type': readProp(output, 'type') ?? '',
                'multiConnections':
                    (readProp(output, 'multiConnections') as bool?) ?? false,
              },
            )
            .toList(),
      });
    }

    // Create a serializable representation of connections
    final connectionData = <Map<String, dynamic>>[];

    // Handle different possible connection formats (map vs list)
    for (final conn in connections) {
      try {
        final sourceNode =
            readProp(conn, 'outNode') ?? readProp(conn, 'sourceNode');
        final targetNode =
            readProp(conn, 'inNode') ?? readProp(conn, 'targetNode');
        final sourcePort =
            readProp(conn, 'outPort') ?? readProp(conn, 'sourcePort');
        final targetPort =
            readProp(conn, 'inPort') ?? readProp(conn, 'targetPort');

        // Try to access the properties directly
        connectionData.add({
          'id': readProp(conn, 'id') ?? 'unknown',
          'sourceNodeId':
              readProp(conn, 'sourceNodeId') ??
              readProp(sourceNode, 'name') ??
              readProp(conn, 'sourceNode') ??
              'unknown',
          'sourcePortId':
              readProp(conn, 'sourcePortId') ??
              readProp(sourcePort, 'name') ??
              readProp(conn, 'sourcePort') ??
              'unknown',
          'targetNodeId':
              readProp(conn, 'targetNodeId') ??
              readProp(targetNode, 'name') ??
              readProp(conn, 'targetNode') ??
              'unknown',
          'targetPortId':
              readProp(conn, 'targetPortId') ??
              readProp(targetPort, 'name') ??
              readProp(conn, 'targetPort') ??
              'unknown',
          'sourceOutputId':
              readProp(sourcePort, 'name') ??
              readProp(conn, 'sourcePortId') ??
              'unknown',
          'targetInputId':
              readProp(targetPort, 'name') ??
              readProp(conn, 'targetPortId') ??
              'unknown',
        });
      } catch (e) {
        // Fallback if properties don't exist
        connectionData.add({
          'id': readProp(conn, 'id') ?? 'unknown',
          'sourceNodeId': 'unknown',
          'sourcePortId': 'unknown',
          'targetNodeId': 'unknown',
          'targetPortId': 'unknown',
        });
      }
    }

    return {'nodes': nodeData, 'connections': connectionData};
  }

  @override
  void dispose() {
    _nodeController.removeListener(_ensureStartNode);
    _nodeFocus.dispose();
    _nodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.translate('nodeEditor') ?? 'Node Editor'),
        actions: [
          IconButton(
            onPressed: _isSavingGraph ? null : _saveNodeGraph,
            tooltip: _isSavingGraph ? 'Saving...' : 'Save Workflow',
            icon: _isSavingGraph
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(
            onPressed: _isLoadingNodeTypes ? null : _loadNodeTypes,
            tooltip: 'Refresh Node Types',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _openAddNodeMenuFromButton,
            tooltip: 'Add Node',
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            onPressed: _openWorkflowNodeCreator,
            tooltip: 'Create Node Type',
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  event.buttons == kSecondaryMouseButton) {
                _onCanvasSecondaryTapDown(
                  TapDownDetails(
                    globalPosition: event.position,
                    localPosition: event.localPosition,
                  ),
                );
              }
            },
            child: Stack(
              children: [
                NodeEditor(
                  focusNode: _nodeFocus,
                  controller: _nodeController,
                  background: const GridBackground(),
                  infiniteCanvasSize: 5000,
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Use Add Node or right-click',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _openAddNodeMenuFromButton,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Node'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NodePortLabels {
  const _NodePortLabels({
    required this.inputDescription,
    required this.outputDescription,
  });

  final String inputDescription;
  final String outputDescription;
}

class _NodeBodyDragRegion extends StatelessWidget {
  final String nodeName;
  final Widget child;

  const _NodeBodyDragRegion({required this.nodeName, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) {
        final controller = ControllerInheritedWidget.of(context).controller;
        controller.moveNodePosition(nodeName, details.delta);
      },
      child: child,
    );
  }
}

class _TapPortTarget extends StatelessWidget {
  const _TapPortTarget({
    required this.portName,
    required this.child,
    required this.isOutput,
  });

  final String portName;
  final Widget child;
  final bool isOutput;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final controller = ControllerInheritedWidget.of(context).controller;
        final node = NodeEditorInheritedWidget.of(context);

        if (isOutput) {
          controller.setConnecting(node.blueprintNode.name, portName);
          controller.focusNode.requestFocus();
        } else {
          controller.addConnectionByTap(
            inNode: node.blueprintNode.name,
            inPort: portName,
          );
          controller.focusNode.requestFocus();
        }
      },
      child: IgnorePointer(child: child),
    );
  }
}

enum _TodoAssigneeType { person, department }

class _NodeRuntimeMetadata {
  const _NodeRuntimeMetadata({
    required this.typeName,
    required this.category,
    required this.functionLabel,
    required this.endpointLabel,
    required this.triggerInput,
  });

  final String typeName;
  final String category;
  final String? functionLabel;
  final String? endpointLabel;
  final String triggerInput;

  Map<String, dynamic> toMap() {
    return {
      'type_name': typeName,
      'category': category,
      'function': functionLabel,
      'endpoint': endpointLabel,
      'trigger_input': triggerInput,
    };
  }
}

class _TodoNodeConfig {
  const _TodoNodeConfig({
    required this.name,
    required this.assigneeType,
    required this.department,
    required this.mainEmployer,
    required this.coworkerLogins,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.projectStatus,
    required this.companyId,
    required this.projectId,
    required this.folderId,
  });

  final String name;
  final _TodoAssigneeType assigneeType;
  final String department;
  final String mainEmployer;
  final List<String> coworkerLogins;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String projectStatus;
  final String companyId;
  final String projectId;
  final String folderId;

  factory _TodoNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    DateTime? parseDate(String key) {
      final raw = readString(key).trim();
      if (raw.isEmpty) {
        return null;
      }
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }

    final rawAssignee = readString('assignee_type').toLowerCase();
    final assigneeType = rawAssignee == 'department'
        ? _TodoAssigneeType.department
        : _TodoAssigneeType.person;

    final coworkerRaw = json['coworker_logins'];
    final coworkers = coworkerRaw is List
        ? coworkerRaw
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];

    return _TodoNodeConfig(
      name: readString('name'),
      assigneeType: assigneeType,
      department: readString('department'),
      mainEmployer: readString('main_employer'),
      coworkerLogins: coworkers,
      description: readString('description'),
      startDate: parseDate('start_date'),
      endDate: parseDate('end_date'),
      projectStatus: readString('project_status').trim().isEmpty
          ? 'inWork'
          : readString('project_status').trim(),
      companyId: readString('company_id'),
      projectId: readString('project_id'),
      folderId: readString('folder_id'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'assignee_type': assigneeType == _TodoAssigneeType.department
          ? 'department'
          : 'person',
      'department': department,
      'main_employer': mainEmployer,
      'coworker_logins': coworkerLogins,
      'description': description,
      'start_date': _dateToJson(startDate),
      'end_date': _dateToJson(endDate),
      'project_status': projectStatus,
      'company_id': companyId,
      'project_id': projectId,
      'folder_id': folderId,
    };
  }

  static String? _dateToJson(DateTime? value) {
    if (value == null) {
      return null;
    }
    final dateOnly = DateTime(value.year, value.month, value.day);
    return dateOnly.toIso8601String().split('T').first;
  }
}

class _TicketNodeConfig {
  const _TicketNodeConfig({
    required this.name,
    required this.text,
    required this.department,
    required this.companyId,
    required this.projectId,
    required this.folderId,
  });

  final String name;
  final String text;
  final String department;
  final String companyId;
  final String projectId;
  final String folderId;

  factory _TicketNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    return _TicketNodeConfig(
      name: readString('name'),
      text: readString('text'),
      department: readString('department'),
      companyId: readString('company_id'),
      projectId: readString('project_id'),
      folderId: readString('folder_id'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'text': text,
      'department': department,
      'company_id': companyId,
      'project_id': projectId,
      'folder_id': folderId,
    };
  }
}

class _ProjectPartsMailNodeConfig {
  const _ProjectPartsMailNodeConfig({
    required this.recipientEmail,
    required this.subject,
    required this.projectId,
  });

  final String recipientEmail;
  final String subject;
  final String projectId;

  factory _ProjectPartsMailNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    return _ProjectPartsMailNodeConfig(
      recipientEmail: readString('recipient_email'),
      subject: readString('subject'),
      projectId: readString('project_id'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recipient_email': recipientEmail,
      'subject': subject,
      'project_id': projectId,
    };
  }
}

class _FolderFileSpec {
  const _FolderFileSpec({
    required this.name,
    required this.content,
    this.bytesBase64,
    this.mimeType,
  });

  final String name;
  final String content;
  final String? bytesBase64;
  final String? mimeType;

  factory _FolderFileSpec.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    return _FolderFileSpec(
      name: readString('name'),
      content: readString('content'),
      bytesBase64: readString('bytes_base64').trim().isEmpty
          ? null
          : readString('bytes_base64').trim(),
      mimeType: readString('mime_type').trim().isEmpty
          ? null
          : readString('mime_type').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'content': content,
      if (bytesBase64 != null && bytesBase64!.isNotEmpty)
        'bytes_base64': bytesBase64,
      if (mimeType != null && mimeType!.isNotEmpty) 'mime_type': mimeType,
    };
  }
}

class _AddFolderNodeConfig {
  const _AddFolderNodeConfig({
    required this.folderName,
    required this.projectId,
    required this.files,
  });

  final String folderName;
  final String projectId;
  final List<_FolderFileSpec> files;

  factory _AddFolderNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    final rawFiles = json['files'];
    final files = <_FolderFileSpec>[];
    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map<String, dynamic>) {
          final parsed = _FolderFileSpec.fromMap(item);
          if (parsed.name.trim().isNotEmpty) {
            files.add(parsed);
          }
        } else if (item is Map) {
          final parsed = _FolderFileSpec.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (parsed.name.trim().isNotEmpty) {
            files.add(parsed);
          }
        } else if (item is String && item.trim().isNotEmpty) {
          files.add(_FolderFileSpec(name: item.trim(), content: ''));
        }
      }
    }

    return _AddFolderNodeConfig(
      folderName: readString('folder_name'),
      projectId: readString('project_id'),
      files: files,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'folder_name': folderName,
      'project_id': projectId,
      'files': files.map((file) => file.toMap()).toList(),
    };
  }
}

class _FileTodoNodeConfig {
  const _FileTodoNodeConfig({
    required this.name,
    required this.department,
    required this.description,
    required this.companyId,
    required this.projectId,
  });

  final String name;
  final String department;
  final String description;
  final String companyId;
  final String projectId;

  factory _FileTodoNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) {
        return value;
      }
      return '';
    }

    return _FileTodoNodeConfig(
      name: readString('name'),
      department: readString('department'),
      description: readString('description'),
      companyId: readString('company_id'),
      projectId: readString('project_id'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'department': department,
      'description': description,
      'company_id': companyId,
      'project_id': projectId,
    };
  }
}

class _PersonNodeConfig {
  const _PersonNodeConfig({
    required this.employeeId,
    required this.employeeLabel,
  });

  final String employeeId;
  final String employeeLabel;

  factory _PersonNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _PersonNodeConfig(
      employeeId: readString('employee_id'),
      employeeLabel: readString('employee_label'),
    );
  }

  Map<String, dynamic> toMap() {
    return {'employee_id': employeeId, 'employee_label': employeeLabel};
  }
}

class _CustomerNodeConfig {
  const _CustomerNodeConfig({
    required this.customerCompanyId,
    required this.customerLabel,
  });

  final String customerCompanyId;
  final String customerLabel;

  factory _CustomerNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _CustomerNodeConfig(
      customerCompanyId: readString('customer_company_id'),
      customerLabel: readString('customer_label'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customer_company_id': customerCompanyId,
      'customer_label': customerLabel,
    };
  }
}

/// A single selected part row, reused by both the Parts Offer node
/// (one email per part, each with its own note) and the Parts Order node
/// (one combined email listing every selected part).
class _PartSelectionEntry {
  const _PartSelectionEntry({
    required this.partId,
    required this.partName,
    this.note = '',
  });

  final String partId;
  final String partName;
  final String note;

  factory _PartSelectionEntry.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _PartSelectionEntry(
      partId: readString('part_id'),
      partName: readString('part_name'),
      note: readString('note'),
    );
  }

  Map<String, dynamic> toMap() {
    return {'part_id': partId, 'part_name': partName, 'note': note};
  }
}

List<_PartSelectionEntry> _partSelectionListFromJson(dynamic raw) {
  if (raw is! List) {
    return const <_PartSelectionEntry>[];
  }
  final entries = <_PartSelectionEntry>[];
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      entries.add(_PartSelectionEntry.fromMap(item));
    } else if (item is Map) {
      entries.add(
        _PartSelectionEntry.fromMap(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
  }
  return entries;
}

class _PartsOfferNodeConfig {
  const _PartsOfferNodeConfig({
    required this.items,
    required this.recipientEmail,
  });

  final List<_PartSelectionEntry> items;
  final String recipientEmail;

  factory _PartsOfferNodeConfig.fromMap(Map<String, dynamic> json) {
    final value = json['recipient_email'];
    return _PartsOfferNodeConfig(
      items: _partSelectionListFromJson(json['items']),
      recipientEmail: value is String ? value : '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((item) => item.toMap()).toList(),
      'recipient_email': recipientEmail,
    };
  }
}

class _PartsOrderNodeConfig {
  const _PartsOrderNodeConfig({
    required this.items,
    required this.department,
    required this.text,
  });

  final List<_PartSelectionEntry> items;
  final String department;
  final String text;

  factory _PartsOrderNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _PartsOrderNodeConfig(
      items: _partSelectionListFromJson(json['items']),
      department: readString('department'),
      text: readString('text'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((item) => item.toMap()).toList(),
      'department': department,
      'text': text,
    };
  }
}

class _AiTextNodeConfig {
  const _AiTextNodeConfig({
    required this.aiServerName,
    required this.task,
    required this.personality,
  });

  final String aiServerName;
  final String task;
  final String personality;

  factory _AiTextNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _AiTextNodeConfig(
      aiServerName: readString('ai_server_name'),
      task: readString('task'),
      personality: readString('personality'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ai_server_name': aiServerName,
      'task': task,
      'personality': personality,
    };
  }
}

class _SaveEmailDraftNodeConfig {
  const _SaveEmailDraftNodeConfig({
    required this.recipientEmail,
    required this.subject,
    required this.body,
  });

  final String recipientEmail;
  final String subject;
  final String body;

  factory _SaveEmailDraftNodeConfig.fromMap(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return _SaveEmailDraftNodeConfig(
      recipientEmail: readString('recipient_email'),
      subject: readString('subject'),
      body: readString('body'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recipient_email': recipientEmail,
      'subject': subject,
      'body': body,
    };
  }
}

class WorkflowNodesTab extends ConsumerWidget {
  const WorkflowNodesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final nodesAsync = ref.watch(workflowNodesProvider);

    return nodesAsync.when(
      data: (nodes) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    builder: (context) => const WorkflowNodeDialog(),
                  ).then((saved) {
                    if (saved == true) {
                      ref.invalidate(workflowNodesProvider);
                    }
                  });
                },
                child: Text(
                  L10n.of(context)?.translate('createNew') ?? 'Create New',
                ),
              ),
            ),
            ...nodes.map(
              (node) => WorkflowNodeCard(
                node: node,
                onEdit: () {
                  showDialog<bool>(
                    context: context,
                    builder: (context) => WorkflowNodeDialog(node: node),
                  ).then((saved) {
                    if (saved == true) {
                      ref.invalidate(workflowNodesProvider);
                    }
                  });
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('${l10n?.translate('error') ?? 'Error'}: $error')),
    );
  }
}

class WorkflowNodeCard extends StatelessWidget {
  final WorkflowNodeDto node;
  final VoidCallback onEdit;

  const WorkflowNodeCard({super.key, required this.node, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(node.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(node.category),
            if (node.configuration.isNotEmpty)
              Text(node.configuration, style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                // TODO: Implement delete
              },
            ),
          ],
        ),
      ),
    );
  }
}

class WorkflowNodeDialog extends ConsumerStatefulWidget {
  final WorkflowNodeDto? node;

  const WorkflowNodeDialog({super.key, this.node});

  @override
  ConsumerState<WorkflowNodeDialog> createState() => _WorkflowNodeDialogState();
}

class _WorkflowNodeDialogState extends ConsumerState<WorkflowNodeDialog> {
  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController functionController;
  late TextEditingController endpointController;
  late TextEditingController triggerInputController;
  late TextEditingController configurationController;
  String selectedCategory = 'AddFunctions';
  bool isActive = true;
  bool isSaving = false;
  String? saveError;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.node?.name ?? '');
    descriptionController = TextEditingController(
      text: widget.node?.description ?? '',
    );
    functionController = TextEditingController(
      text: widget.node?.function ?? '',
    );
    endpointController = TextEditingController(
      text: widget.node?.endpoint ?? '',
    );
    triggerInputController = TextEditingController(
      text: widget.node?.triggerInput ?? '',
    );
    configurationController = TextEditingController(
      text: widget.node?.configuration ?? '',
    );
    selectedCategory = widget.node?.category ?? 'AddFunctions';
    isActive = widget.node?.isActive ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    functionController.dispose();
    endpointController.dispose();
    triggerInputController.dispose();
    configurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return AlertDialog(
      title: Text(
        widget.node == null
            ? l10n?.translate('createWorkflowNode') ?? 'Create Workflow Node'
            : l10n?.translate('editWorkflowNode') ?? 'Edit Workflow Node',
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n?.translate('name') ?? 'Name',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedCategory,
                items: [
                  DropdownMenuItem(
                    value: 'AddFunctions',
                    child: Text(
                      l10n?.translate('addFunctions') ?? 'Add Functions',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Information',
                    child: Text(
                      l10n?.translate('information') ?? 'Information',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Todos',
                    child: Text(l10n?.translate('todos') ?? 'Todos'),
                  ),
                  DropdownMenuItem(
                    value: 'AIEntryPoint',
                    child: Text(
                      l10n?.translate('aiEntryPoint') ?? 'AI Entry Point',
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedCategory = value ?? 'AddFunctions';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: functionController,
                decoration: InputDecoration(
                  labelText: l10n?.translate('function') ?? 'Function',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: InputDecoration(
                  labelText: l10n?.translate('endpoint') ?? 'Endpoint',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: triggerInputController,
                decoration: InputDecoration(
                  labelText: l10n?.translate('triggerInput') ?? 'Trigger Input',
                  hintText: 'action_button_pressed',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: configurationController,
                decoration: InputDecoration(
                  labelText:
                      l10n?.translate('configuration') ?? 'Configuration',
                  hintText: '{"key": "value"}',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: l10n?.translate('description') ?? 'Description',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: Text(l10n?.translate('active') ?? 'Active'),
                value: isActive,
                onChanged: (value) {
                  setState(() {
                    isActive = value ?? true;
                  });
                },
              ),
              if (saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    saveError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: Text(l10n?.translate('cancel') ?? 'Cancel'),
        ),
        ElevatedButton(
          onPressed: isSaving
              ? null
              : () async {
                  final api = ref.read(apiClientProvider);
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setState(() {
                      saveError =
                          l10n?.translate('nameRequired') ?? 'Name is required';
                    });
                    return;
                  }

                  setState(() {
                    isSaving = true;
                    saveError = null;
                  });

                  try {
                    if (widget.node == null) {
                      await api.createWorkflowNode(
                        name: name,
                        category: selectedCategory,
                        function: functionController.text.trim().isEmpty
                            ? null
                            : functionController.text.trim(),
                        endpoint: endpointController.text.trim().isEmpty
                            ? null
                            : endpointController.text.trim(),
                        triggerInput: normalizeWorkflowTriggerInput(
                          triggerInputController.text,
                        ),
                        configuration:
                            configurationController.text.trim().isEmpty
                            ? '{}'
                            : configurationController.text.trim(),
                        description: descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
                        isActive: isActive,
                      );
                    } else {
                      await api.updateWorkflowNode(
                        nodeId: widget.node!.id,
                        name: name,
                        category: selectedCategory,
                        function: functionController.text.trim().isEmpty
                            ? null
                            : functionController.text.trim(),
                        endpoint: endpointController.text.trim().isEmpty
                            ? null
                            : endpointController.text.trim(),
                        triggerInput: normalizeWorkflowTriggerInput(
                          triggerInputController.text,
                        ),
                        configuration:
                            configurationController.text.trim().isEmpty
                            ? null
                            : configurationController.text.trim(),
                        description: descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
                        isActive: isActive,
                      );
                    }

                    if (!context.mounted) {
                      return;
                    }

                    Navigator.of(context).pop(true);
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      saveError = 'Error: $error';
                    });
                  } finally {
                    if (mounted) {
                      setState(() {
                        isSaving = false;
                      });
                    }
                  }
                },
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n?.translate('save') ?? 'Save'),
        ),
      ],
    );
  }
}
