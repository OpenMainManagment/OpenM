import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../models/dtos.dart';
import '../models/workflow/workflow_model.dart';
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

class InitialSetupStatus {
  const InitialSetupStatus({
    required this.setupRequired,
    required this.legacyAdminPasswordReset,
    this.organizationName,
  });

  final bool setupRequired;
  final bool legacyAdminPasswordReset;
  final String? organizationName;

  factory InitialSetupStatus.fromJson(Map<String, dynamic> json) {
    return InitialSetupStatus(
      setupRequired: json['setup_required'] as bool,
      legacyAdminPasswordReset: json['legacy_admin_password_reset'] as bool,
      organizationName: json['organization_name'] as String?,
    );
  }
}

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<InitialSetupStatus> initialSetupStatus() async {
    final response = await _dio.get('/auth/setup/status');
    return InitialSetupStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> initializeApplication({
    required String organizationName,
    required String firstName,
    required String lastName,
    required String email,
    required String loginName,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/setup',
      data: {
        'organization_name': organizationName,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'login_name': loginName,
        'password': password,
      },
    );
    return (response.data as Map<String, dynamic>)['access_token'] as String;
  }

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

  Future<EmployeeDto> getCurrentEmployee() async {
    final response = await _dio.get('/auth/employees/me');
    return EmployeeDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Self-service profile edit (name/email/job description only — role,
  /// department and login name stay admin-managed).
  Future<EmployeeDto> updateMyProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? jobDescription,
  }) async {
    final payload = <String, dynamic>{};
    if (firstName != null) payload['first_name'] = firstName;
    if (lastName != null) payload['last_name'] = lastName;
    if (email != null) payload['email'] = email;
    if (jobDescription != null) payload['job_description'] = jobDescription;

    final response = await _dio.patch('/auth/employees/me', data: payload);
    return EmployeeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> changeMyPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post(
      '/auth/employees/me/password',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<EmployeeDto> uploadMyProfilePhoto({
    required List<int> imageBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: fileName),
    });
    final response = await _dio.post(
      '/auth/employees/me/image',
      data: formData,
    );
    return EmployeeDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Bytes of the current employee's profile photo, or null if none is set.
  Future<List<int>?> myProfilePhotoBytes() async {
    try {
      final response = await _dio.get<List<int>>(
        '/auth/employees/me/image',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Bytes of any employee's profile photo by id, or null if none is set.
  Future<List<int>?> employeeImageBytes(String employeeId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/auth/employees/$employeeId/image',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
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
          'image_url': customer['image_url'],
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
      queryParameters: {'organization_id': mainCompanyId, 'search': search},
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
      queryParameters: {'client_company_id': clientCompanyId, 'search': search},
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

  Future<ProjectGanttTreeResponseDto> projectGanttTree(String projectId) async {
    final response = await _dio.get('/projects/$projectId/gantt-tree');
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> updateProjectGanttStepDuration({
    required String projectId,
    required String stepId,
    required int durationDays,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/gantt/steps/$stepId/duration',
      data: {'duration_days': durationDays},
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> updateProjectGanttSubStepDuration({
    required String projectId,
    required String subStepId,
    required int durationDays,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/gantt/sub-steps/$subStepId/duration',
      data: {'duration_days': durationDays},
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> updateProjectGanttSubStepAssignee({
    required String projectId,
    required String subStepId,
    String? assigneeLogin,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/gantt/sub-steps/$subStepId/assignee',
      data: {'assignee_login': assigneeLogin},
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> updateProjectGanttSubStepAssignees({
    required String projectId,
    required String subStepId,
    required List<String> assigneeLogins,
  }) async {
    final response = await _dio.patch(
      '/projects/$projectId/gantt/sub-steps/$subStepId/assignees',
      data: {'assignee_logins': assigneeLogins},
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> createProjectGanttSubStep({
    required String projectId,
    required String stepId,
    required String title,
    String? description,
    int durationDays = 1,
  }) async {
    final response = await _dio.post(
      '/projects/$projectId/gantt/steps/$stepId/sub-steps',
      data: {
        'title': title,
        'description': description,
        'duration_days': durationDays,
      },
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectGanttTreeResponseDto> deleteProjectGanttSubStep({
    required String projectId,
    required String subStepId,
  }) async {
    final response = await _dio.delete(
      '/projects/$projectId/gantt/sub-steps/$subStepId',
    );
    return ProjectGanttTreeResponseDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectDto> nextProjectStatus(String projectId) async {
    final response = await _dio.patch('/projects/$projectId/next-status');
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectDto> previousProjectStatus(String projectId) async {
    final response = await _dio.patch('/projects/$projectId/previous-status');
    return ProjectDto.fromJson(response.data as Map<String, dynamic>);
  }

  Workflow _workflowFromActionButton(Map<String, dynamic> json) {
    // node_graph comes back from the backend as a JSON-encoded string
    // (ActionButton.node_graph is a Text column), not as a nested object.
    final rawNodeGraph = json['node_graph'] as String?;
    final nodeIds = <String>[];
    if (rawNodeGraph != null && rawNodeGraph.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNodeGraph);
        if (decoded is Map<String, dynamic>) {
          final nodes = decoded['nodes'];
          if (nodes is List<dynamic>) {
            for (final node in nodes) {
              if (node is Map<String, dynamic> && node['id'] is String) {
                nodeIds.add(node['id'] as String);
              }
            }
          }
        }
      } catch (_) {
        // Ignore malformed node graphs; fall back to no known node ids.
      }
    }

    return Workflow(
      id: json['id'] as String,
      name: json['unique_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      companyId:
          json['company_id'] as String? ??
          json['organization_id'] as String? ??
          '',
      workflowStage: json['workflow_stage'] as String? ?? 'draft',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      nodeIds: nodeIds.isEmpty ? null : nodeIds,
      nodeGraph: rawNodeGraph,
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
      data: {'top_note': topNote, 'bottom_note': bottomNote},
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

  Future<List<ProjectOrderItemDto>> projectPartsStatus(String projectId) async {
    final response = await _dio.get('/projects/$projectId/parts-status');
    return (response.data as List<dynamic>)
        .map(
          (item) => ProjectOrderItemDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ProjectOrderItemDto> updateProjectPartStatus({
    required String projectId,
    required String itemId,
    String? orderStatus,
    String? orderNumber,
    String? quotationNumber,
    String? shippingNumber,
    String? supplier,
    DateTime? orderedAt,
    DateTime? expectedDeliveryDate,
    DateTime? actualDeliveryDate,
    String? statusNotes,
  }) async {
    String? dateOnly(DateTime? value) =>
        value?.toIso8601String().split('T').first;

    final response = await _dio.patch(
      '/projects/$projectId/order-items/$itemId/status',
      data: {
        'order_status': orderStatus,
        'order_number': orderNumber,
        'quotation_number': quotationNumber,
        'shipping_number': shippingNumber,
        'supplier': supplier,
        'ordered_at': dateOnly(orderedAt),
        'expected_delivery_date': dateOnly(expectedDeliveryDate),
        'actual_delivery_date': dateOnly(actualDeliveryDate),
        'status_notes': statusNotes,
      },
    );
    return ProjectOrderItemDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Requests quotations for every selected part on the project: assigns a
  /// quotation number, pushes the due date 4 weeks out, and marks Storage-
  /// sourced parts as already In Stock.
  Future<List<ProjectOrderItemDto>> requestProjectQuotation(
    String projectId,
  ) async {
    final response = await _dio.post('/projects/$projectId/request-quotation');
    return (response.data as List<dynamic>)
        .map(
          (item) => ProjectOrderItemDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Generates a PDF offer for the project's selected parts and saves it
  /// into the project's "Angebote" folder.
  Future<DocumentDto> generateProjectOfferPdf(String projectId) async {
    final response = await _dio.post('/projects/$projectId/offer/pdf');
    return DocumentDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ProjectOfferRecipientDto>> projectOfferRecipients(
    String projectId,
  ) async {
    final response = await _dio.get('/projects/$projectId/offer/recipients');
    return (response.data as List<dynamic>)
        .map(
          (item) =>
              ProjectOfferRecipientDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectOfferSendResultDto>> sendProjectOffer({
    required String projectId,
    required String documentId,
    required List<String> customerIds,
  }) async {
    final response = await _dio.post(
      '/projects/$projectId/offer/send',
      data: {'document_id': documentId, 'customer_ids': customerIds},
    );
    return (response.data as List<dynamic>)
        .map(
          (item) =>
              ProjectOfferSendResultDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
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
        'organization_id': companyId,
        'client_company_id': clientCompanyId,
        'project_id': projectId,
        'folder_id': folderId,
      },
    );
    return (response.data as List<dynamic>)
        .map((item) => TodoDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TodoDto> createTodo({
    required String name,
    String? companyId,
    String? projectId,
    String? folderId,
    String? department,
    String? mainEmployer,
    List<String> coworkerLogins = const [],
    String? description,
    String? startDate,
    String? endDate,
    String projectStatus = 'inWork',
  }) async {
    final response = await _dio.post(
      '/todos',
      data: {
        'name': name,
        'organization_id': companyId,
        'project_id': projectId,
        'folder_id': folderId,
        'department': department,
        'main_employer': mainEmployer,
        'coworker_logins': coworkerLogins,
        'description': description,
        'start_date': startDate,
        'end_date': endDate,
        'project_status': projectStatus,
      },
    );
    return TodoDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TodoDto> updateTodo({
    required String todoId,
    required String name,
    String? companyId,
    String? projectId,
    String? folderId,
    String? department,
    String? mainEmployer,
    List<String>? coworkerLogins,
    String? description,
    String? startDate,
    String? endDate,
    String? projectStatus,
  }) async {
    final response = await _dio.patch(
      '/todos/$todoId',
      data: {
        'name': name,
        'organization_id': companyId,
        'project_id': projectId,
        'folder_id': folderId,
        'department': department,
        'main_employer': mainEmployer,
        'coworker_logins': coworkerLogins,
        'description': description,
        'start_date': startDate,
        'end_date': endDate,
        'project_status': projectStatus,
      },
    );
    return TodoDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTodo(String todoId) async {
    await _dio.delete('/todos/$todoId');
  }

  Future<void> reorderTodos({
    required String projectStatus,
    required List<String> orderedTodoIds,
  }) async {
    await _dio.patch(
      '/todos/reorder',
      data: {
        'project_status': projectStatus,
        'ordered_todo_ids': orderedTodoIds,
      },
    );
  }

  Future<Map<String, dynamic>> createTodoRepresentation({
    required String delegateLogin,
    required String startDate,
    required String endDate,
  }) async {
    final response = await _dio.post(
      '/todos/representation',
      data: {
        'delegate_login': delegateLogin,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<EmployeeDto>> adminEmployees() async {
    final response = await _dio.get('/admin/employees');
    return (response.data as List<dynamic>)
        .map((item) => EmployeeDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<EmployeeDto>> authEmployees() async {
    final response = await _dio.get('/auth/employees');
    return (response.data as List<dynamic>)
        .map((item) => EmployeeDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> authDepartments() async {
    final response = await _dio.get('/auth/departments');
    return (response.data as List<dynamic>)
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> createEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String loginName,
    required String password,
    String role = 'User',
    String? department,
    String? companyId,
  }) async {
    await _dio.post(
      '/admin/employees',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'login_name': loginName,
        'password': password,
        'role': role,
        'department': department,
        'organization_id': companyId,
      },
    );
  }

  Future<void> updateEmployee({
    required String employeeId,
    String? firstName,
    String? lastName,
    String? email,
    String? role,
    String? department,
    String? companyId,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) {
      data['first_name'] = firstName;
    }
    if (lastName != null) {
      data['last_name'] = lastName;
    }
    if (email != null) {
      data['email'] = email;
    }
    if (role != null) {
      data['role'] = role;
    }
    if (department != null) {
      data['department'] = department;
    }
    if (companyId != null) {
      data['organization_id'] = companyId;
    }

    await _dio.patch('/admin/employees/$employeeId', data: data);
  }

  Future<void> deleteEmployee(String employeeId) async {
    await _dio.delete('/admin/employees/$employeeId');
  }

  Future<List<CompanyRoleDto>> companyRoles(String companyId) async {
    final response = await _dio.get(
      '/admin/company-roles',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map((item) => CompanyRoleDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCompanyRole({
    required String companyId,
    required String name,
    List<String> permissions = const [],
  }) async {
    await _dio.post(
      '/admin/company-roles',
      data: {
        'organization_id': companyId,
        'name': name,
        'permissions': permissions,
      },
    );
  }

  Future<void> updateCompanyRole({
    required String roleId,
    String? name,
    List<String>? permissions,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) {
      data['name'] = name;
    }
    if (permissions != null) {
      data['permissions'] = permissions;
    }
    await _dio.patch('/admin/company-roles/$roleId', data: data);
  }

  Future<void> deleteCompanyRole(String roleId) async {
    await _dio.delete('/admin/company-roles/$roleId');
  }

  Future<List<DepartmentDto>> departments(String companyId) async {
    final response = await _dio.get(
      '/admin/departments',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map((item) => DepartmentDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDepartment({
    required String companyId,
    required String name,
    List<String> roleIds = const [],
    List<String> folderTemplates = const [],
    List<String> projectActions = const [],
  }) async {
    await _dio.post(
      '/admin/departments',
      data: {
        'organization_id': companyId,
        'name': name,
        'role_ids': roleIds,
        'folder_templates': folderTemplates,
        'project_actions': projectActions,
      },
    );
  }

  Future<void> updateDepartment({
    required String departmentId,
    String? name,
    List<String>? roleIds,
    List<String>? folderTemplates,
    List<String>? projectActions,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) {
      data['name'] = name;
    }
    if (roleIds != null) {
      data['role_ids'] = roleIds;
    }
    if (folderTemplates != null) {
      data['folder_templates'] = folderTemplates;
    }
    if (projectActions != null) {
      data['project_actions'] = projectActions;
    }
    await _dio.patch('/admin/departments/$departmentId', data: data);
  }

  Future<void> deleteDepartment(String departmentId) async {
    await _dio.delete('/admin/departments/$departmentId');
  }

  Future<List<DocumentDto>> folderFiles(
    String folderId, {
    String? search,
  }) async {
    final response = await _dio.get(
      '/files',
      queryParameters: {'folder_id': folderId, 'search': search},
    );
    return (response.data as List<dynamic>)
        .map((item) => DocumentDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> uploadFile({
    required String folderId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'folder_id': folderId,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    await _dio.post('/files/upload', data: formData);
  }

  /// Sends a message (and optional file) to the local AI assistant crew.
  /// The crew can take a while to respond, so this uses a longer timeout
  /// than the rest of the API.
  Future<({String response, bool isError})> sendChatMessage({
    required String message,
    List<int>? fileBytes,
    String? fileName,
    String? projectId,
    String? projectContext,
  }) async {
    final formData = FormData.fromMap({
      'message': message,
      'project_id': projectId ?? '',
      'project_context': projectContext ?? '',
      if (fileBytes != null && fileName != null)
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    final response = await _dio.post(
      '/chat/message',
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final data = response.data as Map<String, dynamic>;
    return (
      response: data['response'] as String? ?? '',
      isError: data['error'] as bool? ?? false,
    );
  }

  /// Full text summary of a project (status, parts, sourcing decisions,
  /// gantt progress, todos) to hand to the AI chat assistant as context.
  Future<String> projectAiContext(String projectId) async {
    final response = await _dio.get('/projects/$projectId/ai-context');
    return (response.data as Map<String, dynamic>)['context'] as String? ?? '';
  }

  Future<List<DemoTemplateDto>> demoTemplates({String? category}) async {
    final response = await _dio.get(
      '/files/demo-templates',
      queryParameters: {'category': category},
    );
    return (response.data as List<dynamic>)
        .map((item) => DemoTemplateDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createFileFromDemo({
    required String folderId,
    required String templateId,
    String? fileName,
  }) async {
    await _dio.post(
      '/files/create-from-demo',
      data: {
        'folder_id': folderId,
        'template_id': templateId,
        'file_name': fileName,
      },
    );
  }

  Future<void> renameFile({
    required String fileId,
    required String fileName,
  }) async {
    await _dio.patch('/files/$fileId/rename', data: {'file_name': fileName});
  }

  Future<void> moveFile({
    required String fileId,
    required String folderId,
  }) async {
    await _dio.patch('/files/$fileId/move', data: {'folder_id': folderId});
  }

  Future<void> deleteFile(String fileId) async {
    await _dio.delete('/files/$fileId');
  }

  Future<List<int>> downloadFileBytes(String fileId) async {
    final response = await _dio.get<List<int>>(
      '/files/$fileId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<void> replaceFileContent({
    required String fileId,
    required List<int> bytes,
    required String fileName,
    String contentType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    await _dio.put('/files/$fileId/content', data: formData);
  }

  Future<String> extractBusinessCardText({
    required List<int> bytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await _dio.post(
      '/ai/business-card-extract',
      data: formData,
    );
    final data = response.data as Map<String, dynamic>;
    return data['extracted_text'] as String? ?? '';
  }

  String downloadUrl(String fileId) {
    return '${_dio.options.baseUrl}/files/$fileId/download';
  }

  Future<AiSummaryDto> folderSummary({
    required String folderId,
    String? projectContext,
  }) async {
    final response = await _dio.post(
      '/ai/folder-summary',
      data: {'folder_id': folderId, 'project_context': projectContext},
    );
    return AiSummaryDto.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Folder access ────────────────────────────────────────────────────────

  Future<FolderAccessDto> folderAccess(String folderId) async {
    final response = await _dio.get('/admin/folders/$folderId/access');
    return FolderAccessDto.fromJson(response.data as Map<String, dynamic>);
  }

  /// Replace the full department access list for a folder.
  /// Pass an empty list to remove all restrictions.
  Future<FolderAccessDto> setFolderDepartmentAccess({
    required String folderId,
    required List<String> departmentIds,
  }) async {
    final response = await _dio.put(
      '/admin/folders/$folderId/department-access',
      data: {'department_ids': departmentIds},
    );
    return FolderAccessDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FolderAccessDto> addFolderUserAccess({
    required String folderId,
    required String employeeId,
  }) async {
    final response = await _dio.post(
      '/admin/folders/$folderId/user-access',
      data: {'employee_id': employeeId},
    );
    return FolderAccessDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FolderAccessDto> removeFolderUserAccess({
    required String folderId,
    required String employeeId,
  }) async {
    final response = await _dio.delete(
      '/admin/folders/$folderId/user-access/$employeeId',
    );
    return FolderAccessDto.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Project folder templates ──────────────────────────────────────────────

  Future<List<ProjectFolderTemplateDto>> projectFolderTemplates(
    String companyId,
  ) async {
    final response = await _dio.get(
      '/admin/project-folder-templates',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectFolderTemplateDto>> addProjectFolderTemplate({
    required String companyId,
    required String name,
    String? parentTemplateId,
  }) async {
    final response = await _dio.post(
      '/admin/project-folder-templates',
      queryParameters: {'organization_id': companyId},
      data: {'name': name, 'parent_template_id': parentTemplateId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  // ==================== Action System ====================

  Future<List<ProjectActionDto>> getProjectActions({
    String? companyId,
    String? workflowStage,
  }) async {
    final response = await _dio.get(
      '/api/actions/buttons',
      queryParameters: {
        'organization_id': companyId,
        'workflow_stage': workflowStage,
      },
    );
    return (response.data as List<dynamic>)
        .map((item) => ProjectActionDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ProjectActionDto> getProjectAction(String buttonId) async {
    final response = await _dio.get('/api/actions/buttons/$buttonId');
    return ProjectActionDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectActionDto> createProjectAction({
    required String uniqueName,
    String? description,
    String? nodeGraph,
    String? workflowStage,
    bool isActive = true,
    List<String> departmentIds = const [],
  }) async {
    final response = await _dio.post(
      '/api/actions/buttons',
      data: {
        'unique_name': uniqueName,
        'description': description,
        'node_graph': nodeGraph ?? '{}',
        'workflow_stage': workflowStage,
        'is_active': isActive,
        'department_ids': departmentIds,
      },
    );
    return ProjectActionDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProjectActionDto> updateProjectAction({
    required String buttonId,
    String? uniqueName,
    String? description,
    String? nodeGraph,
    String? workflowStage,
    bool? isActive,
    int? sortOrder,
    List<String>? departmentIds,
  }) async {
    final payload = <String, dynamic>{
      'unique_name': uniqueName,
      'description': description,
      'node_graph': nodeGraph,
      'workflow_stage': workflowStage,
      'is_active': isActive,
      'sort_order': sortOrder,
      'department_ids': departmentIds,
    }..removeWhere((_, value) => value == null);

    final response = await _dio.put(
      '/api/actions/buttons/$buttonId',
      data: payload,
    );
    return ProjectActionDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProjectAction(String buttonId) async {
    await _dio.delete('/api/actions/buttons/$buttonId');
  }

  Future<List<WorkflowNodeDto>> getWorkflowNodes() async {
    final response = await _dio.get('/api/actions/nodes');
    return (response.data as List<dynamic>)
        .map((item) => WorkflowNodeDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ServerSettingsDto> getServerSettings() async {
    final response = await _dio.get('/admin/settings');
    return ServerSettingsDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ServerSettingsDto> updateEmailSettings({
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
    bool smtpUseTls = true,
    String? mailFrom,
  }) async {
    final response = await _dio.put(
      '/admin/settings/email',
      data: {
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'smtp_username': smtpUsername,
        'smtp_password': smtpPassword,
        'smtp_use_tls': smtpUseTls,
        'mail_from': mailFrom,
      },
    );
    return ServerSettingsDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ServerSettingsDto> updateAiServers(
    List<AiServerConfigDto> aiServers,
  ) async {
    final response = await _dio.put(
      '/admin/settings/ai-servers',
      data: {'ai_servers': aiServers.map((server) => server.toJson()).toList()},
    );
    return ServerSettingsDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<EmployeeMailSettingsDto> getMyMailSettings() async {
    final response = await _dio.get('/auth/employees/me/mail-settings');
    return EmployeeMailSettingsDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<EmployeeMailSettingsDto> updateMyMailSettings({
    String? imapHost,
    int imapPort = 993,
    String? imapUsername,
    String? imapPassword,
    bool imapUseSsl = true,
    String draftsFolder = 'Drafts',
  }) async {
    final response = await _dio.put(
      '/auth/employees/me/mail-settings',
      data: {
        'imap_host': imapHost,
        'imap_port': imapPort,
        'imap_username': imapUsername,
        'imap_password': imapPassword,
        'imap_use_ssl': imapUseSsl,
        'drafts_folder': draftsFolder,
      },
    );
    return EmployeeMailSettingsDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<WorkflowNodeDto> getWorkflowNode(String nodeId) async {
    final response = await _dio.get('/api/actions/nodes/$nodeId');
    return WorkflowNodeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkflowNodeDto> createWorkflowNode({
    required String name,
    required String category,
    String? function,
    String? endpoint,
    String? triggerInput,
    String configuration = '{}',
    String? description,
    bool isActive = true,
  }) async {
    final response = await _dio.post(
      '/api/actions/nodes',
      data: {
        'name': name,
        'category': category,
        'function': function,
        'endpoint': endpoint,
        'trigger_input': triggerInput,
        'configuration': configuration,
        'description': description,
        'is_active': isActive,
      },
    );
    return WorkflowNodeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkflowNodeDto> updateWorkflowNode({
    required String nodeId,
    String? name,
    String? category,
    String? function,
    String? endpoint,
    String? triggerInput,
    String? configuration,
    String? description,
    bool? isActive,
  }) async {
    final response = await _dio.put(
      '/api/actions/nodes/$nodeId',
      data: {
        'name': name,
        'category': category,
        'function': function,
        'endpoint': endpoint,
        'trigger_input': triggerInput,
        'configuration': configuration,
        'description': description,
        'is_active': isActive,
      },
    );
    return WorkflowNodeDto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteWorkflowNode(String nodeId) async {
    await _dio.delete('/api/actions/nodes/$nodeId');
  }

  Future<Map<String, dynamic>> sendGoogleTestMail({
    required String recipientEmail,
    String? subject,
    String? body,
    String? projectId,
  }) async {
    final response = await _dio.post(
      '/api/actions/mail/google-test',
      data: {
        'recipient_email': recipientEmail,
        'subject': subject,
        'body': body,
        'project_id': projectId,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<ProjectActionExecutionDto>> getProjectActionExecutions(
    String projectId,
  ) async {
    final response = await _dio.get(
      '/api/actions/projects/$projectId/executions',
    );
    return (response.data as List<dynamic>)
        .map(
          (item) =>
              ProjectActionExecutionDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ProjectActionExecutionDto> executeProjectAction({
    required String projectId,
    required String actionButtonId,
    Map<String, dynamic>? executionInput,
  }) async {
    final response = await _dio.post(
      '/api/actions/projects/$projectId/execute',
      data: {
        'action_button_id': actionButtonId,
        'execution_input': executionInput == null
            ? null
            : jsonEncode(executionInput),
      },
    );
    return ProjectActionExecutionDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectActionExecutionDto> getProjectActionExecution(
    String executionId,
  ) async {
    final response = await _dio.get('/api/actions/executions/$executionId');
    return ProjectActionExecutionDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProjectActionExecutionDto> updateProjectActionExecution({
    required String executionId,
    String? executionStatus,
    String? executionResult,
    String? errorMessage,
  }) async {
    final response = await _dio.put(
      '/api/actions/executions/$executionId',
      data: {
        'execution_status': executionStatus,
        'execution_result': executionResult,
        'error_message': errorMessage,
      },
    );
    return ProjectActionExecutionDto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<ProjectFolderTemplateDto>> deleteProjectFolderTemplate(
    String templateId,
  ) async {
    final response = await _dio.delete(
      '/admin/project-folder-templates/$templateId',
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectFolderTemplateDto>> initDefaultProjectFolderTemplates(
    String companyId,
  ) async {
    final response = await _dio.post(
      '/admin/project-folder-templates/init-defaults',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectFolderTemplateDemoFileDto>> folderTemplateDemoFiles(
    String templateId,
  ) async {
    final response = await _dio.get(
      '/admin/project-folder-templates/$templateId/demo-files',
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDemoFileDto.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<ProjectFolderTemplateDemoFileDto>> addFolderTemplateDemoFile({
    required String templateId,
    required String demoTemplateId,
    String? targetFileName,
  }) async {
    final response = await _dio.post(
      '/admin/project-folder-templates/$templateId/demo-files',
      data: {
        'demo_template_id': demoTemplateId,
        'target_file_name': targetFileName,
      },
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDemoFileDto.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<ProjectFolderTemplateDemoFileDto>> deleteFolderTemplateDemoFile(
    String demoFileId,
  ) async {
    final response = await _dio.delete(
      '/admin/project-folder-template-demo-files/$demoFileId',
    );
    return (response.data as List<dynamic>)
        .map(
          (e) => ProjectFolderTemplateDemoFileDto.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> projectGanttStepTemplates(
    String companyId,
  ) async {
    final response = await _dio.get(
      '/admin/project-gantt-step-templates',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>>
  initDefaultProjectGanttStepTemplates(String companyId) async {
    final response = await _dio.post(
      '/admin/project-gantt-step-templates/init-defaults',
      queryParameters: {'organization_id': companyId},
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> addProjectGanttStepTemplate({
    required String companyId,
    required String statusKey,
    required String title,
    String? description,
    int durationDays = 7,
  }) async {
    final response = await _dio.post(
      '/admin/project-gantt-step-templates',
      queryParameters: {'organization_id': companyId},
      data: {
        'status_key': statusKey,
        'title': title,
        'description': description,
        'duration_days': durationDays,
      },
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> updateProjectGanttStepTemplate({
    required String templateId,
    String? statusKey,
    String? title,
    String? description,
    int? durationDays,
  }) async {
    final payload = <String, dynamic>{};
    if (statusKey != null) {
      payload['status_key'] = statusKey;
    }
    if (title != null) {
      payload['title'] = title;
    }
    if (description != null) {
      payload['description'] = description;
    }
    if (durationDays != null) {
      payload['duration_days'] = durationDays;
    }
    final response = await _dio.patch(
      '/admin/project-gantt-step-templates/$templateId',
      data: payload,
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> deleteProjectGanttStepTemplate(
    String templateId,
  ) async {
    final response = await _dio.delete(
      '/admin/project-gantt-step-templates/$templateId',
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> addProjectGanttSubStepTemplate({
    required String parentTemplateId,
    required String title,
    String? description,
    int durationDays = 1,
  }) async {
    final response = await _dio.post(
      '/admin/project-gantt-step-templates/$parentTemplateId/sub-steps',
      data: {
        'title': title,
        'description': description,
        'duration_days': durationDays,
      },
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> updateProjectGanttSubStepTemplate({
    required String subTemplateId,
    String? title,
    String? description,
    int? durationDays,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) {
      payload['title'] = title;
    }
    if (description != null) {
      payload['description'] = description;
    }
    if (durationDays != null) {
      payload['duration_days'] = durationDays;
    }
    final response = await _dio.patch(
      '/admin/project-gantt-sub-step-templates/$subTemplateId',
      data: payload,
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ProjectGanttStepTemplateDto>> deleteProjectGanttSubStepTemplate(
    String subTemplateId,
  ) async {
    final response = await _dio.delete(
      '/admin/project-gantt-sub-step-templates/$subTemplateId',
    );
    return (response.data as List<dynamic>)
        .map(
          (e) =>
              ProjectGanttStepTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ManufacturerDto>> manufacturers() async {
    final response = await _dio.get('/manufacturers');
    return (response.data as List<dynamic>)
        .map((e) => ManufacturerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ManufacturerDto>> addManufacturer({
    required String name,
    String? website,
    String? contactEmail,
    String? phoneNumber,
    String? notes,
  }) async {
    final response = await _dio.post(
      '/manufacturers',
      data: {
        'name': name,
        'website': website,
        'contact_email': contactEmail,
        'phone_number': phoneNumber,
        'notes': notes,
      },
    );
    return (response.data as List<dynamic>)
        .map((e) => ManufacturerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ManufacturerDto>> updateManufacturer({
    required String manufacturerId,
    String? name,
    String? website,
    String? contactEmail,
    String? phoneNumber,
    String? notes,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (website != null) payload['website'] = website;
    if (contactEmail != null) payload['contact_email'] = contactEmail;
    if (phoneNumber != null) payload['phone_number'] = phoneNumber;
    if (notes != null) payload['notes'] = notes;

    final response = await _dio.patch(
      '/manufacturers/$manufacturerId',
      data: payload,
    );
    return (response.data as List<dynamic>)
        .map((e) => ManufacturerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ManufacturerDto>> deleteManufacturer(
    String manufacturerId,
  ) async {
    final response = await _dio.delete('/manufacturers/$manufacturerId');
    return (response.data as List<dynamic>)
        .map((e) => ManufacturerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PartOrderDecisionDto>> projectPartDecisions(
    String projectId,
  ) async {
    final response = await _dio.get('/projects/$projectId/part-decisions');
    return (response.data as List<dynamic>)
        .map((e) => PartOrderDecisionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// entries: list of {part_id, decision, manufacturer_id?, quantity?, notes?}
  Future<List<PartOrderDecisionDto>> savePartOrderDecisions({
    required String projectId,
    required List<Map<String, dynamic>> entries,
  }) async {
    final response = await _dio.post(
      '/projects/$projectId/part-decisions',
      data: {'entries': entries},
    );
    return (response.data as List<dynamic>)
        .map((e) => PartOrderDecisionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
