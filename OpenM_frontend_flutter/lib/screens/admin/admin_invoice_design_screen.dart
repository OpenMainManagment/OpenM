import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../widgets/app_shell.dart';

/// Admin screen for designing invoices according to German law requirements
///
/// German invoice requirements (UStG, § 14 UStG):
/// - Full name and address of supplier and customer
/// - Tax number or VAT ID (USt-IdNr.)
/// - Invoice number (unique, sequential)
/// - Invoice date
/// - Delivery/performance date
/// - Quantity and type of goods/services
/// - Net amount, tax rate, gross amount
/// - Tax exemption note if applicable
class AdminInvoiceDesignScreen extends ConsumerWidget {
  const AdminInvoiceDesignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      pageName: 'Invoice Design',
      onAdd: () {},
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildQuickActions(context),
            const SizedBox(height: 24),
            _buildInvoiceSections(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Invoice Design',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Design invoice templates according to German law requirements',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showTemplateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Template'),
            ),
            ElevatedButton.icon(
              onPressed: () => _showPreviewDialog(context),
              icon: const Icon(Icons.visibility),
              label: const Text('Preview Invoice'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showSettingsDialog(context),
              icon: const Icon(Icons.settings),
              label: const Text('Settings'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceSections(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Invoice Sections',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          context,
          title: 'Header Section',
          subtitle: 'Company logo, name, and address',
          icon: Icons.business,
          onTap: () => _showSectionEditor(context, 'Header'),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          context,
          title: 'Customer Information',
          subtitle: 'Customer details and billing address',
          icon: Icons.person,
          onTap: () => _showSectionEditor(context, 'Customer'),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          context,
          title: 'Invoice Details',
          subtitle: 'Invoice number, date, and tax information',
          icon: Icons.receipt,
          onTap: () => _showSectionEditor(context, 'Invoice Details'),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          context,
          title: 'Line Items',
          subtitle: 'Products and services table',
          icon: Icons.list,
          onTap: () => _showSectionEditor(context, 'Line Items'),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          context,
          title: 'Totals & Tax',
          subtitle: 'Subtotals, VAT, and final amounts',
          icon: Icons.attach_money,
          onTap: () => _showSectionEditor(context, 'Totals'),
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          context,
          title: 'Footer',
          subtitle: 'Payment terms, bank details, legal notes',
          icon: Icons.arrow_downward,
          onTap: () => _showSectionEditor(context, 'Footer'),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showTemplateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Invoice Template'),
        content: const Text(
          'Choose a template to start with:Standard German Invoice (Umsatzsteuer-Rechnung) • Reduced VAT Invoice (ermäßigte MwSt.)Small Business Invoice (Kleinunternehmer)• Custom Template',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Template creation coming soon')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPreviewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invoice Preview'),
        content: SizedBox(
          width: 400,
          child: AspectRatio(
            aspectRatio: 1 / 1.414, // A4 ratio
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Company',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text('Street 123'),
                          const Text('12345 City'),
                          const Text('Germany'),
                        ],
                      ),
                      const Text(
                        'RECHNUNG',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Rechnungs-Nr.: 2024-001'),
                  Text(
                    'Rechnungsdatum: ${DateTime.now().toString().split(' ')[0]}',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Rechnungsempfänger:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text('Customer Name'),
                  const Text('Customer Street'),
                  const Text('Customer City'),
                  const SizedBox(height: 24),
                  const Text(
                    'Positionen:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('Service Description'), Text('100,00 €')],
                    ),
                  ),
                  const Spacer(),
                  const Divider(),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('Zwischensumme:'), Text('100,00 €')],
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('MwSt. (19%):'), Text('19,00 €')],
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Gesamtbetrag:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '119,00 €',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download PDF coming soon')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('Download PDF'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invoice Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Default VAT Rate:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              initialValue: 19.0,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixText: "",
              ),
              items: const [
                DropdownMenuItem(value: 19.0, child: Text('19% (Standard)')),
                DropdownMenuItem(value: 7.0, child: Text('7% (Reduced)')),
                DropdownMenuItem(value: 0.0, child: Text('0% (Exempt)')),
              ],
              onChanged: (value) {},
            ),
            const SizedBox(height: 16),
            const Text(
              'Invoice Numbering:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text('Pattern: YYYY-####'),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Show VAT ID (USt-IdNr.)'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Show Tax Number'),
              value: true,
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Settings saved')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSectionEditor(BuildContext context, String section) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Edit $section section coming soon')),
    );
  }
}
