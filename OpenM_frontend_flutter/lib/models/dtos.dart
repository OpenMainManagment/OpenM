typedef MainCompanyDto = CompanyDto;
typedef ClientCompanyDto = CompanyDto;
typedef ClientContactDto = CompanyCustomerDto;

class CompanyDto {
  const CompanyDto({
    required this.id,
    required this.uniqueName,
    required this.uniqueCode,
    this.street,
    this.houseNumber,
    this.headOfCompany,
    this.contactEmail,
    this.phoneNumber,
    this.customers = const [],
    this.mainCustomerId,
    this.createdAt,
  });

  final String id;
  final String uniqueName;
  final String uniqueCode;
  final String? street;
  final String? houseNumber;
  final String? headOfCompany;
  final String? contactEmail;
  final String? phoneNumber;
  final List<CompanyCustomerDto> customers;
  final String? mainCustomerId;
  // Nullable: older rows created before this field existed have no
  // recorded creation date (see the backend's CustomerCompanyOut schema).
  final DateTime? createdAt;

  factory CompanyDto.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] as Map<String, dynamic>?;
    final createdAtRaw = json['created_at'] as String?;
    return CompanyDto(
      id: json['id'] as String,
      uniqueName: json['unique_name'] as String,
      uniqueCode: json['unique_code'] as String,
      street: contact?['street'] as String?,
      houseNumber: contact?['house_number'] as String?,
      headOfCompany: contact?['head_of_company'] as String?,
      contactEmail: contact?['email'] as String?,
      phoneNumber: contact?['phone_number'] as String?,
      customers: (json['customers'] as List<dynamic>? ?? const [])
          .map(
            (item) => CompanyCustomerDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      mainCustomerId: json['main_customer_id'] as String?,
      createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null,
    );
  }
}

