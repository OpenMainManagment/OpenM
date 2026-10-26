import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class L10n {
  const L10n(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  static L10n? of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n);
  }

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'actions': 'Actions',
      'actionButtons': 'Action Buttons',
      'workflowNodes': 'Workflow Nodes',
      'createNew': 'Create New',
      'createActionButton': 'Create Action Button',
      'editActionButton': 'Edit Action Button',
      'createWorkflowNode': 'Create Workflow Node',
      'editWorkflowNode': 'Edit Workflow Node',
      'name': 'Name',
      'description': 'Description',
      'workflowStage': 'Workflow Stage',
      'active': 'Active',
      'nodeEditorPlaceholder': 'Node editor will be added here.',
      'cancel': 'Cancel',
      'save': 'Save',
      'function': 'Function',
      'endpoint': 'Endpoint',
      'addFunctions': 'Add Functions',
      'information': 'Information',
      'todos': 'Todos',
      'aiEntryPoint': 'AI Entry Point',
      'noActionsAvailable': 'No actions available',
      'projectActions': 'Project Actions',
      'executionHistory': 'Execution History',
      'execute': 'Execute',
      'actionExecutedSuccessfully': 'Action executed successfully',
      'close': 'Close',
      'noDescription': 'No description',
      'noExecutions': 'No executions yet',
      'executionDetails': 'Execution Details',
      'status': 'Status',
      'created': 'Created',
      'started': 'Started',
      'completed': 'Completed',
      'error': 'Error',
      'running': 'Running',
      'success': 'Success',
      'failed': 'Failed',
      'pending': 'Pending',
      'cancelled': 'Cancelled',
      'nodeEditor': 'Node Editor',
      'openNodeEditor': 'Open Node Editor',
      'projectActionDepartments': 'Departments',
      'noDepartmentsAvailable': 'No departments available',
    },
    'de': {
      'actions': 'Aktionen',
      'actionButtons': 'Aktionsschaltflächen',
      'workflowNodes': 'Workflow-Knoten',
      'createNew': 'Neu erstellen',
      'createActionButton': 'Aktionsschaltfläche erstellen',
      'editActionButton': 'Aktionsschaltfläche bearbeiten',
      'createWorkflowNode': 'Workflow-Knoten erstellen',
      'editWorkflowNode': 'Workflow-Knoten bearbeiten',
      'name': 'Name',
      'description': 'Beschreibung',
      'workflowStage': 'Workflow-Phase',
      'active': 'Aktiv',
      'nodeEditorPlaceholder': 'Der Node-Editor wird hier hinzugefügt.',
      'cancel': 'Abbrechen',
      'save': 'Speichern',
      'function': 'Funktion',
      'endpoint': 'Endpunkt',
      'addFunctions': 'Funktionen hinzufügen',
      'information': 'Informationen',
      'todos': 'Aufgaben',
      'aiEntryPoint': 'KI-Einstiegspunkt',
      'noActionsAvailable': 'Keine Aktionen verfügbar',
      'projectActions': 'Projektaktionen',
      'executionHistory': 'Ausführungsverlauf',
      'execute': 'Ausführen',
      'actionExecutedSuccessfully': 'Aktion erfolgreich ausgeführt',
      'close': 'Schließen',
      'noDescription': 'Keine Beschreibung',
      'noDepartmentsAvailable': 'Keine Abteilungen verfügbar',
      'projectActionDepartments': 'Abteilungen',
      'noExecutions': 'Noch keine Ausführungen',
      'executionDetails': 'Ausführungsdetails',
      'status': 'Status',
      'created': 'Erstellt',
      'started': 'Gestartet',
      'completed': 'Abgeschlossen',
      'error': 'Fehler',
      'running': 'Laufend',
      'success': 'Erfolgreich',
      'failed': 'Fehlgeschlagen',
      'pending': 'Ausstehend',
      'cancelled': 'Abgebrochen',
      'nodeEditor': 'Node-Editor',
      'openNodeEditor': 'Node-Editor öffnen',
    },
  };

  String translate(String key) {
    final language = _translations[locale.languageCode] ?? _translations['en']!;
    return language[key] ?? _translations['en']![key] ?? key;
  }
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'de'].contains(locale.languageCode);

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(L10n(locale));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

/// Simple getter-based localization used by newer screens
/// (e.g. AdminActionsScreen). Kept alongside [L10n] above, which
/// older screens still use via `.translate('key')`.
class AppLocalizations {
  AppLocalizations([this.context]);

  final BuildContext? context;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // This is a placeholder implementation - in a real app, this would be auto-generated
  String get appTitle => 'OpenM Admin Panel';
  String get actions => 'Actions';
  String get workflowNodes => 'Workflow Nodes';
  String get addNewAction => 'Add New Action';
  String get cancel => 'Cancel';
  String get save => 'Save';
  String get delete => 'Delete';
  String get edit => 'Edit';
  String get confirm => 'Confirm';
  String get areYouSure => 'Are you sure?';
  String get yes => 'Yes';
  String get no => 'No';
  String get createProjectAction => 'Create Project Action';
  String get editProjectAction => 'Edit Project Action';
  String get name => 'Name';
  String get description => 'Description';
  String get workflowStage => 'Workflow Stage';
  String get active => 'Active';
  String get create => 'Create';
  String get update => 'Update';
  String get createNewNode => 'Create New Node';
  String get createWorkflowNode => 'Create Workflow Node';
  String get editWorkflowNode => 'Edit Workflow Node';
  String get type => 'Type';
  String get category => 'Category';
  String get nodeEditor => 'Node Editor';
  String get workflowUpdated => 'Workflow updated successfully';
  String get workflowCreated => 'Workflow created successfully';
  String get error => 'An error occurred';
  String get editWorkflow => 'Edit Workflow';
  String get createWorkflow => 'Create Workflow';
  String get workflowName => 'Workflow Name';
  String get workflowDescription => 'Workflow Description';
  String get enterWorkflowName => 'Please enter a workflow name';
  String get enterWorkflowDescription => 'Please enter a workflow description';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'de'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations());
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
