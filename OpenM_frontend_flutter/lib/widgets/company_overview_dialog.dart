import 'package:flutter/material.dart';

import '../models/dtos.dart';

String _displayCompanyValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '-' : text;
}

Future<void> showCompanyOverviewDialog({
  required BuildContext context,
  required CompanyDto company,
  required Future<void> Function() onEdit,
  required Future<void> Function() onManageCustomers,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Client Company Overview'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                company.uniqueName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Client company name: ${_displayCompanyValue(company.uniqueName)}',
              ),
              const SizedBox(height: 6),
              Text('Unique ID: ${_displayCompanyValue(company.uniqueCode)}'),
              const SizedBox(height: 6),
              Text('Client company ID: ${_displayCompanyValue(company.id)}'),
              const SizedBox(height: 6),
              Text('Street: ${_displayCompanyValue(company.street)}'),
              const SizedBox(height: 6),
              Text(
                'House number: ${_displayCompanyValue(company.houseNumber)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Head of client company: ${_displayCompanyValue(company.headOfCompany)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Contact email: ${_displayCompanyValue(company.contactEmail)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Phone number: ${_displayCompanyValue(company.phoneNumber)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Head customer: ${_displayCompanyValue(company.headOfCompany)}',
              ),
              const SizedBox(height: 6),
              Text(
                'Test customers: ${company.customers.isEmpty ? '-' : company.customers.map((customer) => customer.fullName).join(', ')}',
              ),
              const SizedBox(height: 6),
              Text(
                'Head customer id: ${_displayCompanyValue(company.mainCustomerId)}',
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await onManageCustomers();
          },
          child: const Text('Customers'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await onEdit();
          },
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Back'),
        ),
      ],
    ),
  );
}
