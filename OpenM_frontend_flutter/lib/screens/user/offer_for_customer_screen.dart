import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

/// Lets the user pick which customer-company employees should receive the
/// generated offer PDF by email (project leader listed first), then sends it.
class OfferForCustomerScreen extends ConsumerStatefulWidget {
  const OfferForCustomerScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.documentId,
  });

  final String projectId;
  final String projectName;
  final String documentId;

  @override
  ConsumerState<OfferForCustomerScreen> createState() =>
      _OfferForCustomerScreenState();
}

class _OfferForCustomerScreenState
    extends ConsumerState<OfferForCustomerScreen> {
  bool _isLoading = true;
  bool _isSending = false;
  bool _isPreviewing = false;
  String? _error;
  List<ProjectOfferRecipientDto> _recipients = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens the offer PDF already saved in the project's Angebote folder.
  Future<void> _viewPdf() async {
    setState(() => _isPreviewing = true);
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .downloadFileBytes(widget.documentId);
      if (bytes.isEmpty) {
        throw Exception('PDF is empty');
      }
      final dataUri = 'data:application/pdf;base64,${base64Encode(bytes)}';
      final launched = await launchUrl(
        Uri.parse(dataUri),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the PDF.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open PDF: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isPreviewing = false);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final recipients = await ref
          .read(apiClientProvider)
          .projectOfferRecipients(widget.projectId);
      if (!mounted) {
        return;
      }
      setState(() {
        _recipients = recipients;
        _selected
          ..clear()
          ..addAll(
            recipients
                .where((r) => r.isProjectLeader && r.email != null)
                .map((r) => r.customerId),
          );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load recipients: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one recipient')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final results = await ref.read(apiClientProvider).sendProjectOffer(
            projectId: widget.projectId,
            documentId: widget.documentId,
            customerIds: _selected.toList(),
          );
      if (!mounted) {
        return;
      }
      final sentCount = results.where((r) => r.sent).length;
      final failedCount = results.length - sentCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedCount == 0
                ? 'Offer sent to $sentCount recipient(s).'
                : 'Sent to $sentCount recipient(s), $failedCount failed.',
          ),
        ),
      );
      if (failedCount == 0) {
        Navigator.of(context).maybePop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send offer: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Offer for ${widget.projectName}',
      onAdd: () {},
      onSettings: () {},
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _recipients.isEmpty
          ? const Center(
              child: Text('No customer company contacts found for this project.'),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isPreviewing ? null : _viewPdf,
                      icon: _isPreviewing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_isPreviewing ? 'Opening PDF...' : 'View PDF'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Select who should receive the offer by email. '
                    'The project leader is pre-selected.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _recipients.length,
                    itemBuilder: (context, index) {
                      final recipient = _recipients[index];
                      final hasEmail =
                          recipient.email != null && recipient.email!.isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: _selected.contains(recipient.customerId),
                          onChanged: hasEmail
                              ? (checked) {
                                  setState(() {
                                    if (checked ?? false) {
                                      _selected.add(recipient.customerId);
                                    } else {
                                      _selected.remove(recipient.customerId);
                                    }
                                  });
                                }
                              : null,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  recipient.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (recipient.isProjectLeader)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Chip(label: Text('Project leader')),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            hasEmail
                                ? '${recipient.jobTitle ?? '-'} \u2022 ${recipient.email}'
                                : '${recipient.jobTitle ?? '-'} \u2022 no email on file',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSending ? null : _send,
                        icon: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(_isSending ? 'Sending...' : 'Send'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
