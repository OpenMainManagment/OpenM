import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/current_project_state.dart';
import '../../widgets/app_shell.dart';

class ProjectPartDecisionsScreen extends ConsumerStatefulWidget {
  const ProjectPartDecisionsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  ConsumerState<ProjectPartDecisionsScreen> createState() =>
      _ProjectPartDecisionsScreenState();
}

class _ProjectPartDecisionsScreenState
    extends ConsumerState<ProjectPartDecisionsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<ProjectOrderItemDto> _parts = const [];
  List<ManufacturerDto> _manufacturers = const [];

  // partId -> chosen decision ('Storage' | 'Self Manufacture' | 'Order')
  final Map<String, String> _choices = {};
  // partId -> chosen manufacturer id (only relevant when decision == Order)
  final Map<String, String?> _manufacturerChoices = {};

  static const List<String> _decisionOptions = [
    'Storage',
    'Self Manufacture',
    'Order',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentProjectIdProvider.notifier).state = widget.projectId;
    });
    _load();
  }

  @override
  void dispose() {
    if (ref.read(currentProjectIdProvider) == widget.projectId) {
      ref.read(currentProjectIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.projectPartsStatus(widget.projectId),
        api.manufacturers(),
        api.projectPartDecisions(widget.projectId),
      ]);
      final parts = (results[0] as List<ProjectOrderItemDto>)
          .where((item) => item.selected)
          .toList();
      final manufacturers = results[1] as List<ManufacturerDto>;
      final existingDecisions = results[2] as List<PartOrderDecisionDto>;

      // existingDecisions is ordered most-recent-first by the backend, so
      // the first one seen per part is its current/latest decision.
      final latestByPart = <String, PartOrderDecisionDto>{};
      for (final decision in existingDecisions) {
        latestByPart.putIfAbsent(decision.partId, () => decision);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _parts = parts;
        _manufacturers = manufacturers;
        for (final part in parts) {
          final existing = latestByPart[part.partId];
          _choices[part.partId] = existing?.decision ?? 'Storage';
          _manufacturerChoices[part.partId] = existing?.manufacturerId;
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load parts: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _saveDecisions();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sourcing decisions saved')));
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveDecisions() async {
    final entries = _parts.map((part) {
      final decision = _choices[part.partId] ?? 'Storage';
      return {
        'part_id': part.partId,
        'decision': decision,
        'manufacturer_id': decision == 'Order'
            ? _manufacturerChoices[part.partId]
            : null,
        'quantity': part.quantity <= 0 ? 1 : part.quantity,
      };
    }).toList();

    await ref
        .read(apiClientProvider)
        .savePartOrderDecisions(
          projectId: widget.projectId,
          entries: entries,
        );
  }

  /// Saves the sourcing decisions, then requests quotations: assigns
  /// quotation numbers, pushes due dates 4 weeks out, and sets Storage-
  /// sourced parts straight to "In Stock".
  Future<void> _requestQuotations() async {
    setState(() => _isSaving = true);
    try {
      await _saveDecisions();
      await ref.read(apiClientProvider).requestProjectQuotation(widget.projectId);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quotations requested — due dates set 4 weeks out.'),
        ),
      );
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not request quotations: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Color _decisionColor(String decision) {
    switch (decision) {
      case 'Storage':
        return Colors.blueGrey.shade600;
      case 'Self Manufacture':
        return Colors.teal.shade700;
      case 'Order':
        return AppColors.primaryLight;
      default:
        return AppColors.projectStatusDefault;
    }
  }

  IconData _decisionIcon(String decision) {
    switch (decision) {
      case 'Storage':
        return Icons.inventory_2_outlined;
      case 'Self Manufacture':
        return Icons.precision_manufacturing_outlined;
      case 'Order':
        return Icons.shopping_cart_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Order Parts — ${widget.projectName}',
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
          : _parts.isEmpty
          ? const Center(
              child: Text(
                'No parts selected for this project yet. '
                'Select parts on the Order screen first.',
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'For each part, decide how it will be sourced: pulled '
                    'from Storage, made in-house (Self Manufacture), or '
                    'Ordered from a manufacturer.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _parts.length,
                    itemBuilder: (context, index) =>
                        _buildPartRow(_parts[index]),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _save,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _isSaving ? 'Saving...' : 'Save Sourcing Decisions',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _requestQuotations,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.request_quote_outlined),
                            label: const Text('Quotations'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPartRow(ProjectOrderItemDto part) {
    final decision = _choices[part.partId] ?? 'Storage';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              part.partName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (part.partNumber != null && part.partNumber!.isNotEmpty)
              Text(
                'Nr: ${part.partNumber} • Qty: ${part.quantity}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: _decisionOptions
                  .map(
                    (option) => ButtonSegment(
                      value: option,
                      label: Text(option),
                      icon: Icon(_decisionIcon(option), size: 16),
                    ),
                  )
                  .toList(),
              selected: {decision},
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: _decisionColor(
                  decision,
                ).withValues(alpha: 0.18),
                selectedForegroundColor: _decisionColor(decision),
              ),
              onSelectionChanged: (selection) {
                setState(() {
                  _choices[part.partId] = selection.first;
                });
              },
            ),
            if (decision == 'Order') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _manufacturerChoices[part.partId],
                decoration: const InputDecoration(
                  labelText: 'Manufacturer (optional)',
                  isDense: true,
                ),
                items: _manufacturers
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _manufacturerChoices[part.partId] = value;
                  });
                },
              ),
              if (_manufacturers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No manufacturers configured yet — add some under '
                    'Admin > Manufacturers.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
