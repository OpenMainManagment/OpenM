import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'models/dtos.dart';
import 'screens/management_dashboard/dashboard_screen.dart';
import 'screens/user/companies_screen.dart';
import 'screens/user/project_overview_screen.dart';
import 'services/api_client.dart';

void main() {
  final screen = switch (Uri.base.queryParameters['screen']) {
    'projects' => const ProjectOverviewScreen(),
    'dashboard' => const _ScreenshotDashboard(),
    _ => const CompaniesScreen(),
  };

  runApp(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_ScreenshotApiClient())],
      child: MaterialApp(
        title: 'OpenM Screenshot Preview',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: screen,
      ),
    ),
  );
}

class _ScreenshotApiClient extends ApiClient {
  _ScreenshotApiClient() : super(Dio());

  static DateTime get _sampleToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static final _companies = [
    CompanyDto(
      id: 'company-nordstern',
      uniqueName: 'Nordstern Automation',
      uniqueCode: 'NSA-2401',
      createdAt: _sampleToday,
    ),
    CompanyDto(
      id: 'company-wiesenwerk',
      uniqueName: 'Wiesenwerk Technik',
      uniqueCode: 'WWT-1082',
      createdAt: _sampleToday,
    ),
    CompanyDto(
      id: 'company-aurelia',
      uniqueName: 'Aurelia Maschinenbau',
      uniqueCode: 'AMB-7720',
      createdAt: _sampleToday,
    ),
  ];

  static const _projects = [
    ProjectDto(
      id: 'PRJ-2026-014',
      companyId: 'NSA-2401',
      name: 'Automated Assembly Line',
      status: 'Construction',
      workflowStage: 'project',
      baseModel: 'Standard',
      ganttStarted: true,
    ),
    ProjectDto(
      id: 'PRJ-2026-021',
      companyId: 'WWT-1082',
      name: 'Generation 3 Test Bench',
      status: 'Procurement',
      workflowStage: 'project',
      baseModel: 'Standard',
      ganttStarted: false,
    ),
  ];

  static const _todos = [
    TodoDto(
      id: 'todo-quote',
      name: 'Review proposal',
      endDate: '2026-11-12',
      projectStatus: 'inWork',
    ),
    TodoDto(
      id: 'todo-drawings',
      name: 'Approve drawings',
      endDate: '2026-11-13',
      projectStatus: 'inWork',
    ),
    TodoDto(
      id: 'todo-delivery',
      name: 'Confirm delivery date',
      endDate: '2026-11-14',
      projectStatus: 'overdue',
    ),
  ];

  @override
  Future<List<ClientCompanyDto>> clientCompanies({String? search}) async {
    if (search == null || search.isEmpty) return _companies;
    return _companies
        .where(
          (company) =>
              company.uniqueName.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
  }

  @override
  Future<List<TodoDto>> todos({
    String? companyId,
    String? clientCompanyId,
    String? projectId,
    String? folderId,
  }) async => _todos;

  @override
  Future<EmployeeDto> getCurrentEmployee() async => const EmployeeDto(
    id: 'employee-demo',
    companyId: 'org-demo',
    firstName: 'Mara',
    lastName: 'Beispiel',
    email: 'mara@example.test',
    loginName: 'mara.beispiel',
  );

  @override
  Future<List<ProjectDto>> projectsByMainCompany(
    String mainCompanyId, {
    String? search,
  }) async => _projects;
}

class _ScreenshotDashboard extends StatefulWidget {
  const _ScreenshotDashboard();

  @override
  State<_ScreenshotDashboard> createState() => _ScreenshotDashboardState();
}

class _ScreenshotDashboardState extends State<_ScreenshotDashboard> {
  late final Future<void> _configure = _selectDashboardWidget();

  Future<void> _selectDashboardWidget() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('dashboard.widgets.default', ['overview']);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _configure,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not prepare screenshot: ${snapshot.error}'),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return const ManagementDashboardScreen();
      },
    );
  }
}
