import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class CompanyCustomersScreen extends ConsumerStatefulWidget {
  const CompanyCustomersScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  final String companyId;
  final String companyName;

  @override
  ConsumerState<CompanyCustomersScreen> createState() =>
      _CompanyCustomersScreenState();
}

class _CompanyCustomersScreenState
    extends ConsumerState<CompanyCustomersScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _loading = true;
  CompanyDto? _company;
  String? _error;

  String _display(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final companies = await ref.read(apiClientProvider).companies();
      final matches = companies
          .where((item) => item.id == widget.companyId)
          .toList();
      final company = matches.isEmpty ? null : matches.first;
      if (!mounted) {
        return;
      }
      if (company == null) {
        setState(() {
          _company = null;
          _error = 'Company not found.';
        });
        return;
      }
      setState(() {
        _company = company;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final detail = error.response?.data;
      setState(() {
        _error = detail is Map && detail['detail'] != null
            ? '${detail['detail']}'
            : 'Could not load company customers.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Could not load company customers.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Future<void> _scanBusinessCard(
    _CustomerFormData data,
    void Function(void Function()) setDialogState,
  ) async {
    List<int>? bytes;
    String fileName = 'business_card.jpg';

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      if (photo != null) {
        bytes = await photo.readAsBytes();
        fileName = photo.name;
      }
    } catch (_) {
      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera is not available in this browser.'),
            ),
          );
        }
        return;
      }
    }

    if (bytes == null) {
      if (kIsWeb) {
        return;
      }
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.image,
      );
      final file = picked?.files.single;
      if (file == null || file.bytes == null) {
        return;
      }
      bytes = file.bytes!;
      fileName = file.name;
    }

    try {
      final extractedText = await ref
          .read(apiClientProvider)
          .extractBusinessCardText(bytes: bytes, fileName: fileName);
      if (extractedText.trim().isEmpty) {
        return;
      }
      _applyBusinessCardText(data, extractedText);
      setDialogState(() {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Business card scanned.')));
      }
    } on DioException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not scan business card.')),
        );
      }
    }
  }

  void _applyBusinessCardText(_CustomerFormData data, String extractedText) {
    final normalizedText = extractedText.replaceAll('\r', '\n');
    final lines = normalizedText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final emailMatch = RegExp(
      r'[\w.+-]+@[\w-]+\.[\w.-]+',
      caseSensitive: false,
    ).firstMatch(extractedText);
    if (emailMatch != null) {
      data.emailCtrl.text = emailMatch.group(0) ?? data.emailCtrl.text;
    }

    final phoneMatches = RegExp(
      r'(?:\+?\d[\d\s()./-]{5,}\d)',
    ).allMatches(extractedText).map((match) => match.group(0)!.trim()).toList();
    if (phoneMatches.isNotEmpty) {
      data.phoneCtrl.text = phoneMatches.first;
      if (phoneMatches.length > 1) {
        data.mobileCtrl.text = phoneMatches[1];
      }
    }

    final roleKeywords = [
      'manager',
      'sales',
      'ceo',
      'founder',
      'director',
      'owner',
      'head',
      'geschäftsführer',
      'leitung',
    ];

    String? nameLine;
    String? roleLine;
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (nameLine == null &&
          !lower.contains('@') &&
          !RegExp(r'\d').hasMatch(line) &&
          !lower.contains('www.') &&
          !lower.contains('tel') &&
          !lower.contains('fax') &&
          !lower.contains('phone') &&
          !lower.contains('mobile') &&
          line.split(' ').length >= 2) {
        nameLine = line;
        continue;
      }
      if (roleLine == null &&
          roleKeywords.any(lower.contains) &&
          !lower.contains('@')) {
        roleLine = line;
      }
      if (nameLine != null && roleLine != null) {
        break;
      }
    }

    if (nameLine != null) {
      final parts = nameLine
          .replaceAll(
            RegExp(r'^(Herr|Frau|Mr\.?|Ms\.?|Mrs\.?)\s+', caseSensitive: false),
            '',
          )
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        data.firstNameCtrl.text = parts.first;
        data.lastNameCtrl.text = parts.length > 1
            ? parts.skip(1).join(' ')
            : '';
      }
      final lowerName = nameLine.toLowerCase();
      if (lowerName.startsWith('herr')) {
        data.gender = 'Herr';
      } else if (lowerName.startsWith('frau')) {
        data.gender = 'Frau';
      }
    }

    if (roleLine != null) {
      data.roleCtrl.text = roleLine;
    }
  }

  Future<void> _openCustomerEditor() async {
    final company = _company;
    if (company == null) {
      return;
    }

    final customerCtrls = List.generate(3, (index) {
      final customer = index < company.customers.length
          ? company.customers[index]
          : null;
      return _CustomerFormData.fromCustomer(customer);
    });

    int? headCustomerIndex = company.mainCustomerId == null
        ? null
        : company.customers.indexWhere(
            (item) => item.id == company.mainCustomerId,
          );
    if (headCustomerIndex != null && headCustomerIndex < 0) {
      headCustomerIndex = null;
    }
    if (headCustomerIndex == null && company.customers.isNotEmpty) {
      headCustomerIndex = 0;
    }

    String headLabel() {
      if (headCustomerIndex == null ||
          headCustomerIndex! >= customerCtrls.length) {
        return 'No head selected';
      }
      return customerCtrls[headCustomerIndex!].displayName;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Customers - ${company.uniqueName}'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Manage up to 3 test customers for ${company.uniqueName}.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'The head must be one of the entered customers.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Chip(label: Text('Slots: ${customerCtrls.length}/3')),
                      const SizedBox(width: 8),
                      Chip(label: Text('Head: ${headLabel()}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < customerCtrls.length; i++) ...[
                    _CustomerFormCard(
                      index: i,
                      data: customerCtrls[i],
                      isHead: i == headCustomerIndex,
                      onScanBusinessCard: () =>
                          _scanBusinessCard(customerCtrls[i], setDialogState),
                      onChanged: () => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: headCustomerIndex,
                    decoration: const InputDecoration(
                      labelText: 'Head of company',
                      helperText: 'Choose the person who leads the company.',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('No selection'),
                      ),
                      for (var i = 0; i < customerCtrls.length; i++)
                        if (customerCtrls[i].isNotEmpty)
                          DropdownMenuItem<int?>(
                            value: i,
                            child: Text(customerCtrls[i].displayName),
                          ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        headCustomerIndex = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Company ID: ${company.id} | Unique ID: ${company.uniqueCode}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () async {
                final customers = customerCtrls
                    .where((item) => item.isNotEmpty)
                    .map((item) => item.toPayload())
                    .toList();
                if (customers.length > 3) {
                  return;
                }
                if (customers.isNotEmpty && headCustomerIndex == null) {
                  headCustomerIndex = 0;
                }
                if (headCustomerIndex != null &&
                    headCustomerIndex! >= customers.length) {
                  return;
                }

                try {
                  await ref.read(apiClientProvider).updateClientCompany(clientCompanyId: company.id,
                  customers: customers, 
                  headCustomerIndex: headCustomerIndex,
                  );
                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.pop(dialogContext);
                  await _load();
                } on DioException catch (error) {
                  final detail = error.response?.data;
                  final message = detail is Map && detail['detail'] != null
                      ? '${detail['detail']}'
                      : 'Could not save customers.';
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomerDetails(CompanyCustomerDto customer) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(customer.fullName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gender: ${_display(customer.gender)}'),
            const SizedBox(height: 6),
            Text('Email: ${_display(customer.email)}'),
            const SizedBox(height: 6),
            Text('Role: ${_display(customer.role)}'),
            const SizedBox(height: 6),
            Text('Phone: ${_display(customer.phoneNumber)}'),
            const SizedBox(height: 6),
            Text('Mobile: ${_display(customer.mobileNumber)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openCustomerEditor();
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Customers: ${widget.companyName}',
      onAdd: _openCustomerEditor,
      onSettings: _openSettings,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!),
                    ),
                  if (_company != null) ...[
                    Text(
                      'Company: ${_company!.uniqueName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Unique ID (database): ${_company!.uniqueCode}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openCustomerEditor,
                      icon: const Icon(Icons.people_outline),
                      label: const Text('Edit customers'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openCustomerEditor,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Scan business card'),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _company!.customers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final customer = _company!.customers[index];
                          final isHead =
                              customer.id == _company!.mainCustomerId;
                          return Card(
                            child: ListTile(
                              onTap: () => _openCustomerDetails(customer),
                              title: Text(customer.fullName),
                              subtitle: Text(
                                'Gender: ${_display(customer.gender)} | Email: ${_display(customer.email)}\nRole: ${_display(customer.role)} | Phone: ${_display(customer.phoneNumber)} | Mobile: ${_display(customer.mobileNumber)}',
                              ),
                              trailing: isHead
                                  ? const Chip(label: Text('Head'))
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ] else
                    const Text('No company loaded.'),
                ],
              ),
            ),
    );
  }
}

class _CustomerFormData {
  _CustomerFormData({
    String firstName = '',
    String lastName = '',
    this.gender = 'not_specified',
    String email = '',
    String role = '',
    String phoneNumber = '',
    String mobileNumber = '',
  }) {
    firstNameCtrl.text = firstName;
    lastNameCtrl.text = lastName;
    emailCtrl.text = email;
    roleCtrl.text = role;
    phoneCtrl.text = phoneNumber;
    mobileCtrl.text = mobileNumber;
  }

  factory _CustomerFormData.fromCustomer(CompanyCustomerDto? customer) {
    if (customer == null) {
      return _CustomerFormData();
    }
    return _CustomerFormData(
      firstName: customer.firstName,
      lastName: customer.lastName,
      gender: customer.gender,
      email: customer.email ?? '',
      role: customer.role ?? '',
      phoneNumber: customer.phoneNumber ?? '',
      mobileNumber: customer.mobileNumber ?? '',
    );
  }

  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController lastNameCtrl = TextEditingController();
  String gender;
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController roleCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController mobileCtrl = TextEditingController();
  String get displayName =>
      '${firstNameCtrl.text.trim()} ${lastNameCtrl.text.trim()}'.trim();
  bool get isNotEmpty =>
      firstNameCtrl.text.trim().isNotEmpty ||
      lastNameCtrl.text.trim().isNotEmpty ||
      emailCtrl.text.trim().isNotEmpty ||
      roleCtrl.text.trim().isNotEmpty ||
      phoneCtrl.text.trim().isNotEmpty ||
      mobileCtrl.text.trim().isNotEmpty;

  Map<String, dynamic> toPayload() {
    return {
      'first_name': firstNameCtrl.text.trim(),
      'last_name': lastNameCtrl.text.trim(),
      'gender': gender,
      'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
      'role': roleCtrl.text.trim().isEmpty ? null : roleCtrl.text.trim(),
      'phone_number': phoneCtrl.text.trim().isEmpty
          ? null
          : phoneCtrl.text.trim(),
      'mobile_number': mobileCtrl.text.trim().isEmpty
          ? null
          : mobileCtrl.text.trim(),
    };
  }
}

class _CustomerFormCard extends StatelessWidget {
  const _CustomerFormCard({
    required this.index,
    required this.data,
    required this.isHead,
    required this.onScanBusinessCard,
    required this.onChanged,
  });

  final int index;
  final _CustomerFormData data;
  final bool isHead;
  final Future<void> Function() onScanBusinessCard;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isHead ? 2 : 0,
      color: isHead ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Customer ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (isHead)
                  const Chip(
                    label: Text('Head'),
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onScanBusinessCard,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan card'),
                ),
                const SizedBox(width: 8),
                if (!data.isNotEmpty)
                  const Text(
                    'Empty slot',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.firstNameCtrl,
              decoration: const InputDecoration(labelText: 'First name'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Last name'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: data.gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'Herr', child: Text('Herr')),
                DropdownMenuItem(value: 'Frau', child: Text('Frau')),
                DropdownMenuItem(value: 'Div', child: Text('Div')),
                DropdownMenuItem(
                  value: 'not_specified',
                  child: Text('not_specified'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                data.gender = value;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.roleCtrl,
              decoration: const InputDecoration(labelText: 'Role'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone number'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.mobileCtrl,
              decoration: const InputDecoration(labelText: 'Mobile number'),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}
