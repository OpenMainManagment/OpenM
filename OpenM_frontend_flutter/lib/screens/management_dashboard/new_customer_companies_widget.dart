import 'package:openm/screens/management_dashboard/dashboard_widget_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_client.dart';

/// Example/test widget built on [DashboardWidgetTemplate]: shows how many
/// new customer companies came in during the selected time span, as a line
/// chart by default (the template also lets the employee switch it to a
/// bar or pie chart).
class NewCustomerCompaniesWidget extends ConsumerWidget {
  const NewCustomerCompaniesWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardWidgetTemplate(
      name: 'New Customer Companies',
      description: 'How many new customer companies came in over time.',
      valueLabel: 'Companies',
      initialChartType: DashboardChartType.line,
      dataLoader: (range) async {
        final api = ref.read(apiClientProvider);
        final companies = await api.clientCompanies();
        final creationDates = companies
            .map((company) => company.createdAt)
            .whereType<DateTime>()
            .toList();
        return range.bucketCounts(creationDates);
      },
    );
  }
}
