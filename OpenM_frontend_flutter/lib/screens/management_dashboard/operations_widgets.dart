import 'package:openm/models/dtos.dart';
import 'package:openm/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<List<ProjectDto>> _loadDashboardProjects(ApiClient api) async {
  final companies = await api.clientCompanies();
  final projects = await Future.wait(
    companies.map((company) => api.projectsByClientCompany(company.id)),
  );
  return projects.expand((items) => items).toList();
}

class ShippingDashboardWidget extends ConsumerWidget {
  const ShippingDashboardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardDataCard(
      title: 'Shipping Pipeline',
      description: 'Parts that are ordered, in transit, overdue, or delivered.',
      icon: Icons.local_shipping_outlined,
      loader: () async {
        final api = ref.read(apiClientProvider);
        final projects = await _loadDashboardProjects(api);
        final orders = await Future.wait(
          projects.map((project) => api.projectOrderItems(project.id)),
        );
        final items = orders.expand((projectItems) => projectItems);
        final shipping = <String, int>{
          'Ordered': 0,
          'In transit': 0,
          'Overdue': 0,
          'Delivered': 0,
        };
        for (final item in items) {
          if (item.orderStatus == 'In Stock' ||
              item.orderStatus == 'Loaded' ||
              item.orderStatus == 'Installed') {
            shipping['Delivered'] = shipping['Delivered']! + 1;
          } else if (item.isOverdue) {
            shipping['Overdue'] = shipping['Overdue']! + 1;
          } else if (item.shippingNumber != null &&
              item.shippingNumber!.trim().isNotEmpty) {
            shipping['In transit'] = shipping['In transit']! + 1;
          } else {
            shipping['Ordered'] = shipping['Ordered']! + 1;
          }
        }
        return shipping;
      },
    );
  }
}

class OrderToBuildDashboardWidget extends ConsumerWidget {
  const OrderToBuildDashboardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardDataCard(
      title: 'Order to Build Time',
      description: 'Average days from the first ordered part to build start.',
      icon: Icons.timelapse_outlined,
      loader: () async {
        final api = ref.read(apiClientProvider);
        final projects = await _loadDashboardProjects(api);
        final durations = <int>[];
        for (final project in projects) {
          final orderItems = await api.projectOrderItems(project.id);
          final orderedDates = orderItems
              .map((item) => item.orderedAt)
              .whereType<DateTime>()
              .toList();
          final firstOrdered = orderedDates.isEmpty
              ? null
              : orderedDates.reduce(
                  (first, date) => date.isBefore(first) ? date : first,
                );
          final buildStart = project.ganttStartedAt == null
              ? null
              : DateTime.tryParse(project.ganttStartedAt!);
          if (firstOrdered != null && buildStart != null) {
            durations.add(buildStart.difference(firstOrdered).inDays);
          }
        }
        final average = durations.isEmpty
            ? 0
            : (durations.reduce((a, b) => a + b) / durations.length).round();
        return {
          'Average days': average,
          'Projects measured': durations.length,
        };
      },
    );
  }
}

class ProjectWorkHoursDashboardWidget extends ConsumerWidget {
  const ProjectWorkHoursDashboardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardDataCard(
      title: 'Project Work Hours',
      description: 'Planned work hours from Gantt dates (8 hours per workday).',
      icon: Icons.engineering_outlined,
      loader: () async {
        final api = ref.read(apiClientProvider);
        final projects = await _loadDashboardProjects(api);
        var totalHours = 0;
        var projectsWithPlan = 0;
        for (final project in projects) {
          final tree = await api.projectGanttTree(project.id);
          var projectHours = 0;
          for (final step in tree.ganttSteps) {
            final start = _parseDate(step.plannedStartDate);
            final end = _parseDate(step.plannedEndDate);
            if (start != null && end != null) {
              projectHours += _workdaysInclusive(start, end) * 8;
            }
          }
          if (projectHours > 0) {
            projectsWithPlan++;
            totalHours += projectHours;
          }
        }
        return {
          'Planned hours': totalHours,
          'Projects with a plan': projectsWithPlan,
        };
      },
    );
  }
}

DateTime? _parseDate(String? value) {
  return value == null ? null : DateTime.tryParse(value);
}

int _workdaysInclusive(DateTime start, DateTime end) {
  if (end.isBefore(start)) return 0;
  var days = 0;
  for (var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))) {
    if (date.weekday <= DateTime.friday) days++;
  }
  return days;
}

class _DashboardDataCard extends StatelessWidget {
  const _DashboardDataCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.loader,
  });

  final String title;
  final String description;
  final IconData icon;
  final Future<Map<String, int>> Function() loader;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, int>>(
          future: loader(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DashboardError(title: title, error: snapshot.error!);
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 130,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final entry in snapshot.data!.entries)
                      _Metric(label: entry.key, value: '${entry.value}'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Could not load dashboard data: $error'),
      ],
    );
  }
}