class CompanyCustomerDto {
  const CompanyCustomerDto({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.gender,
    this.email,
    this.role,
    this.phoneNumber,
    this.mobileNumber,
    this.imageUrl,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String gender;
  final String? email;
  final String? role;
  final String? phoneNumber;
  final String? mobileNumber;
  final String? imageUrl;
  String get fullName => '$firstName $lastName'.trim();

  factory CompanyCustomerDto.fromJson(Map<String, dynamic> json) {
    return CompanyCustomerDto(
      id: json['id'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      gender: json['gender'] as String? ?? 'not_specified',
      email: json['email'] as String?,
      role: json['role'] as String?,
      phoneNumber: json['phone_number'] as String?,
      mobileNumber: json['mobile_number'] as String?,
    );
  }
}

class ProjectDto {
  const ProjectDto({
    required this.id,
    required this.companyId,
    required this.name,
    required this.status,
    required this.workflowStage,
    required this.baseModel,
    required this.ganttStarted,
    this.ganttStartedAt,
    this.orderTopNote,
    this.orderBottomNote,
  });

  final String id;
  final String companyId;
  final String name;
  final String status;
  final String workflowStage;
  final String baseModel;
  final bool ganttStarted;
  final String? ganttStartedAt;
  final String? orderTopNote;
  final String? orderBottomNote;

  factory ProjectDto.fromJson(Map<String, dynamic> json) {
    return ProjectDto(
      id: json['id'] as String,
      companyId: json['customer_company_id'] as String,
      name: json['name'] as String,
      status: json['status'] as String? ?? 'Quote',
      workflowStage: json['workflow_stage'] as String? ?? 'project',
      baseModel: json['base_model'] as String? ?? 'Normal',
      ganttStarted: json['gantt_started'] as bool? ?? false,
      ganttStartedAt: json['gantt_started_at'] as String?,
      orderTopNote: json['order_top_note'] as String?,
      orderBottomNote: json['order_bottom_note'] as String?,
    );
  }
}

class ProjectGanttStepDto {
  const ProjectGanttStepDto({
    required this.id,
    required this.projectId,
    required this.statusKey,
    required this.title,
    this.description,
    this.plannedStartDate,
    this.plannedEndDate,
    required this.isCompleted,
    required this.isCurrent,
    required this.sortOrder,
  });

  final String id;
  final String projectId;
  final String statusKey;
  final String title;
  final String? description;
  final String? plannedStartDate;
  final String? plannedEndDate;
  final bool isCompleted;
  final bool isCurrent;
  final int sortOrder;

  factory ProjectGanttStepDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttStepDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      statusKey: json['status_key'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      plannedStartDate: json['planned_start_date'] as String?,
      plannedEndDate: json['planned_end_date'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProjectGanttStartResponseDto {
  const ProjectGanttStartResponseDto({
    required this.project,
    required this.ganttSteps,
  });

  final ProjectDto project;
  final List<ProjectGanttStepDto> ganttSteps;

  factory ProjectGanttStartResponseDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttStartResponseDto(
      project: ProjectDto.fromJson(json['project'] as Map<String, dynamic>),
      ganttSteps: (json['gantt_steps'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProjectGanttStepDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ProjectGanttSubStepDto {
  const ProjectGanttSubStepDto({
    required this.id,
    required this.projectId,
    required this.parentStepId,
    required this.title,
    this.description,
    this.plannedStartDate,
    this.plannedEndDate,
    this.assigneeLogin,
    this.assigneeLogins = const [],
    required this.isCompleted,
    required this.sortOrder,
  });

  final String id;
  final String projectId;
  final String parentStepId;
  final String title;
  final String? description;
  final String? plannedStartDate;
  final String? plannedEndDate;
  final String? assigneeLogin;
  final List<String> assigneeLogins;
  final bool isCompleted;
  final int sortOrder;

  factory ProjectGanttSubStepDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttSubStepDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      parentStepId: json['parent_step_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      plannedStartDate: json['planned_start_date'] as String?,
      plannedEndDate: json['planned_end_date'] as String?,
      assigneeLogin: json['assignee_login'] as String?,
      assigneeLogins: (json['assignee_logins'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      isCompleted: json['is_completed'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProjectGanttStepTreeDto extends ProjectGanttStepDto {
  const ProjectGanttStepTreeDto({
    required super.id,
    required super.projectId,
    required super.statusKey,
    required super.title,
    super.description,
    super.plannedStartDate,
    super.plannedEndDate,
    required super.isCompleted,
    required super.isCurrent,
    required super.sortOrder,
    this.subSteps = const [],
  });

  final List<ProjectGanttSubStepDto> subSteps;

  factory ProjectGanttStepTreeDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttStepTreeDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      statusKey: json['status_key'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      plannedStartDate: json['planned_start_date'] as String?,
      plannedEndDate: json['planned_end_date'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      subSteps: (json['sub_steps'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProjectGanttSubStepDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ProjectGanttTreeResponseDto {
  const ProjectGanttTreeResponseDto({
    required this.project,
    required this.ganttSteps,
  });

  final ProjectDto project;
  final List<ProjectGanttStepTreeDto> ganttSteps;

  factory ProjectGanttTreeResponseDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttTreeResponseDto(
      project: ProjectDto.fromJson(json['project'] as Map<String, dynamic>),
      ganttSteps: (json['gantt_steps'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProjectGanttStepTreeDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ProjectOrderItemDto {
  const ProjectOrderItemDto({
    required this.id,
    required this.projectId,
    required this.partId,
    required this.partName,
    this.partNumber,
    required this.quantity,
    required this.selected,
    this.orderStatus = 'In Progress',
    this.orderNumber,
    this.quotationNumber,
    this.shippingNumber,
    this.supplier,
    this.orderedAt,
    this.expectedDeliveryDate,
    this.actualDeliveryDate,
    this.statusNotes,
  });

  final String id;
  final String projectId;
  final String partId;
  final String partName;
  final String? partNumber;
  final int quantity;
  final bool selected;
  final String orderStatus;
  final String? orderNumber;
  final String? quotationNumber;
  final String? shippingNumber;
  final String? supplier;
  final DateTime? orderedAt;
  final DateTime? expectedDeliveryDate;
  final DateTime? actualDeliveryDate;
  final String? statusNotes;

  bool get isOverdue {
    if (orderStatus == 'In Stock' ||
        orderStatus == 'Loaded' ||
        orderStatus == 'Installed') {
      return false;
    }
    final expected = expectedDeliveryDate;
    if (expected == null) {
      return false;
    }
    return expected.isBefore(DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ));
  }

  factory ProjectOrderItemDto.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) {
        return null;
      }
      return DateTime.tryParse(value as String);
    }

    return ProjectOrderItemDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      partId: json['part_id'] as String,
      partName: json['part_name'] as String,
      partNumber: json['part_number'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      selected: json['selected'] as bool? ?? false,
      orderStatus: json['order_status'] as String? ?? 'In Progress',
      orderNumber: json['order_number'] as String?,
      quotationNumber: json['quotation_number'] as String?,
      shippingNumber: json['shipping_number'] as String?,
      supplier: json['supplier'] as String?,
      orderedAt: parseDate(json['ordered_at']),
      expectedDeliveryDate: parseDate(json['expected_delivery_date']),
      actualDeliveryDate: parseDate(json['actual_delivery_date']),
      statusNotes: json['status_notes'] as String?,
    );
  }
}

class PartDrawingDto {
  const PartDrawingDto({
    required this.id,
    required this.partId,
    required this.fileUrl,
    required this.fileName,
  });

  final String id;
  final String partId;
  final String fileUrl;
  final String fileName;

  factory PartDrawingDto.fromJson(Map<String, dynamic> json) {
    return PartDrawingDto(
      id: json['id'] as String,
      partId: json['part_id'] as String,
      fileUrl: json['file_url'] as String,
      fileName: json['file_name'] as String,
    );
  }
}

class PartDto {
  const PartDto({
    required this.id,
    this.parentPartId,
    this.categoryId,
    this.categoryName,
    this.categoryScope,
    this.rivalPartId,
    required this.name,
    this.description,
    this.partSource,
    this.status = 'active',
    this.notes,
    required this.partRole,
    this.imageUrl,
    this.idNumber,
    required this.sellPrice,
    required this.buyPrice,
    this.cadFileUrl,
    this.cadFileName,
    this.instructionsUrl,
    this.instructionsName,
    this.drawings = const [],
  });

  final String id;
  final String? parentPartId;
  final String? categoryId;
  final String? categoryName;
  final String? categoryScope;
  final String? rivalPartId;
  final String name;
  final String? description;
  final String? partSource;
  final String status;
  final String? notes;
  final String partRole;
  final String? imageUrl;
  final String? idNumber;
  final double sellPrice;
  final double buyPrice;
  final String? cadFileUrl;
  final String? cadFileName;
  final String? instructionsUrl;
  final String? instructionsName;
  final List<PartDrawingDto> drawings;

  factory PartDto.fromJson(Map<String, dynamic> json) {
    return PartDto(
      id: json['id'] as String,
      parentPartId: json['parent_part_id'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      categoryScope: json['category_scope'] as String?,
      rivalPartId: json['rival_part_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      partSource: json['part_source'] as String?,
      status: (json['status'] as String? ?? 'active').toLowerCase(),
      notes: json['notes'] as String?,
      partRole: (json['part_role'] as String? ?? 'main').toLowerCase(),
      imageUrl: json['image_url'] as String?,
      idNumber: json['id_number'] as String?,
      sellPrice: (json['sell_price'] as num).toDouble(),
      buyPrice: (json['buy_price'] as num).toDouble(),
      cadFileUrl: json['cad_file_url'] as String?,
      cadFileName: json['cad_file_name'] as String?,
      instructionsUrl: json['instructions_url'] as String?,
      instructionsName: json['instructions_name'] as String?,
      drawings: (json['drawings'] as List<dynamic>? ?? const [])
          .map((item) => PartDrawingDto.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PartCategoryDto {
  const PartCategoryDto({
    required this.id,
    required this.name,
    required this.scope,
  });

  final String id;
  final String name;
  final String scope;

  factory PartCategoryDto.fromJson(Map<String, dynamic> json) {
    return PartCategoryDto(
      id: json['id'] as String,
      name: json['name'] as String,
      scope: (json['scope'] as String).toLowerCase(),
    );
  }
}

class FolderDto {
  const FolderDto({required this.id, required this.name, this.parentFolderId});

  final String id;
  final String name;
  final String? parentFolderId;

  factory FolderDto.fromJson(Map<String, dynamic> json) {
    return FolderDto(
      id: json['id'] as String,
      name: json['name'] as String,
      parentFolderId: json['parent_folder_id'] as String?,
    );
  }
}

class TodoDto {
  const TodoDto({
    required this.id,
    required this.name,
    this.sortOrder,
    this.companyId,
    this.projectId,
    this.folderId,
    this.department,
    this.mainEmployer,
    this.coworkerLogins = const [],
    this.description,
    this.startDate,
    this.endDate,
    this.projectStatus,
  });

  final String id;
  final String name;
  final int? sortOrder;
  final String? companyId;
  final String? projectId;
  final String? folderId;
  final String? department;
  final String? mainEmployer;
  final List<String> coworkerLogins;
  final String? description;
  final String? startDate;
  final String? endDate;
  final String? projectStatus;

  factory TodoDto.fromJson(Map<String, dynamic> json) {
    return TodoDto(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int?,
      companyId: json['organization_id'] as String?,
      projectId: json['project_id'] as String?,
      folderId: json['folder_id'] as String?,
      department: json['department'] as String?,
      mainEmployer: json['main_employer'] as String?,
      coworkerLogins: (json['coworker_logins'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      description: json['description'] as String?,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      projectStatus: json['project_status'] as String?,
    );
  }
}

class EmployeeDto {
  const EmployeeDto({
    required this.id,
    this.companyId,
    required this.firstName,
    required this.lastName,
    this.jobDescription,
    required this.email,
    required this.loginName,
    this.imageUrl,
    this.role,
    this.department,
  });

  final String id;
  final String? companyId;
  final String firstName;
  final String lastName;
  final String? jobDescription;
  final String email;
  final String loginName;
  // Raw disk path from the backend, not a directly-loadable URL. Fetch the
  // actual photo bytes via ApiClient.myProfilePhotoBytes()/employeeImageBytes().
  final String? imageUrl;
  final String? role;
  final String? department;

  factory EmployeeDto.fromJson(Map<String, dynamic> json) {
    return EmployeeDto(
      id: json['id'] as String,
      companyId: json['organization_id'] as String?,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      jobDescription: json['job_description'] as String?,
      email: json['email'] as String,
      loginName: json['login_name'] as String,
      imageUrl: json['image_url'] as String?,
      role: json['role'] as String?,
      department: json['department'] as String?,
    );
  }
}

class CompanyRoleDto {
  const CompanyRoleDto({
    required this.id,
    required this.name,
    required this.permissions,
  });

  final String id;
  final String name;
  final List<String> permissions;

  factory CompanyRoleDto.fromJson(Map<String, dynamic> json) {
    return CompanyRoleDto(
      id: json['id'] as String,
      name: json['name'] as String,
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class DepartmentDto {
  const DepartmentDto({
    required this.id,
    required this.name,
    required this.roleIds,
    required this.roleNames,
    required this.folderTemplates,
    required this.projectActions,
  });

  final String id;
  final String name;
  final List<String> roleIds;
  final List<String> roleNames;
  final List<String> folderTemplates;
  final List<String> projectActions;

  factory DepartmentDto.fromJson(Map<String, dynamic> json) {
    return DepartmentDto(
      id: json['id'] as String,
      name: json['name'] as String,
      roleIds: (json['role_ids'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      roleNames: (json['role_names'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      folderTemplates: (json['folder_templates'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      projectActions: (json['project_actions'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class DocumentDto {
  const DocumentDto({
    required this.id,
    required this.fileName,
    this.mimeType,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String? mimeType;
  final DateTime createdAt;

  factory DocumentDto.fromJson(Map<String, dynamic> json) {
    return DocumentDto(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ProjectOfferRecipientDto {
  const ProjectOfferRecipientDto({
    required this.customerId,
    required this.name,
    this.jobTitle,
    this.email,
    this.isProjectLeader = false,
  });

  final String customerId;
  final String name;
  final String? jobTitle;
  final String? email;
  final bool isProjectLeader;

  factory ProjectOfferRecipientDto.fromJson(Map<String, dynamic> json) {
    return ProjectOfferRecipientDto(
      customerId: json['customer_id'] as String,
      name: json['name'] as String? ?? '',
      jobTitle: json['job_title'] as String?,
      email: json['email'] as String?,
      isProjectLeader: json['is_project_leader'] as bool? ?? false,
    );
  }
}

class ProjectOfferSendResultDto {
  const ProjectOfferSendResultDto({
    required this.customerId,
    required this.name,
    this.email,
    required this.sent,
    required this.detail,
  });

  final String customerId;
  final String name;
  final String? email;
  final bool sent;
  final String detail;

  factory ProjectOfferSendResultDto.fromJson(Map<String, dynamic> json) {
    return ProjectOfferSendResultDto(
      customerId: json['customer_id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      sent: json['sent'] as bool? ?? false,
      detail: json['detail'] as String? ?? '',
    );
  }
}

class DemoTemplateDto {
  const DemoTemplateDto({
    required this.id,
    required this.fileName,
    required this.category,
  });

  final String id;
  final String fileName;
  final String category;

  factory DemoTemplateDto.fromJson(Map<String, dynamic> json) {
    return DemoTemplateDto(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      category: json['category'] as String,
    );
  }
}

class AiSummaryDto {
  const AiSummaryDto({
    required this.summary,
    required this.suggestions,
    this.extractedTextPreview,
  });

  final String summary;
  final List<String> suggestions;
  final String? extractedTextPreview;

  factory AiSummaryDto.fromJson(Map<String, dynamic> json) {
    return AiSummaryDto(
      summary: json['summary'] as String,
      suggestions: (json['suggestions'] as List<dynamic>).cast<String>(),
      extractedTextPreview: json['extracted_text_preview'] as String?,
    );
  }
}

class FolderDepartmentAccessDto {
  const FolderDepartmentAccessDto({
    required this.id,
    required this.departmentId,
    required this.departmentName,
  });

  final String id;
  final String departmentId;
  final String departmentName;

  factory FolderDepartmentAccessDto.fromJson(Map<String, dynamic> json) {
    return FolderDepartmentAccessDto(
      id: json['id'] as String,
      departmentId: json['department_id'] as String,
      departmentName: json['department_name'] as String,
    );
  }
}

class FolderUserAccessDto {
  const FolderUserAccessDto({
    required this.id,
    required this.employeeId,
    required this.employeeName,
  });

  final String id;
  final String employeeId;
  final String employeeName;

  factory FolderUserAccessDto.fromJson(Map<String, dynamic> json) {
    return FolderUserAccessDto(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
    );
  }
}

class FolderAccessDto {
  const FolderAccessDto({
    required this.folderId,
    required this.folderName,
    required this.projectId,
    required this.departmentAccess,
    required this.userAccess,
  });

  final String folderId;
  final String folderName;
  final String projectId;
  final List<FolderDepartmentAccessDto> departmentAccess;
  final List<FolderUserAccessDto> userAccess;

  factory FolderAccessDto.fromJson(Map<String, dynamic> json) {
    return FolderAccessDto(
      folderId: json['folder_id'] as String,
      folderName: json['folder_name'] as String,
      projectId: json['project_id'] as String,
      departmentAccess:
          (json['department_access'] as List<dynamic>? ?? const [])
              .map(
                (e) => FolderDepartmentAccessDto.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList(),
      userAccess: (json['user_access'] as List<dynamic>? ?? const [])
          .map((e) => FolderUserAccessDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ==================== Action System Models ====================

class WorkflowNodeDto {
  const WorkflowNodeDto({
    required this.id,
    required this.name,
    required this.category,
    this.function,
    this.endpoint,
    this.triggerInput,
    required this.configuration,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final String? function;
  final String? endpoint;
  final String? triggerInput;
  final String configuration;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorkflowNodeDto.fromJson(Map<String, dynamic> json) {
    return WorkflowNodeDto(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      function: json['function'] as String?,
      endpoint: json['endpoint'] as String?,
      triggerInput: json['trigger_input'] as String?,
      configuration: json['configuration'] as String? ?? '{}',
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ProjectActionDepartmentDto {
  const ProjectActionDepartmentDto({
    required this.id,
    required this.actionButtonId,
    required this.departmentId,
  });

  final String id;
  final String actionButtonId;
  final String departmentId;

  factory ProjectActionDepartmentDto.fromJson(Map<String, dynamic> json) {
    return ProjectActionDepartmentDto(
      id: json['id'] as String,
      actionButtonId: json['action_button_id'] as String,
      departmentId: json['department_id'] as String,
    );
  }
}

class ProjectActionDto {
  const ProjectActionDto({
    required this.id,
    required this.uniqueName,
    this.description,
    required this.nodeGraph,
    this.workflowStage,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.departments = const [],
  });

  final String id;
  final String uniqueName;
  final String? description;
  final String nodeGraph;
  final String? workflowStage;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProjectActionDepartmentDto> departments;

  factory ProjectActionDto.fromJson(Map<String, dynamic> json) {
    return ProjectActionDto(
      id: json['id'] as String,
      uniqueName: json['unique_name'] as String,
      description: json['description'] as String?,
      nodeGraph: json['node_graph'] as String? ?? '{}',
      workflowStage: json['workflow_stage'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      departments: (json['departments'] as List<dynamic>? ?? const [])
          .map(
            (e) =>
                ProjectActionDepartmentDto.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ProjectActionExecutionDto {
  const ProjectActionExecutionDto({
    required this.id,
    required this.projectId,
    required this.actionButtonId,
    required this.executedByEmployeeId,
    required this.executionStatus,
    this.executionResult,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String actionButtonId;
  final String executedByEmployeeId;
  final String executionStatus;
  final String? executionResult;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory ProjectActionExecutionDto.fromJson(Map<String, dynamic> json) {
    return ProjectActionExecutionDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      actionButtonId: json['action_button_id'] as String,
      executedByEmployeeId: json['executed_by_employee_id'] as String,
      executionStatus: json['execution_status'] as String,
      executionResult: json['execution_result'] as String?,
      errorMessage: json['error_message'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ProjectFolderTemplateDto {
  const ProjectFolderTemplateDto({
    required this.id,
    required this.parentTemplateId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String? parentTemplateId;
  final String name;
  final int sortOrder;

  factory ProjectFolderTemplateDto.fromJson(Map<String, dynamic> json) {
    return ProjectFolderTemplateDto(
      id: json['id'] as String,
      parentTemplateId: json['parent_template_id'] as String?,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class ProjectFolderTemplateDemoFileDto {
  const ProjectFolderTemplateDemoFileDto({
    required this.id,
    required this.folderTemplateId,
    required this.demoTemplateId,
    required this.targetFileName,
    required this.sortOrder,
  });

  final String id;
  final String folderTemplateId;
  final String demoTemplateId;
  final String? targetFileName;
  final int sortOrder;

  factory ProjectFolderTemplateDemoFileDto.fromJson(Map<String, dynamic> json) {
    return ProjectFolderTemplateDemoFileDto(
      id: json['id'] as String,
      folderTemplateId: json['folder_template_id'] as String,
      demoTemplateId: json['demo_template_id'] as String,
      targetFileName: json['target_file_name'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class ProjectGanttSubStepTemplateDto {
  const ProjectGanttSubStepTemplateDto({
    required this.id,
    required this.parentTemplateId,
    required this.title,
    this.description,
    required this.durationDays,
    required this.sortOrder,
  });

  final String id;
  final String parentTemplateId;
  final String title;
  final String? description;
  final int durationDays;
  final int sortOrder;

  factory ProjectGanttSubStepTemplateDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttSubStepTemplateDto(
      id: json['id'] as String,
      parentTemplateId: json['parent_template_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 1,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProjectGanttStepTemplateDto {
  const ProjectGanttStepTemplateDto({
    required this.id,
    required this.companyId,
    required this.statusKey,
    required this.title,
    this.description,
    required this.durationDays,
    required this.sortOrder,
    this.subStepTemplates = const [],
  });

  final String id;
  final String companyId;
  final String statusKey;
  final String title;
  final String? description;
  final int durationDays;
  final int sortOrder;
  final List<ProjectGanttSubStepTemplateDto> subStepTemplates;

  factory ProjectGanttStepTemplateDto.fromJson(Map<String, dynamic> json) {
    return ProjectGanttStepTemplateDto(
      id: json['id'] as String,
      companyId: json['organization_id'] as String,
      statusKey: json['status_key'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 7,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      subStepTemplates: (json['sub_step_templates'] as List<dynamic>? ?? [])
          .map(
            (item) => ProjectGanttSubStepTemplateDto.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class AiServerConfigDto {
  const AiServerConfigDto({
    required this.name,
    required this.provider,
    required this.baseUrl,
    this.apiKey,
    this.model,
  });

  final String name;
  final String provider; // 'ollama' | 'openai_compatible'
  final String baseUrl;
  final String? apiKey;
  final String? model;

  factory AiServerConfigDto.fromJson(Map<String, dynamic> json) {
    return AiServerConfigDto(
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String? ?? 'ollama',
      baseUrl: json['base_url'] as String? ?? '',
      apiKey: json['api_key'] as String?,
      model: json['model'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'provider': provider,
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
    };
  }
}

class ServerSettingsDto {
  const ServerSettingsDto({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpUseTls,
    required this.mailFrom,
    required this.hasSmtpPassword,
    required this.aiServers,
  });

  final String? smtpHost;
  final int? smtpPort;
  final String? smtpUsername;
  final bool smtpUseTls;
  final String? mailFrom;
  final bool hasSmtpPassword;
  final List<AiServerConfigDto> aiServers;

  factory ServerSettingsDto.fromJson(Map<String, dynamic> json) {
    return ServerSettingsDto(
      smtpHost: json['smtp_host'] as String?,
      smtpPort: json['smtp_port'] as int?,
      smtpUsername: json['smtp_username'] as String?,
      smtpUseTls: json['smtp_use_tls'] as bool? ?? true,
      mailFrom: json['mail_from'] as String?,
      hasSmtpPassword: json['has_smtp_password'] as bool? ?? false,
      aiServers: (json['ai_servers'] as List<dynamic>? ?? [])
          .map(
            (item) => AiServerConfigDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class EmployeeMailSettingsDto {
  const EmployeeMailSettingsDto({
    required this.imapHost,
    required this.imapPort,
    required this.imapUsername,
    required this.imapUseSsl,
    required this.draftsFolder,
    required this.hasPassword,
  });

  final String? imapHost;
  final int imapPort;
  final String? imapUsername;
  final bool imapUseSsl;
  final String draftsFolder;
  final bool hasPassword;

  factory EmployeeMailSettingsDto.fromJson(Map<String, dynamic> json) {
    return EmployeeMailSettingsDto(
      imapHost: json['imap_host'] as String?,
      imapPort: json['imap_port'] as int? ?? 993,
      imapUsername: json['imap_username'] as String?,
      imapUseSsl: json['imap_use_ssl'] as bool? ?? true,
      draftsFolder: json['drafts_folder'] as String? ?? 'Drafts',
      hasPassword: json['has_password'] as bool? ?? false,
    );
  }
}

class ManufacturerDto {
  const ManufacturerDto({
    required this.id,
    required this.companyId,
    required this.name,
    this.website,
    this.contactEmail,
    this.phoneNumber,
    this.notes,
  });

  final String id;
  final String companyId;
  final String name;
  final String? website;
  final String? contactEmail;
  final String? phoneNumber;
  final String? notes;

  factory ManufacturerDto.fromJson(Map<String, dynamic> json) {
    return ManufacturerDto(
      id: json['id'] as String,
      companyId: json['organization_id'] as String,
      name: json['name'] as String,
      website: json['website'] as String?,
      contactEmail: json['contact_email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class PartOrderDecisionDto {
  const PartOrderDecisionDto({
    required this.id,
    required this.projectId,
    required this.partId,
    required this.partName,
    this.partNumber,
    required this.decision,
    required this.orderId,
    this.manufacturerId,
    this.manufacturerName,
    required this.quantity,
    required this.placedAt,
    this.notes,
  });

  final String id;
  final String projectId;
  final String partId;
  final String partName;
  final String? partNumber;
  final String decision; // 'Storage' | 'Self Manufacture' | 'Order'
  final String orderId;
  final String? manufacturerId;
  final String? manufacturerName;
  final int quantity;
  final DateTime placedAt;
  final String? notes;

  factory PartOrderDecisionDto.fromJson(Map<String, dynamic> json) {
    return PartOrderDecisionDto(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      partId: json['part_id'] as String,
      partName: json['part_name'] as String,
      partNumber: json['part_number'] as String?,
      decision: json['decision'] as String,
      orderId: json['order_id'] as String,
      manufacturerId: json['manufacturer_id'] as String?,
      manufacturerName: json['manufacturer_name'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      placedAt: DateTime.parse(json['placed_at'] as String),
      notes: json['notes'] as String?,
    );
  }
}
