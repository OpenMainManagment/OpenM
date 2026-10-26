import 'package:openm/screens/management_dashboard/new_customer_companies_widget.dart';
import 'package:openm/screens/management_dashboard/operations_widgets.dart';
import 'package:openm/widgets/management_dashboard/overview_widget.dart';
import 'package:openm/widgets/management_dashboard/stats_widget.dart';
import 'package:flutter/material.dart';

/// One entry in the catalog of widgets an employee can add to their
/// Management Dashboard.
class DashboardWidgetCatalogEntry {
  const DashboardWidgetCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.builder,
  });

  /// Stable id used to persist which widgets an employee has chosen.
  /// Never change an existing entry's id, or employees' saved
  /// selections referencing it will silently stop matching.
  final String id;
  final String name;
  final String description;
  final Widget Function() builder;
}

/// All widgets available to add to the Management Dashboard. Add new
/// widget templates here (see new_customer_companies_widget.dart for an
/// example built on DashboardWidgetTemplate) to make them selectable.
final List<DashboardWidgetCatalogEntry> dashboardWidgetCatalog = [
  const DashboardWidgetCatalogEntry(
    id: 'overview',
    name: 'Overview',
    description: 'Quick summary of key metrics and system status.',
    builder: OverviewWidget.new,
  ),
  const DashboardWidgetCatalogEntry(
    id: 'stats',
    name: 'Statistics',
    description: 'Performance and usage statistics.',
    builder: StatsWidget.new,
  ),
  const DashboardWidgetCatalogEntry(
    id: 'new_customer_companies',
    name: 'New Customer Companies',
    description: 'How many new customer companies came in over time.',
    builder: NewCustomerCompaniesWidget.new,
  ),
  const DashboardWidgetCatalogEntry(
    id: 'shipping_pipeline',
    name: 'Shipping Pipeline',
    description: 'Track ordered, in-transit, overdue, and delivered parts.',
    builder: ShippingDashboardWidget.new,
  ),
  const DashboardWidgetCatalogEntry(
    id: 'order_to_build_time',
    name: 'Order to Build Time',
    description: 'Average time from ordering parts to starting the build.',
    builder: OrderToBuildDashboardWidget.new,
  ),
  const DashboardWidgetCatalogEntry(
    id: 'project_work_hours',
    name: 'Project Work Hours',
    description: 'Planned project hours calculated from Gantt workdays.',
    builder: ProjectWorkHoursDashboardWidget.new,
  ),
];

/// Widgets shown by default for an employee who hasn't customized their
/// dashboard yet.
const List<String> defaultDashboardWidgetIds = [
  'overview',
  'stats',
  'new_customer_companies',
];
