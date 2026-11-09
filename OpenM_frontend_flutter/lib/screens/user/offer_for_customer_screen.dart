import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/pdf_preview.dart';
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
  String? _previewingOfferId;
  String? _selectedOfferId;
  String? _error;
  List<DocumentDto> _offers = const [];
  List<ProjectOfferRecipientDto> _recipients = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens an offer PDF already saved in the project's Angebote folder.
  Future<void> _viewPdf(DocumentDto offer) async {
    setState(() {
      _selectedOfferId = offer.id;
      _previewingOfferId = offer.id;
    });
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .downloadFileBytes(offer.id);
      if (!mounted) {
        return;
      }
      if (bytes.isEmpty) {
        throw Exception('PDF is empty');
      }
      await showPdfPreview(context, bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open PDF: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _previewingOfferId = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final recipients = await api.projectOfferRecipients(widget.projectId);
      final rootFolders = await api.folders(widget.projectId);
      final offersFolder = rootFolders.where(
        (folder) => folder.name.toLowerCase() == 'angebote',
      );
      final offers = offersFolder.isEmpty
          ? <DocumentDto>[]
          : await api.folderFiles(offersFolder.first.id);
      final pdfOffers =
          offers
              .where(
                (file) =>
                    file.fileName.toLowerCase().endsWith('.pdf') ||
                    file.mimeType?.toLowerCase() == 'application/pdf',
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) {
        return;
      }
      setState(() {
        _recipients = recipients;
        _offers = pdfOffers;
        _selectedOfferId =
            pdfOffers.any((offer) => offer.id == widget.documentId)
            ? widget.documentId
            : pdfOffers.firstOrNull?.id;
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
        _error = 'Failed to load offers and recipients: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _send() async {
    final documentId = _selectedOfferId;
    if (documentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an offer PDF first')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one recipient')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final results = await ref
          .read(apiClientProvider)
          .sendProjectOffer(
            projectId: widget.projectId,
            documentId: documentId,
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
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Offer PDFs',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (_offers.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.picture_as_pdf_outlined),
                            title: Text('No offer PDFs found.'),
                          ),
                        )
                      else
                        for (final offer in _offers)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              selected: offer.id == _selectedOfferId,
                              leading: const Icon(
                                Icons.picture_as_pdf_outlined,
                              ),
                              title: Text(offer.fileName),
                              subtitle: Text(
                                'Created ${_formatDate(offer.createdAt)}',
                              ),
                              trailing: _previewingOfferId == offer.id
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.open_in_new),
                              onTap: _previewingOfferId == null
                                  ? () => _viewPdf(offer)
                                  : null,
                            ),
                          ),
                      const SizedBox(height: 16),
                      Text(
                        'Recipients',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Select who should receive the selected offer by email. '
                          'The project leader is pre-selected.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_recipients.isEmpty)
                        const Card(
                          child: ListTile(
                            title: Text(
                              'No customer company contacts found for this project.',
                            ),
                          ),
                        )
                      else
                        for (final recipient in _recipients)
                          _buildRecipientTile(recipient),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _isSending ||
                                _selectedOfferId == null ||
                                _recipients.isEmpty
                            ? null
                            : _send,
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

  Widget _buildRecipientTile(ProjectOfferRecipientDto recipient) {
    final hasEmail = recipient.email != null && recipient.email!.isNotEmpty;
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
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}
