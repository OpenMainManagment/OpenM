enum ProjectStatusEnum {
  quote,
  sale,
  construction,
  procurement,
  installation,
  programming,
  delivery,
  commissioning,
  finalAcceptance,
  completed;

  static ProjectStatusEnum fromString(String status) {
    switch (status) {
      case 'Quote':
        return ProjectStatusEnum.quote;
      case 'Sale':
        return ProjectStatusEnum.sale;
      case 'Construction':
        return ProjectStatusEnum.construction;
      case 'Procurement':
        return ProjectStatusEnum.procurement;
      case 'Installation':
        return ProjectStatusEnum.installation;
      case 'Programming':
        return ProjectStatusEnum.programming;
      case 'Delivery':
        return ProjectStatusEnum.delivery;
      case 'Commissioning':
        return ProjectStatusEnum.commissioning;
      case 'Final Acceptance':
        return ProjectStatusEnum.finalAcceptance;
      case 'Completed':
        return ProjectStatusEnum.completed;
      default:
        return ProjectStatusEnum.quote; // Default fallback
    }
  }

  String get displayName {
    switch (this) {
      case ProjectStatusEnum.quote:
        return 'Quote';
      case ProjectStatusEnum.sale:
        return 'Sale';
      case ProjectStatusEnum.construction:
        return 'Construction';
      case ProjectStatusEnum.procurement:
        return 'Procurement';
      case ProjectStatusEnum.installation:
        return 'Installation';
      case ProjectStatusEnum.programming:
        return 'Programming';
      case ProjectStatusEnum.delivery:
        return 'Delivery';
      case ProjectStatusEnum.commissioning:
        return 'Commissioning';
      case ProjectStatusEnum.finalAcceptance:
        return 'Final Acceptance';
      case ProjectStatusEnum.completed:
        return 'Completed';
    }
  }

  int get statusIndex {
    switch (this) {
      case ProjectStatusEnum.quote:
        return 0;
      case ProjectStatusEnum.sale:
        return 1;
      case ProjectStatusEnum.construction:
        return 2;
      case ProjectStatusEnum.procurement:
        return 3;
      case ProjectStatusEnum.installation:
        return 4;
      case ProjectStatusEnum.programming:
        return 5;
      case ProjectStatusEnum.delivery:
        return 6;
      case ProjectStatusEnum.commissioning:
        return 7;
      case ProjectStatusEnum.finalAcceptance:
        return 8;
      case ProjectStatusEnum.completed:
        return 9;
    }
  }
}