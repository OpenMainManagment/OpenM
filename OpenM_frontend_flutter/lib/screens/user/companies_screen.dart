import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/web_camera_capture_stub.dart'
    if (dart.library.html) '../../services/web_camera_capture_web.dart'
    as web_camera_capture;
import '../../widgets/app_shell.dart';
import '../../widgets/company_overview_dialog.dart';
import '../../widgets/todo_strip.dart';

class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});

  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<CompanyDto> _companies = const [];

  Future<void> _openCompanyOverview(CompanyDto company) async {
    await showCompanyOverviewDialog(
      context: context,
      company: company,
      onEdit: () => _openEditCompanyDialog(company),
      onManageCustomers: () => _openCompanyCustomers(company),
    );
  }

  Future<void> _openCompanyCustomers(CompanyDto company) async {
    await context.push(
      '/companies/${company.id}/customers?name=${Uri.encodeComponent(company.uniqueName)}',
    );
    await _load();
  }

  Future<void> _openProjectNoteWindow({
    required String companyId,
    required String companyName,
  }) async {
    await context.push(
      '/companies/$companyId/projects/new-note?name=${Uri.encodeComponent(companyName)}',
    );
    await _load();
  }

  Future<void> _scanBusinessCardForAddCompany({
    required TextEditingController companyNameCtrl,
    required TextEditingController streetCtrl,
    required TextEditingController houseNumberCtrl,
    required TextEditingController emailCtrl,
    required TextEditingController phoneCtrl,
    required TextEditingController customerFirstNameCtrl,
    required TextEditingController customerLastNameCtrl,
    required TextEditingController customerEmailCtrl,
    required TextEditingController customerRoleCtrl,
    required TextEditingController customerPhoneCtrl,
    required void Function(void Function()) setDialogState,
  }) async {
    List<int>? bytes;
    String fileName = 'business_card.jpg';

    try {
      if (kIsWeb) {
        web_camera_capture.WebCameraCaptureResult? webCapture;
        try {
          webCapture = await web_camera_capture.captureImageFromWebCamera(
            context,
          );
        } on web_camera_capture.CameraPermissionDeniedException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Camera access is blocked. Please allow camera permission in Chrome and try again.',
                ),
              ),
            );
          }
          return;
        }

        if (webCapture == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open camera. Please allow camera access.',
                ),
              ),
            );
          }
          return;
        }
        bytes = webCapture.bytes;
        fileName = webCapture.fileName;
      }

      try {
        if (!kIsWeb) {
          final photo = await _imagePicker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.rear,
            imageQuality: 85,
          );
          if (photo != null) {
            bytes = await photo.readAsBytes();
            fileName = photo.name;
          }
        }
      } catch (_) {
        // Camera may be unavailable on some platforms.
      }

      if (bytes == null) {
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

      final extractedText = await ref
          .read(apiClientProvider)
          .extractBusinessCardText(bytes: bytes, fileName: fileName);
      if (extractedText.trim().isEmpty) {
        return;
      }

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
        final email = emailMatch.group(0) ?? '';
        if (customerEmailCtrl.text.trim().isEmpty) {
          customerEmailCtrl.text = email;
        }
        if (emailCtrl.text.trim().isEmpty) {
          emailCtrl.text = email;
        }
      }

      final phoneMatches = RegExp(r'(?:\+?\d[\d\s()./-]{5,}\d)')
          .allMatches(extractedText)
          .map((match) => match.group(0)!.trim())
          .toList();
      if (phoneMatches.isNotEmpty) {
        if (customerPhoneCtrl.text.trim().isEmpty) {
          customerPhoneCtrl.text = phoneMatches.first;
        }
        if (phoneCtrl.text.trim().isEmpty) {
          phoneCtrl.text = phoneMatches.first;
        }
      }

      String? companyLine;
      String? personLine;
      String? roleLine;
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (personLine == null &&
            !lower.contains('@') &&
            !RegExp(r'\d').hasMatch(line) &&
            !lower.contains('www.') &&
            !lower.contains('tel') &&
            !lower.contains('phone') &&
            !lower.contains('mobile') &&
            line.split(' ').length >= 2) {
          personLine = line;
          continue;
        }
        if (roleLine == null &&
            (lower.contains('manager') ||
                lower.contains('sales') ||
                lower.contains('ceo') ||
                lower.contains('owner') ||
                lower.contains('leitung') ||
                lower.contains('geschäftsführer'))) {
          roleLine = line;
        }
        if (companyLine == null &&
            !lower.contains('@') &&
            !RegExp(r'\d').hasMatch(line) &&
            line.split(' ').length <= 5 &&
            !lower.contains('tel') &&
            !lower.contains('phone')) {
          companyLine = line;
        }
      }

      if (personLine != null) {
        final parts = personLine
            .replaceAll(
              RegExp(
                r'^(Herr|Frau|Mr\.?|Ms\.?|Mrs\.?)\s+',
                caseSensitive: false,
              ),
              '',
            )
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.isNotEmpty && customerFirstNameCtrl.text.trim().isEmpty) {
          customerFirstNameCtrl.text = parts.first;
        }
        if (parts.length > 1 && customerLastNameCtrl.text.trim().isEmpty) {
          customerLastNameCtrl.text = parts.skip(1).join(' ');
        }
      }

      if (roleLine != null && customerRoleCtrl.text.trim().isEmpty) {
        customerRoleCtrl.text = roleLine;
      }
      if (companyLine != null && companyNameCtrl.text.trim().isEmpty) {
        companyNameCtrl.text = companyLine;
      }

      final addressLine = lines
          .where((line) => RegExp(r'\d').hasMatch(line))
          .firstWhere((_) => streetCtrl.text.trim().isEmpty, orElse: () => '');
      if (addressLine.isNotEmpty) {
        final match = RegExp(
          r'^(.*?)[,\s]+(\d+[A-Za-z/-]*)$',
        ).firstMatch(addressLine);
        if (match != null) {
          if (streetCtrl.text.trim().isEmpty) {
            streetCtrl.text = (match.group(1) ?? '').trim();
          }
          if (houseNumberCtrl.text.trim().isEmpty) {
            houseNumberCtrl.text = (match.group(2) ?? '').trim();
          }
        }
      }

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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not take picture. Please try again and allow camera access.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openEditCompanyDialog(CompanyDto company) async {
    final nameCtrl = TextEditingController(text: company.uniqueName);
    final streetCtrl = TextEditingController(text: company.street ?? '');
    final houseNumberCtrl = TextEditingController(
      text: company.houseNumber ?? '',
    );
    final emailCtrl = TextEditingController(text: company.contactEmail ?? '');
    final phoneCtrl = TextEditingController(text: company.phoneNumber ?? '');
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Client Company'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Unique Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: streetCtrl,
                  decoration: const InputDecoration(labelText: 'Street'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: houseNumberCtrl,
                  decoration: const InputDecoration(labelText: 'House number'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Contact email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Unique ID (from database): ${company.uniqueCode}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                      });
                      try {
                        await ref
                            .read(apiClientProvider)
                            .updateClientCompany(
                              clientCompanyId: company.id,
                              uniqueName: name,
                              street: streetCtrl.text.trim().isEmpty
                                  ? null
                                  : streetCtrl.text.trim(),
                              houseNumber: houseNumberCtrl.text.trim().isEmpty
                                  ? null
                                  : houseNumberCtrl.text.trim(),
                              contactEmail: emailCtrl.text.trim().isEmpty
                                  ? null
                                  : emailCtrl.text.trim(),
                              phoneNumber: phoneCtrl.text.trim().isEmpty
                                  ? null
                                  : phoneCtrl.text.trim(),
                            );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Client company updated.'),
                            ),
                          );
                        }
                      } on DioException catch (error) {
                        final detail = error.response?.data;
                        final message =
                            detail is Map && detail['detail'] != null
                            ? '${detail['detail']}'
                            : 'Could not update client company.';
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), _load);
  }

  void _clearSearch() {
    if (_searchCtrl.text.isEmpty) {
      return;
    }
    _searchCtrl.clear();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final companies = await api.clientCompanies(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _companies = companies;
    });
  }

  Future<void> _addCompanyDialog() async {
    final nameCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final houseNumberCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final customerFirstNameCtrl = TextEditingController();
    final customerLastNameCtrl = TextEditingController();
    final customerEmailCtrl = TextEditingController();
    final customerRoleCtrl = TextEditingController();
    final customerPhoneCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Client Company'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _scanBusinessCardForAddCompany(
                    companyNameCtrl: nameCtrl,
                    streetCtrl: streetCtrl,
                    houseNumberCtrl: houseNumberCtrl,
                    emailCtrl: emailCtrl,
                    phoneCtrl: phoneCtrl,
                    customerFirstNameCtrl: customerFirstNameCtrl,
                    customerLastNameCtrl: customerLastNameCtrl,
                    customerEmailCtrl: customerEmailCtrl,
                    customerRoleCtrl: customerRoleCtrl,
                    customerPhoneCtrl: customerPhoneCtrl,
                    setDialogState: setDialogState,
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan business card'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Unique Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: streetCtrl,
                  decoration: const InputDecoration(labelText: 'Street'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: houseNumberCtrl,
                  decoration: const InputDecoration(labelText: 'House number'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Contact email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Customer from card',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customerFirstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer first name',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customerLastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer last name',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customerEmailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer email',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customerRoleCtrl,
                  decoration: const InputDecoration(labelText: 'Customer role'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customerPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer phone',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final companyName = nameCtrl.text.trim();
                      if (companyName.isEmpty) {
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                      });

                      try {
                        final api = ref.read(apiClientProvider);
                        final existing = _companies.where((c) {
                          final sameName =
                              c.uniqueName.trim().toLowerCase() ==
                              companyName.toLowerCase();
                          final sameContact =
                              (c.contactEmail ?? '')
                                  .trim()
                                  .toLowerCase()
                                  .isNotEmpty &&
                              (c.contactEmail ?? '').trim().toLowerCase() ==
                                  emailCtrl.text.trim().toLowerCase();
                          return sameName || sameContact;
                        }).toList();

                        final customerFirstName = customerFirstNameCtrl.text
                            .trim();
                        final customerLastName = customerLastNameCtrl.text
                            .trim();
                        final customerEmail = customerEmailCtrl.text.trim();
                        final customerRole = customerRoleCtrl.text.trim();
                        final customerPhone = customerPhoneCtrl.text.trim();

                        final hasCustomer =
                            customerFirstName.isNotEmpty &&
                            customerLastName.isNotEmpty;

                        final customerPayload =
                            <String, dynamic>{
                              'first_name': customerFirstName,
                              'last_name': customerLastName,
                              'email': customerEmail.isEmpty
                                  ? null
                                  : customerEmail,
                              'role': customerRole.isEmpty
                                  ? null
                                  : customerRole,
                              'phone_number': customerPhone.isEmpty
                                  ? null
                                  : customerPhone,
                              'gender': 'not_specified',
                            }..removeWhere(
                              (key, value) => value == null || value == '',
                            );

                        String targetCompanyId;
                        String targetCompanyName;

                        if (existing.isNotEmpty) {
                          final company = existing.first;
                          final List<Map<String, dynamic>> mergedCustomers =
                              company.customers
                                  .map(
                                    (c) =>
                                        <String, dynamic>{
                                          'first_name': c.firstName,
                                          'last_name': c.lastName,
                                          'gender': c.gender,
                                          'email': c.email,
                                          'role': c.role,
                                          'phone_number': c.phoneNumber,
                                          'mobile_number': c.mobileNumber,
                                        }..removeWhere(
                                          (key, value) =>
                                              value == null || value == '',
                                        ),
                                  )
                                  .toList();

                          if (hasCustomer) {
                            final normalizedEmail =
                                (customerPayload['email'] ?? '').toLowerCase();
                            final normalizedFirst =
                                (customerPayload['first_name'] ?? '')
                                    .toLowerCase();
                            final normalizedLast =
                                (customerPayload['last_name'] ?? '')
                                    .toLowerCase();

                            final duplicate = mergedCustomers.any((c) {
                              final email = (c['email'] as String? ?? '')
                                  .toLowerCase();
                              final first = (c['first_name'] as String? ?? '')
                                  .toLowerCase();
                              final last = (c['last_name'] as String? ?? '')
                                  .toLowerCase();
                              if (normalizedEmail.isNotEmpty &&
                                  email.isNotEmpty) {
                                return email == normalizedEmail;
                              }
                              return first == normalizedFirst &&
                                  last == normalizedLast;
                            });

                            if (!duplicate && mergedCustomers.length < 3) {
                              mergedCustomers.add(customerPayload);
                            }
                          }

                          final currentHeadIndex =
                              company.mainCustomerId == null
                              ? null
                              : company.customers.indexWhere(
                                  (c) => c.id == company.mainCustomerId,
                                );

                          await api.updateClientCompany(
                            clientCompanyId: company.id,
                            customers: mergedCustomers,
                            headCustomerIndex:
                                currentHeadIndex != null &&
                                    currentHeadIndex >= 0
                                ? currentHeadIndex
                                : null,
                          );
                          targetCompanyId = company.id;
                          targetCompanyName = company.uniqueName;
                        } else {
                          final created = await api.createClientCompany(
                            uniqueName: companyName,
                            street: streetCtrl.text.trim().isEmpty
                                ? null
                                : streetCtrl.text.trim(),
                            houseNumber: houseNumberCtrl.text.trim().isEmpty
                                ? null
                                : houseNumberCtrl.text.trim(),
                            contactEmail: emailCtrl.text.trim().isEmpty
                                ? null
                                : emailCtrl.text.trim(),
                            phoneNumber: phoneCtrl.text.trim().isEmpty
                                ? null
                                : phoneCtrl.text.trim(),
                            customers: hasCustomer
                                ? [customerPayload]
                                : const [],
                          );
                          targetCompanyId = created.id;
                          targetCompanyName = created.uniqueName;
                        }

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        await _load();
                        if (mounted) {
                          await _openProjectNoteWindow(
                            companyId: targetCompanyId,
                            companyName: targetCompanyName,
                          );
                        }
                      } on DioException catch (error) {
                        final detail = error.response?.data;
                        final message =
                            detail is Map && detail['detail'] != null
                            ? '${detail['detail']}'
                            : 'Could not save client company.';
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Customer Companies',
      onAdd: _addCompanyDialog,
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const TopTodoStrip(),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search customer companies',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _companies.length,
                itemBuilder: (_, index) {
                  final c = _companies[index];
                  return Card(
                    child: ListTile(
                      title: Text(c.uniqueName),
                      subtitle: Text('ID: ${c.uniqueCode}'),
                      trailing: IconButton(
                        tooltip: 'Client company information',
                        onPressed: () => _openCompanyOverview(c),
                        icon: const Icon(Icons.info_outline),
                      ),
                      onTap: () => context.push(
                        '/companies/${c.id}/projects?name=${Uri.encodeComponent(c.uniqueName)}',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
