import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../services/current_project_state.dart';
import '../../widgets/app_shell.dart';

class ProjectPartsStatusScreen extends ConsumerStatefulWidget {
  const ProjectPartsStatusScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  ConsumerState<ProjectPartsStatusScreen> createState() =>
      _ProjectPartsStatusScreenState();
}

class _ProjectPartsStatusScreenState
    extends ConsumerState<ProjectPartsStatusScreen> {
  bool _isLoading = true;
  String? _error;
  List<ProjectOrderItemDto> _items = const [];

  static const List<String> _statusOptions = [
    'In Progress',
    'Quotation',
    'Purchasing',
    'Ordered',
    'Delivery',
    'In Stock',
    'Loaded',
    'Installed',
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
      final items = await ref
          .read(apiClientProvider)
          .projectPartsStatus(widget.projectId);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items.where((item) => item.selected).toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load parts status: $error';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'In Progress':
        return Colors.grey.shade600;
      case 'Quotation':
        return Colors.purple.shade400;
      case 'Purchasing':
        return Colors.indigo.shade400;
      case 'Ordered':
        return AppColors.primaryLight;
      case 'Delivery':
        return Colors.orange.shade700;
      case 'In Stock':
        return AppColors.statusDone;
      case 'Loaded':
        return Colors.teal.shade600;
      case 'Installed':
        return Colors.green.shade800;
      default:
        return AppColors.projectStatusDefault;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  List<ProjectOrderItemDto> get _needsAttention {
    return _items
        .where(
          (item) =>
              item.isOverdue ||
              (item.orderStatus == 'In Progress' && item.selected),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final attention = _needsAttention;

    return AppShell(
      pageName: 'Parts Status — ${widget.projectName}',
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
          : _items.isEmpty
          ? const Center(
              child: Text(
                'No parts selected for this project yet. '
                'Select parts on the Order screen first.',
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryRow(),
                  if (attention.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildAttentionSection(attention),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Delivery Timeline',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_timelineItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No parts have an order or expected delivery date yet.',
                      ),
                    )
                  else
                    _PartsGanttChartView(
                      items: _timelineItems,
                      statusColor: _statusColor,
                      onTap: _openEditDialog,
                    ),
                  if (_notYetOrdered.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Not Yet Ordered (${_notYetOrdered.length})',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._notYetOrdered.map(_buildPartCard),
                  ],
                ],
              ),
            ),
    );
  }

  List<ProjectOrderItemDto> get _timelineItems {
    return _items
        .where(
          (item) => item.orderedAt != null || item.expectedDeliveryDate != null,
        )
        .toList();
  }

  List<ProjectOrderItemDto> get _notYetOrdered {
    return _items
        .where(
          (item) => item.orderedAt == null && item.expectedDeliveryDate == null,
        )
        .toList();
  }

  Widget _buildSummaryRow() {
    final total = _items.length;
    final notOrdered = _items
        .where((item) => item.orderStatus == 'In Progress')
        .length;
    final overdue = _items.where((item) => item.isOverdue).length;
    final delivered = _items
        .where((item) => item.orderStatus == 'In Stock' || item.orderStatus == 'Loaded' || item.orderStatus == 'Installed')
        .length;

    Widget stat(String label, int value, Color color) {
      return Expanded(
        child: Card(
          color: color.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        stat('Total Parts', total, AppColors.primaryDark),
        const SizedBox(width: 10),
        stat('In Progress', notOrdered, Colors.grey.shade700),
        const SizedBox(width: 10),
        stat('Overdue', overdue, AppColors.statusOverdue),
        const SizedBox(width: 10),
        stat('In Stock / Loaded / Installed', delivered, AppColors.statusDone),
      ],
    );
  }

  Widget _buildAttentionSection(List<ProjectOrderItemDto> attention) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.statusOverdue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.statusOverdue.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.statusOverdue,
              ),
              const SizedBox(width: 8),
              Text(
                'Needs Attention (${attention.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.statusOverdue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...attention.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: () => _openEditDialog(item),
                child: Row(
                  children: [
                    Icon(
                item.orderStatus == 'In Progress'
                    ? Icons.shopping_cart_outlined
                    : Icons.schedule,
                size: 18,
                color: AppColors.statusOverdue,
              ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.orderStatus == 'In Progress'
                            ? '${item.partName} — not yet ordered'
                            : '${item.partName} — expected ${_formatDate(item.expectedDeliveryDate)} (overdue)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartCard(ProjectOrderItemDto item) {
    final statusColor = _statusColor(item.orderStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openEditDialog(item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.partName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      item.orderStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (item.partNumber != null && item.partNumber!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Nr: ${item.partNumber} • Qty: ${item.quantity}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _infoChip(
                    Icons.confirmation_number_outlined,
                    'Order #: ${item.orderNumber ?? '-'}',
                  ),
                  _infoChip(
                    Icons.request_quote_outlined,
                    'Quotation #: ${item.quotationNumber ?? '-'}',
                  ),
                  _infoChip(
                    Icons.qr_code_outlined,
                    'ID: ${item.id.substring(0, item.id.length < 8 ? item.id.length : 8)}',
                  ),
                  _infoChip(
                    Icons.local_shipping_outlined,
                    'Shipping #: ${item.shippingNumber ?? '-'}',
                  ),
                  _infoChip(
                    Icons.business_outlined,
                    'Supplier: ${item.supplier ?? '-'}',
                  ),
                  _infoChip(
                    Icons.event_outlined,
                    'Delivery due: ${_formatDate(item.expectedDeliveryDate)}',
                    color: item.isOverdue ? AppColors.statusOverdue : null,
                  ),
                  if (item.actualDeliveryDate != null)
                    _infoChip(
                      Icons.check_circle_outline,
                      'Delivered: ${_formatDate(item.actualDeliveryDate)}',
                      color: AppColors.statusDone,
                    ),
                ],
              ),
              if (item.statusNotes != null && item.statusNotes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    item.statusNotes!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.black54),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: color != null ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }

  Future<void> _openEditDialog(ProjectOrderItemDto item) async {
    var status = item.orderStatus;
    final orderNumberCtrl = TextEditingController(
      text: item.orderNumber ?? '',
    );
    final quotationNumberCtrl = TextEditingController(
      text: item.quotationNumber ?? '',
    );
    final shippingNumberCtrl = TextEditingController(
      text: item.shippingNumber ?? '',
    );
    final supplierCtrl = TextEditingController(text: item.supplier ?? '');
    final notesCtrl = TextEditingController(text: item.statusNotes ?? '');
    var orderedAt = item.orderedAt;
    var expectedDelivery = item.expectedDeliveryDate;
    var actualDelivery = item.actualDeliveryDate;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickDate(
            DateTime? current,
            void Function(DateTime?) onPicked,
          ) async {
            final picked = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(DateTime.now().year - 2),
              lastDate: DateTime(DateTime.now().year + 3),
            );
            if (picked != null) {
              setDialogState(() => onPicked(picked));
            }
          }

          Widget dateRow(
            String label,
            DateTime? value,
            void Function(DateTime?) onPicked,
          ) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(_formatDate(value)),
              trailing: Wrap(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_calendar_outlined),
                    onPressed: () => pickDate(value, onPicked),
                  ),
                  if (value != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setDialogState(() => onPicked(null)),
                    ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: Text(item.partName),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ID: ${item.id}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: _statusOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => status = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Order Number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quotationNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quotation Number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: shippingNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Shipping Number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: supplierCtrl,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                  ),
                  const Divider(height: 24),
                  dateRow('Ordered On', orderedAt, (v) => orderedAt = v),
                  dateRow(
                    'Expected Delivery',
                    expectedDelivery,
                    (v) => expectedDelivery = v,
                  ),
                  dateRow(
                    'Actual Delivery',
                    actualDelivery,
                    (v) => actualDelivery = v,
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes'),
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
                        setDialogState(() => saving = true);
                        try {
                          final api = ref.read(apiClientProvider);
                          final updated = await api.updateProjectPartStatus(
                            projectId: widget.projectId,
                            itemId: item.id,
                            orderStatus: status,
                            orderNumber: orderNumberCtrl.text.trim(),
                            quotationNumber: quotationNumberCtrl.text.trim(),
                            shippingNumber: shippingNumberCtrl.text.trim(),
                            supplier: supplierCtrl.text.trim(),
                            orderedAt: orderedAt,
                            expectedDeliveryDate: expectedDelivery,
                            actualDeliveryDate: actualDelivery,
                            statusNotes: notesCtrl.text.trim(),
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setState(() {
                            _items = _items
                                .map(
                                  (existing) => existing.id == updated.id
                                      ? updated
                                      : existing,
                                )
                                .toList();
                          });
                          Navigator.pop(dialogContext);
                        } catch (error) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not save: $error'),
                              ),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    orderNumberCtrl.dispose();
    quotationNumberCtrl.dispose();
    shippingNumberCtrl.dispose();
    supplierCtrl.dispose();
    notesCtrl.dispose();
  }
}

/// Gantt-style delivery timeline for parts, matching the visual language of
/// ProjectSubGanttScreen: a fixed-width left column per row plus a
/// horizontally-scrollable day-by-day chart with colored bars. A part's bar
/// spans from its order date (or today, if not yet ordered but has an
/// expected date) to its expected/actual delivery date, colored by status.
/// A vertical "today" marker makes it immediately obvious which bars have
/// already run past today without the part being marked delivered.
class _PartsGanttChartView extends StatelessWidget {
  const _PartsGanttChartView({
    required this.items,
    required this.statusColor,
    required this.onTap,
  });

  final List<ProjectOrderItemDto> items;
  final Color Function(String status) statusColor;
  final void Function(ProjectOrderItemDto item) onTap;

  static const double _leftColumnWidth = 260;
  static const double _dayWidth = 26;
  static const double _rowHeight = 72;

  DateTime _barStart(ProjectOrderItemDto item) {
    return item.orderedAt ?? item.expectedDeliveryDate ?? DateTime.now();
  }

  DateTime _barEnd(ProjectOrderItemDto item) {
    final end =
        item.actualDeliveryDate ?? item.expectedDeliveryDate ?? _barStart(item);
    return end.isBefore(_barStart(item)) ? _barStart(item) : end;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    final starts = items.map(_barStart).toList()..add(todayDateOnly);
    final ends = items.map(_barEnd).toList()..add(todayDateOnly);
    final rangeStart = starts.reduce((a, b) => a.isBefore(b) ? a : b)
        .subtract(const Duration(days: 2));
    final rangeEnd = ends.reduce((a, b) => a.isAfter(b) ? a : b)
        .add(const Duration(days: 2));
    final totalDays = rangeEnd.difference(rangeStart).inDays + 1;
    final chartWidth = (totalDays * _dayWidth).clamp(320.0, 6000.0);
    final todayOffset = todayDateOnly.difference(rangeStart).inDays * _dayWidth;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: _leftColumnWidth,
                  child: Text(
                    'Part',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Timeline (today marked with the dashed line)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _leftColumnWidth + chartWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PartsGanttTimelineHeader(
                      leftColumnWidth: _leftColumnWidth,
                      timelineWidth: chartWidth,
                      start: rangeStart,
                      totalDays: totalDays,
                      dayWidth: _dayWidth,
                    ),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        Column(
                          children: items
                              .map(
                                (item) => _PartsGanttChartRow(
                                  item: item,
                                  leftColumnWidth: _leftColumnWidth,
                                  timelineWidth: chartWidth,
                                  timelineStart: rangeStart,
                                  totalDays: totalDays,
                                  dayWidth: _dayWidth,
                                  rowHeight: _rowHeight,
                                  barStart: _barStart(item),
                                  barEnd: _barEnd(item),
                                  color: statusColor(item.orderStatus),
                                  onTap: () => onTap(item),
                                ),
                              )
                              .toList(),
                        ),
                        // Vertical "today" marker across every row.
                        Positioned(
                          left: _leftColumnWidth + todayOffset + (_dayWidth / 2),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 2,
                              color: Colors.redAccent.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartsGanttTimelineHeader extends StatelessWidget {
  const _PartsGanttTimelineHeader({
    required this.leftColumnWidth,
    required this.timelineWidth,
    required this.start,
    required this.totalDays,
    required this.dayWidth,
  });

  final double leftColumnWidth;
  final double timelineWidth;
  final DateTime start;
  final int totalDays;
  final double dayWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(width: leftColumnWidth),
          SizedBox(
            width: timelineWidth,
            child: Stack(
              children: List.generate(totalDays, (index) {
                final day = start.add(Duration(days: index));
                final showLabel =
                    index == 0 || index == totalDays - 1 || day.day == 1;
                return Positioned(
                  left: index * dayWidth,
                  width: dayWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    alignment: Alignment.topCenter,
                    child: showLabel
                        ? Text(
                            '${day.month}/${day.day}',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartsGanttChartRow extends StatelessWidget {
  const _PartsGanttChartRow({
    required this.item,
    required this.leftColumnWidth,
    required this.timelineWidth,
    required this.timelineStart,
    required this.totalDays,
    required this.dayWidth,
    required this.rowHeight,
    required this.barStart,
    required this.barEnd,
    required this.color,
    required this.onTap,
  });

  final ProjectOrderItemDto item;
  final double leftColumnWidth;
  final double timelineWidth;
  final DateTime timelineStart;
  final int totalDays;
  final double dayWidth;
  final double rowHeight;
  final DateTime barStart;
  final DateTime barEnd;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftColumnWidth,
              height: rowHeight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.partName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            item.orderStatus,
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.orderNumber == null || item.orderNumber!.isEmpty
                          ? (item.supplier ?? '')
                          : 'Order #${item.orderNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: timelineWidth,
              height: rowHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: List.generate(
                        totalDays,
                        (index) => Container(
                          width: dayWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.grey.shade200),
                              bottom: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: barStart.difference(timelineStart).inDays * dayWidth,
                    top: 18,
                    width:
                        ((barEnd.difference(barStart).inDays + 1) * dayWidth)
                            .clamp(dayWidth, timelineWidth),
                    height: 24,
                    child: _PartsGanttBar(
                      label: item.orderStatus,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartsGanttBar extends StatelessWidget {
  const _PartsGanttBar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
