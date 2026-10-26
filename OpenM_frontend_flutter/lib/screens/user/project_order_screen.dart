import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/current_project_state.dart';
import '../../widgets/app_shell.dart';

class ProjectOrderScreen extends ConsumerStatefulWidget {
  const ProjectOrderScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  ConsumerState<ProjectOrderScreen> createState() => _ProjectOrderScreenState();
}

class _ProjectOrderScreenState extends ConsumerState<ProjectOrderScreen> {
  List<PartDto> _allParts = [];
  List<ProjectOrderItemDto> _orderItems = [];
  bool _isLoading = true;
  bool _isSendingOffer = false;
  final Map<String, int> _partQuantities = {};
  final TextEditingController _topNoteController = TextEditingController();
  final TextEditingController _bottomNoteController = TextEditingController();
  String? _savedTopNote;
  String? _savedBottomNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentProjectIdProvider.notifier).state = widget.projectId;
    });
    _loadData();
  }

  @override
  void dispose() {
    _topNoteController.dispose();
    _bottomNoteController.dispose();
    if (ref.read(currentProjectIdProvider) == widget.projectId) {
      ref.read(currentProjectIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);

      // Alle Parts laden
      final parts = await api.parts(includeAll: true);

      // Bestellpositionen laden
      final orderItems = await api.projectOrderItems(widget.projectId);
      final project = await api.projectById(widget.projectId);

      if (!mounted) return;

      setState(() {
        _allParts = parts;
        _orderItems = orderItems;
        _partQuantities.clear();
        _savedTopNote = project.orderTopNote;
        _savedBottomNote = project.orderBottomNote;
        _topNoteController.text = _savedTopNote ?? '';
        _bottomNoteController.text = _savedBottomNote ?? '';

        for (final item in _orderItems) {
          _partQuantities[item.partId] = item.quantity > 0 ? item.quantity : 0;
        }

        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Teile nach Rolle gruppieren
  Map<String, List<PartDto>> _groupPartsByRole() {
    final groups = <String, List<PartDto>>{
      'base_case': [],
      'main': [],
      'other': [],
    };

    for (final part in _allParts) {
      final role = part.partRole.toLowerCase();
      if (role == 'base_case') {
        groups['base_case']!.add(part);
      } else if (role == 'main') {
        groups['main']!.add(part);
      } else {
        groups['other']!.add(part);
      }
    }

    return groups;
  }

  /// Prüfen ob ein Teil ein Rival hat
  bool _hasRival(PartDto part) {
    return part.rivalPartId != null && part.rivalPartId!.isNotEmpty;
  }

  /// Rival-Gruppe für ein Teil finden (inkl. des Teils selbst)
  List<PartDto> _getRivalGroup(PartDto part) {
    if (!_hasRival(part)) return [part];

    final rivalId = part.rivalPartId!;
    return _allParts
        .where(
          (p) => p.id == part.id || p.id == rivalId || p.rivalPartId == part.id,
        )
        .toList();
  }

  void _setPartQuantity(PartDto part, int value) {
    setState(() {
      final nextValue = value < 0 ? 0 : value;
      _partQuantities[part.id] = nextValue;
    });
  }

  /// Base model parts are mutually exclusive: picking one clears the
  /// quantity on every other base model part.
  void _selectBaseModel(PartDto selectedPart) {
    setState(() {
      for (final part in _groupPartsByRole()['base_case'] ?? const <PartDto>[]) {
        _partQuantities[part.id] = part.id == selectedPart.id ? 1 : 0;
      }
    });
  }

  String? get _selectedBaseModelId {
    for (final part in _groupPartsByRole()['base_case'] ?? const <PartDto>[]) {
      if ((_partQuantities[part.id] ?? 0) > 0) {
        return part.id;
      }
    }
    return null;
  }

  void _changePartQuantity(PartDto part, {required int delta}) {
    final currentValue = _partQuantities[part.id] ?? 0;
    _setPartQuantity(part, currentValue + delta);
  }

  double get _totalPrice {
    double total = 0.0;

    for (final part in _allParts) {
      final quantity = _partQuantities[part.id] ?? 0;
      if (quantity > 0) {
        total += quantity * part.sellPrice;
      }
    }

    return total;
  }

  /// Auswahl speichern
  Future<void> _saveOrder() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);

      for (final part in _allParts) {
        final existingItem = _orderItems.firstWhere(
          (item) => item.partId == part.id,
          orElse: () => ProjectOrderItemDto(
            id: '',
            projectId: widget.projectId,
            partId: part.id,
            partName: part.name,
            quantity: 0,
            selected: false,
          ),
        );

        final quantity = _partQuantities[part.id] ?? 0;
        final isSelected = quantity > 0;

        if (existingItem.id.isNotEmpty) {
          await api.updateProjectOrderItem(
            projectId: widget.projectId,
            itemId: existingItem.id,
            quantity: quantity,
            selected: isSelected,
          );
        }
      }

      await api.updateProjectOrderNotes(
        projectId: widget.projectId,
        topNote: _topNoteController.text.trim().isEmpty ? null : _topNoteController.text.trim(),
        bottomNote: _bottomNoteController.text.trim().isEmpty ? null : _bottomNoteController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bestellung gespeichert')));

      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Speichern: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: widget.projectName,
      onAdd: () {},
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _topNoteController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Order note',
                            border: OutlineInputBorder(),
                            hintText: 'Add a note for the order',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildBaseModelSection(),
                        const SizedBox(height: 16),
                        _buildOrderItemsSection(),
                      ],
                    ),
                  ),
                ),
                _buildPriceSummary(),
              ],
            ),
    );
  }

  Widget _buildBaseModelSection() {
    final baseModels = _groupPartsByRole()['base_case'] ?? const <PartDto>[];
    if (baseModels.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedId = _selectedBaseModelId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'Base Model',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose exactly one base model.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            RadioGroup<String>(
              groupValue: selectedId,
              onChanged: (value) {
                if (_isLoading || value == null) {
                  return;
                }
                final part = baseModels.firstWhere((p) => p.id == value);
                _selectBaseModel(part);
              },
              child: Column(
                children: baseModels
                    .map(
                      (part) => RadioListTile<String>(
                        value: part.id,
                        title: Text(
                          '${part.name}${part.idNumber != null && part.idNumber!.isNotEmpty ? '  (${part.idNumber})' : ''}',
                        ),
                        subtitle: Text('€${part.sellPrice.toStringAsFixed(2)}'),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsSection() {
    final orderParts = _groupPartsByRole()['main'] ?? [];

    if (orderParts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'Order Items',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.all(color: AppColors.primaryDark.withValues(alpha: 0.3), width: 1),
                  columnWidths: const {
                    0: FixedColumnWidth(44),
                    1: FlexColumnWidth(2),
                    2: FixedColumnWidth(112),
                    3: FixedColumnWidth(90),
                    4: FixedColumnWidth(90),
                  },
                  children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.primaryDark),
                  children: [
                    _invoiceHeaderCell('Pos.', const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                    _invoiceHeaderCell('Description', const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                    _invoiceHeaderCell('Qty', const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white), alignEnd: true),
                    _invoiceHeaderCell('Unit Price', const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white), alignEnd: true),
                    _invoiceHeaderCell('Total', const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white), alignEnd: true),
                  ],
                ),
                    ...List.generate(orderParts.length, (index) {
                      final part = orderParts[index];
                      final quantity = _partQuantities[part.id] ?? 0;
                      final total = quantity * part.sellPrice;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: quantity > 0 ? AppColors.primaryDark.withValues(alpha: 0.05) : null,
                        ),
                        children: [
                          _invoiceCell('${index + 1}', alignEnd: false),
                          _invoiceCell('${part.name}${part.idNumber != null && part.idNumber!.isNotEmpty ? '  (${part.idNumber})' : ''}', bold: quantity > 0),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: _isLoading ? null : () => _changePartQuantity(part, delta: -1),
                                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                                  tooltip: 'Decrease amount',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  visualDensity: VisualDensity.compact,
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    quantity.toString(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _isLoading ? null : () => _changePartQuantity(part, delta: 1),
                                  icon: const Icon(Icons.add_circle_outline, size: 18),
                                  tooltip: 'Increase amount',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                          _invoiceCell('€${part.sellPrice.toStringAsFixed(2)}', alignEnd: true),
                          _invoiceCell('€${total.toStringAsFixed(2)}', alignEnd: true, bold: quantity > 0),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _invoiceHeaderCell(
    String text,
    TextStyle style, {
    bool alignEnd = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: style,
      ),
    );
  }

  Widget _invoiceCell(String text, {bool alignEnd = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Generates the offer PDF (saved into the project's Angebote folder),
  /// then opens the recipient-selection screen so it can be emailed.
  Future<void> _sendOffer() async {
    setState(() => _isSendingOffer = true);
    try {
      final document = await ref
          .read(apiClientProvider)
          .generateProjectOfferPdf(widget.projectId);
      if (!mounted) {
        return;
      }
      final encodedName = Uri.encodeQueryComponent(widget.projectName);
      final encodedDocumentId = Uri.encodeQueryComponent(document.id);
      context.push(
        '/projects/${widget.projectId}/offer?name=$encodedName&documentId=$encodedDocumentId',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create offer: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingOffer = false);
      }
    }
  }

  Widget _buildPriceSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _bottomNoteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Additional details',
                border: OutlineInputBorder(),
                hintText: 'Add extra notes before saving',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gesamt', style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        '€${_totalPrice.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading || _isSendingOffer ? null : _sendOffer,
                  icon: _isSendingOffer
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Send Offer'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
