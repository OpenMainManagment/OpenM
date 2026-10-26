import 'package:openm/models/workflow/workflow_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../models/dtos.dart';
import 'auth_state.dart';

final dioProvider = Provider<Dio>((ref) {
  final auth = ref.watch(authStateProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
    ),
  );
  if (auth.accessToken != null) {
    dio.options.headers['Authorization'] = 'Bearer ${auth.accessToken}';
  }
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    return response.data['access_token'] as String;
  }

  Future<List<MainCompanyDto>> companies({String? search}) async {
    final response = await _dio.get(
      '/companies',
      queryParameters: {'search': search},
    );
    return (response.data as List<dynamic>)
          .map((item) => MainCompanyDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

        Future<List<ClientCompanyDto>> clientCompanies({String? search}) async {
    final response = await _dio.get(
            '/companies/client-companies',
      queryParameters: {'search': search},
    );
    return (response.data as List<dynamic>)
          .map((item) => ClientCompanyDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  List<Map<String, dynamic>> _companyCustomersPayload(
    List<Map<String, dynamic>> customers,
  ) {
    final payload = <Map<String, dynamic>>[];
    for (final customer in customers) {
      final firstName = (customer['first_name'] as String? ?? '').trim();
      final lastName = (customer['last_name'] as String? ?? '').trim();
      if (firstName.isEmpty && lastName.isEmpty) {
        continue;
      }
      payload.add(
        {
          'first_name': firstName,
          'last_name': lastName,
          'gender': customer['gender'],
          'email': customer['email'],
          'role': customer['role'],
          'phone_number': customer['phone_number'],
          'mobile_number': customer['mobile_number'],
        }..removeWhere((key, value) => value == null || value == ''),
      );
    }
    return payload;
  }

  Future<MainCompanyDto> createCompany({
    required String uniqueName,
    String? logoUrl,
    String? street,
    String? houseNumber,
    String? headOfCompany,
    String? contactEmail,
    String? phoneNumber,
    List<Map<String, dynamic>> customers = const [],
    int? headCustomerIndex,
  }) async {
    final contact = <String, dynamic>{
      'street': street,
      'house_number': houseNumber,
      'head_of_company': headOfCompany,
      'email': contactEmail,
      'phone_number': phoneNumber,
    }..removeWhere((key, value) => value == null);

    final response = await _dio.post(
      '/companies',
      data: {
        'unique_name': uniqueName,
        'logo_url': logoUrl,
        if (contact.isNotEmpty) 'contact': contact,
        if (customers.isNotEmpty)
          'customers': _companyCustomersPayload(customers),
        'head_customer_index': headCustomerIndex,
      },
    );
    return MainCompanyDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ClientCompanyDto> createClientCompany({
    required String uniqueName,
    String? logoUrl,
    String? street,
    String? houseNumber,
    String? headOfCompany,
    String? contactEmail,
    String? phoneNumber,
    List<Map<String, dynamic>> customers = const [],
    int? headCustomerIndex,
  }) async {
    final contact = <String, dynamic>{
      'street': street,
      'house_number': houseNumber,
      'head_of_company': headOfCompany,
      'email': contactEmail,
      'phone_number': phoneNumber,
    }..removeWhere((key, value) => value == null);

    final response = await _dio.post(
      '/companies/client-companies',
      data: {
        'unique_name': uniqueName,
        'logo_url': logoUrl,
        if (contact.isNotEmpty) 'contact': contact,
        if (customers.isNotEmpty)
          'customers': _companyCustomersPayload(customers),
        'head_customer_index': headCustomerIndex,
      },
    );
    return ClientCompanyDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MainCompanyDto> updateCompany({
    required String companyId,
    String? uniqueName,
    String? logoUrl,
    String? street,
    String? houseNumber,
    String? headOfCompany,
    String? contactEmail,
    String? phoneNumber,
    List<Map<String, dynamic>>? customers,
    int? headCustomerIndex,
  }) async {
    final contact = <String, dynamic>{
      'street': street,
      'house_number': houseNumber,
      'head_of_company': headOfCompany,
      'email': contactEmail,
      'phone_number': phoneNumber,
    }..removeWhere((key, value) => value == null);

    final response = await _dio.patch(
      '/companies/$companyId',
      data: {
        'unique_name': uniqueName,
        'logo_url': logoUrl,
        if (contact.isNotEmpty) 'contact': contact,
        if (customers != null) 'customers': _companyCustomersPayload(customers),
        if (customers != null) 'head_customer_index': headCustomerIndex,
      },
    );
    return MainCompanyDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ClientCompanyDto> updateClientCompany({
    required String clientCompanyId,
    String? uniqueName,
    String? logoUrl,
    String? street,
    String? houseNumber,
    String? headOfCompany,
    String? contactEmail,
    String? phoneNumber,
    List<Map<String, dynamic>>? customers,
    int? headCustomerIndex,
  }) async {
    final contact = <String, dynamic>{
      'street': street,
      'house_number': houseNumber,
      'head_of_company': headOfCompany,
      'email': contactEmail,
      'phone_number': phoneNumber,
    }..removeWhere((key, value) => value == null);

    final response = await _dio.patch(
      '/companies/client-companies/$clientCompanyId',
      data: {
        'unique_name': uniqueName,
        'logo_url': logoUrl,
        if (contact.isNotEmpty) 'contact': contact,
        if (customers != null) 'customers': _companyCustomersPayload(customers),
        if (customers != null) 'head_customer_index': headCustomerIndex,
      },
    );
    return ClientCompanyDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ProjectDto>> projectsByMainCompany(
    String mainCompanyId, {
    String? search,
  }) async {
    final response = await _dio.get(
      '/projects',
      queryParameters: {'company_id': mainCompanyId, 'search': search},
    );
    return (response.data as List<dynamic>)
        .map((item) => ProjectDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProjectDto>> projectsByClientCompany(
    String clientCompanyId, {
    String? search,
  }) async {
    final response = await _dio.get(
      '/projects',
      queryParameters: {
        'client_company_id': clientCompanyId,
        'search': search,
      },
    );
    return (response.data as List<dynamic>)
        .map((item) => ProjectDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProjectDto>> projects(String companyId, {String? search}) {
    return projectsByMainCompany(companyId, search: search);
  }

  Future<ProjectDto> createProject({
    required String companyId,
    required String name,
  }) async {
    final response = await _dio.post(
      '/projects',
      data: {'company_id': companyId, 'name': name, 'base_model': 'Normal'},
    );
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectDto> createProjectForClientCompany({
    required String clientCompanyId,
    required String name,
  }) async {
    final response = await _dio.post(
      '/projects',
      data: {
        'client_company_id': clientCompanyId,
        'name': name,
        'base_model': 'Normal',
      },
    );
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectDto> projectById(String projectId) async {
    final response = await _dio.get('/projects/$projectId');
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ProjectGanttStepDto>> projectGanttSteps(String projectId) async {
    final response = await _dio.get('/projects/$projectId/gantt-steps');
    return (response.data as List<dynamic>)
        .map(
          (item) => ProjectGanttStepDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ProjectGanttStartResponseDto> startProjectGantt(
    String projectId,
  ) async {
    final response = await _dio.post('/projects/$projectId/gantt/start');
    return ProjectGanttStartResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Workflow _workflowFromActionButton(Map<String, dynamic> json) {
    final nodeGraph = json['node_graph'];
    final nodeIds = <String>[];
    if (nodeGraph is Map<String, dynamic>) {
      final nodes = nodeGraph['nodes'];
      if (nodes is List<dynamic>) {
        for (final node in nodes) {
          if (node is Map<String, dynamic> && node['id'] is String) {
            nodeIds.add(node['id'] as String);
          }
        }
      }
    }

    return Workflow(
      id: json['id'] as String,
      name: json['unique_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      companyId: json['company_id'] as String? ?? '',
      workflowStage: json['workflow_stage'] as String? ?? 'draft',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      nodeIds: nodeIds.isEmpty ? null : nodeIds,
    );
  }

  Future<List<Workflow>> getWorkflows() async {
    final response = await _dio.get('/api/actions/buttons');
    return (response.data as List<dynamic>)
        .map((item) => _workflowFromActionButton(item as Map<String, dynamic>))
        .toList();
  }

  Future<Workflow> getWorkflow({required String id}) async {
    final response = await _dio.get('/api/actions/buttons/$id');
    return _workflowFromActionButton(response.data as Map<String, dynamic>);
  }

  Future<Workflow> createWorkflow({
    required String uniqueName,
    String? description,
    String nodeGraph = '{}',
    String? workflowStage,
    bool isActive = true,
    List<String> departmentIds = const [],
  }) async {
    final response = await _dio.post(
      '/api/actions/buttons',
      data: {
        'unique_name': uniqueName,
        'description': description,
        'node_graph': nodeGraph,
        'workflow_stage': workflowStage,
        'is_active': isActive,
        'department_ids': departmentIds,
      },
    );
    return _workflowFromActionButton(response.data as Map<String, dynamic>);
  }

  Future<Workflow> updateWorkflow({
    required String workflowId,
    String? uniqueName,
    String? description,
    String? nodeGraph,
    String? workflowStage,
    bool? isActive,
    List<String>? departmentIds,
  }) async {
    final response = await _dio.put(
      '/api/actions/buttons/$workflowId',
      data: {
        'unique_name': uniqueName,
        'description': description,
        'node_graph': nodeGraph,
        'workflow_stage': workflowStage,
        'is_active': isActive,
        'department_ids': departmentIds,
      },
    );
    return _workflowFromActionButton(response.data as Map<String, dynamic>);
  }

  Future<void> deleteWorkflow({required String workflowId}) async {
    await _dio.delete('/api/actions/buttons/$workflowId');
  }

  Future<ProjectDto> updateProjectWorkflowStage({
    required String projectId,
    required String workflowStage,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/workflow-stage',
      data: {'workflow_stage': workflowStage},
    );
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectDto> updateProjectBaseModel({
    required String projectId,
    required String baseModel,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/base-model',
      data: {'base_model': baseModel},
    );
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectDto> updateProjectOrderNotes({
    required String projectId,
    String? topNote,
    String? bottomNote,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/order-notes',
      data: {
        'top_note': topNote,
        'bottom_note': bottomNote,
      },
    );
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ProjectOrderItemDto>> projectOrderItems(String projectId) async {
    final response = await _dio.get('/projects/$projectId/order-items');
    return (response.data as List<dynamic>)
        .map(
          (item) => ProjectOrderItemDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ProjectOrderItemDto> updateProjectOrderItem({
    required String projectId,
    required String itemId,
    required int quantity,
    required bool selected,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/order-items/$itemId',
      data: {'quantity': quantity, 'selected': selected},
    );
    return ProjectOrderItemDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PartDto>> parts({
    String? parentPartId,
    bool includeAll = false,
    String? partRole,
    String? search,
  }) async {
    final response = await _dio.get(
      '/parts',
      queryParameters: {
        'parent_part_id': parentPartId,
        'include_all': includeAll,
        'part_role': partRole,
        'search': search,
      },
    );
    return (response.data as List<dynamic>)
        .map((item) => PartDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createPart({
    required String name,
    String? parentPartId,
    String? rivalPartId,
    String? categoryId,
    String? description,
    String? partSource,
    String status = 'active',
    String? notes,
    String partRole = 'main',
    String? idNumber,
    double buyPrice = 0,
    double sellPrice = 0,
    List<int>? imageBytes,
    String? imageFileName,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'part_role': partRole,
      'status': status,
      'buy_price': buyPrice,
      'sell_price': sellPrice,
      'category_id': categoryId ?? '',
    };
    if (parentPartId != null && parentPartId.trim().isNotEmpty) {
      payload['parent_part_id'] = parentPartId;
    }
    if (rivalPartId != null && rivalPartId.trim().isNotEmpty) {
      payload['rival_part_id'] = rivalPartId;
    }
    if (idNumber != null && idNumber.trim().isNotEmpty) {
      payload['id_number'] = idNumber;
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (partSource != null && partSource.trim().isNotEmpty) {
      payload['part_source'] = partSource.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }
    if (imageBytes != null) {
      payload['image'] = MultipartFile.fromBytes(
        imageBytes,
        filename: imageFileName ?? 'part_image.bin',
      );
    }

    final formData = FormData.fromMap(payload);
    await _dio.post('/parts', data: formData);
  }

  Future<void> linkExistingParts({
    required String parentPartId,
    required List<String> childPartIds,
  }) async {
    await _dio.post(
      '/parts/$parentPartId/children',
      data: {'child_part_ids': childPartIds},
    );
  }

  Future<void> deletePart(String partId) async {
    await _dio.delete('/parts/$partId');
  }

  Future<List<PartDto>> resetPartsFromStructure() async {
    final response = await _dio.post('/parts/reset-from-structure');
    return (response.data as List<dynamic>)
        .map((item) => PartDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PartDto> partById(String partId) async {
    final response = await _dio.get('/parts/$partId');
    return PartDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updatePart({
    required String partId,
    required String name,
    String? parentPartId,
    String? rivalPartId,
    String? categoryId,
    String? description,
    String? partSource,
    String status = 'active',
    String? notes,
    String partRole = 'main',
    String? idNumber,
    double buyPrice = 0,
    double sellPrice = 0,
    List<int>? imageBytes,
    String? imageFileName,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'part_role': partRole,
      'status': status,
      'buy_price': buyPrice,
      'sell_price': sellPrice,
      'category_id': categoryId ?? '',
    };
    if (parentPartId != null && parentPartId.trim().isNotEmpty) {
      payload['parent_part_id'] = parentPartId;
    }
    if (rivalPartId != null && rivalPartId.trim().isNotEmpty) {
      payload['rival_part_id'] = rivalPartId;
    }
    if (idNumber != null && idNumber.trim().isNotEmpty) {
      payload['id_number'] = idNumber;
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (partSource != null && partSource.trim().isNotEmpty) {
      payload['part_source'] = partSource.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }
    if (imageBytes != null) {
      payload['image'] = MultipartFile.fromBytes(
        imageBytes,
        filename: imageFileName ?? 'part_image.bin',
      );
    }

    final formData = FormData.fromMap(payload);
    await _dio.patch('/parts/$partId', data: formData);
  }

  Future<List<PartCategoryDto>> partCategories({String? scope}) async {
    final queryParameters = <String, dynamic>{};
    if (scope != null && scope.trim().isNotEmpty) {
      queryParameters['scope'] = scope.trim();
    }
    final response = await _dio.get(
      '/parts/categories',
      queryParameters: queryParameters,
    );
    return (response.data as List<dynamic>)
        .map((item) => PartCategoryDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PartCategoryDto> createPartCategory({
    required String scope,
    required String name,
  }) async {
    final response = await _dio.post(
      '/parts/categories',
      data: {'scope': scope, 'name': name},
    );
    return PartCategoryDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deletePartCategory(String categoryId) async {
    await _dio.delete('/parts/categories/$categoryId');
  }

  Future<PartDto> uploadPartCadFile({
    required String partId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    final response = await _dio.post('/parts/$partId/cad', data: formData);
    return PartDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PartDto> deletePartCadFile(String partId) async {
    final response = await _dio.delete('/parts/$partId/cad');
    return PartDto.fromJson(response.data as Map<String, dynamic>);
  }

  String partCadDownloadUrl(String partId) =>
      '${_dio.options.baseUrl}/parts/$partId/cad/download';

  Future<PartDrawingDto> uploadPartDrawing({
    required String partId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    final response = await _dio.post('/parts/$partId/drawings', data: formData);
    return PartDrawingDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deletePartDrawing({
    required String partId,
    required String drawingId,
  }) async {
    await _dio.delete('/parts/$partId/drawings/$drawingId');
  }

  String partDrawingDownloadUrl(String partId, String drawingId) =>
      '${_dio.options.baseUrl}/parts/$partId/drawings/$drawingId/download';

  Future<PartDto> uploadPartInstructions({
    required String partId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    final response = await _dio.post(
      '/parts/$partId/instructions',
      data: formData,
    );
    return PartDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PartDto> deletePartInstructions(String partId) async {
    final response = await _dio.delete('/parts/$partId/instructions');
    return PartDto.fromJson(response.data as Map<String, dynamic>);
  }

  String partInstructionsDownloadUrl(String partId) =>
      '${_dio.options.baseUrl}/parts/$partId/instructions/download';

  Future<List<FolderDto>> folders(
    String projectId, {
    String? parentFolderId,
    String? search,
    bool includeAll = false,
  }) async {
    final query = <String, dynamic>{'project_id': projectId};
    if (parentFolderId != null && parentFolderId.isNotEmpty) {
      query['parent_folder_id'] = parentFolderId;
    }
    if (search != null && search.isNotEmpty) {
      query['search'] = search;
    }
    if (includeAll) {
      query['include_all'] = true;
    }

    final response = await _dio.get('/folders', queryParameters: query);
    return (response.data as List<dynamic>)
        .map((item) => FolderDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<FolderDto> createFolder({
    required String projectId,
    required String name,
    String? parentFolderId,
  }) async {
    final response = await _dio.post(
      '/folders',
      data: {
        'project_id': projectId,
        'name': name,
        'parent_folder_id': parentFolderId,
      },
    );
    return FolderDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<TodoDto>> todos({
    String? companyId,
    String? clientCompanyId,
    String? projectId,
    String? folderId,
  }) async {
    final response = await _dio.get(
      '/todos',
      queryParameters: {
        'company_id': ?companyId,
        'client_company_id': ?clientCompanyId,
        'project_id': ?projectId,
        'folder_id': ?folderId,
      },
    );
    return (response.data as List<dynamic>)
        .map((item) => TodoDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TodoDto> createTodo({
    required String name,
    String? companyId,
    String? clientCompanyId,
    String? projectId,
    String? folderId,
    String? description,
    DateTime? dueDate,
    bool isCompleted = false,
  }) async {
    final response = await _dio.post(
      '/todos',
      data: {
        'name': name,
        'company_id': ?companyId,
        'client_company_id': ?clientCompanyId,
        'project_id': ?projectId,
        'folder_id': ?folderId,
        'description': description,
        'due_date': dueDate?.toIso8601String(),
        'is_completed': isCompleted,
      },
    );
    return TodoDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TodoDto> updateTodo({
    required String todoId,
    String? name,
    String? companyId,
    String? clientCompanyId,
    String? projectId,
    String? folderId,
    String? description,
    DateTime? dueDate,
    bool? isCompleted,
  }) async {
    final response = await _dio.patch(
      '/todos/$todoId',
      data: {
        'name': ?name,
        'company_id': ?companyId,
        'client_company_id': ?clientCompanyId,
        'project_id': ?projectId,
        'folder_id': ?folderId,
        'description': ?description,
        if (dueDate != null) 'due_date': dueDate.toIso8601String(),
        'is_completed': ?isCompleted,
      },
    );
    return TodoDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTodo(String todoId) async {
    await _dio.delete('/todos/$todoId');
  }
}
