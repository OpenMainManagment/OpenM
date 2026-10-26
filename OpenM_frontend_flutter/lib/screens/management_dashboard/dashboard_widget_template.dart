import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';


import '../../../core/theme/app_colors.dart';

/// The time span a dashboard widget's data is grouped over.
enum DashboardTimeSpan { daily, weekly, monthly, custom }

/// How individual data points are bucketed for the chart's x-axis.
enum DashboardGranularity { day, week, month }

/// Which chart type a dashboard widget currently renders as.
enum DashboardChartType { line, bar, pie }

/// A resolved date range plus the bucket granularity to group data into,
/// derived from a [DashboardTimeSpan] (and, for [DashboardTimeSpan.custom],
/// an explicit from/till pair).
class DashboardTimeRange {
  const DashboardTimeRange({
    required this.start,
    required this.end,
    required this.granularity,
  });

  final DateTime start;
  final DateTime end;
  final DashboardGranularity granularity;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _startOfWeek(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  static DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  /// Resolves a [DashboardTimeSpan] into a concrete [DashboardTimeRange].
  /// For [DashboardTimeSpan.custom], [customFrom]/[customTill] are used
  /// (falling back to the last 30 days if omitted).
  factory DashboardTimeRange.resolve(
    DashboardTimeSpan span, {
    DateTime? customFrom,
    DateTime? customTill,
  }) {
    final today = _dateOnly(DateTime.now());

    switch (span) {
      case DashboardTimeSpan.daily:
        // Last 14 days, one bucket per day.
        return DashboardTimeRange(
          start: today.subtract(const Duration(days: 13)),
          end: today,
          granularity: DashboardGranularity.day,
        );
      case DashboardTimeSpan.weekly:
        // Last 12 weeks, one bucket per week (Mon-start).
        final startOfThisWeek = _startOfWeek(today);
        return DashboardTimeRange(
          start: startOfThisWeek.subtract(const Duration(days: 7 * 11)),
          end: today,
          granularity: DashboardGranularity.week,
        );
      case DashboardTimeSpan.monthly:
        // Last 12 months, one bucket per month.
        final startOfThisMonth = _startOfMonth(today);
        final start = DateTime(
          startOfThisMonth.year,
          startOfThisMonth.month - 11,
          1,
        );
        return DashboardTimeRange(
          start: start,
          end: today,
          granularity: DashboardGranularity.month,
        );
      case DashboardTimeSpan.custom:
        final from = _dateOnly(
          customFrom ?? today.subtract(const Duration(days: 30)),
        );
        final till = _dateOnly(customTill ?? today);
        final span = till.difference(from).inDays;
        final granularity = span <= 31
            ? DashboardGranularity.day
            : (span <= 120 ? DashboardGranularity.week : DashboardGranularity.month);
        return DashboardTimeRange(
          start: from,
          end: till,
          granularity: granularity,
        );
    }
  }

  DateTime _bucketStart(DateTime date) {
    switch (granularity) {
      case DashboardGranularity.day:
        return _dateOnly(date);
      case DashboardGranularity.week:
        return _startOfWeek(date);
      case DashboardGranularity.month:
        return _startOfMonth(date);
    }
  }

  DateTime _nextBucket(DateTime bucketStart) {
    switch (granularity) {
      case DashboardGranularity.day:
        return bucketStart.add(const Duration(days: 1));
      case DashboardGranularity.week:
        return bucketStart.add(const Duration(days: 7));
      case DashboardGranularity.month:
        return DateTime(bucketStart.year, bucketStart.month + 1, 1);
    }
  }

  String _bucketLabel(DateTime bucketStart) {
    switch (granularity) {
      case DashboardGranularity.day:
        return '${bucketStart.day}.${bucketStart.month}.';
      case DashboardGranularity.week:
        return '${bucketStart.day}.${bucketStart.month}.';
      case DashboardGranularity.month:
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return months[bucketStart.month - 1];
    }
  }

  /// The list of bucket start dates covering [start] to [end] (inclusive)
  /// at this range's granularity.
  List<DateTime> bucketStarts() {
    final buckets = <DateTime>[];
    var cursor = _bucketStart(start);
    final endBucket = _bucketStart(end);
    while (!cursor.isAfter(endBucket)) {
      buckets.add(cursor);
      cursor = _nextBucket(cursor);
    }
    return buckets;
  }

  /// Convenience helper for the common "count of events per bucket" case
  /// (e.g. how many new customer companies came in per week). Any
  /// timestamps outside [start]/[end] are ignored.
  List<DashboardDataPoint> bucketCounts(List<DateTime> timestamps) {
    final buckets = bucketStarts();
    final counts = {for (final b in buckets) b: 0};

    for (final timestamp in timestamps) {
      if (timestamp.isBefore(start) || timestamp.isAfter(end)) continue;
      final bucket = _bucketStart(timestamp);
      if (counts.containsKey(bucket)) {
        counts[bucket] = counts[bucket]! + 1;
      }
    }

    return buckets
        .map(
          (b) => DashboardDataPoint(
            date: b,
            label: _bucketLabel(b),
            value: counts[b]!.toDouble(),
          ),
        )
        .toList();
  }
}

/// One point of charted data: a bucket's date, its display label, and its
/// value.
class DashboardDataPoint {
  const DashboardDataPoint({
    required this.date,
    required this.label,
    required this.value,
  });

  final DateTime date;
  final String label;
  final double value;
}

/// Loads the chart data for a resolved [DashboardTimeRange]. Each concrete
/// dashboard widget supplies its own loader (e.g. fetch companies, then
/// bucket their creation dates).
typedef DashboardDataLoader = Future<List<DashboardDataPoint>> Function(
  DashboardTimeRange range,
);

/// Base template every Management Dashboard widget is built on top of.
///
/// Handles the parts every widget shares: a name + description header, a
/// daily/weekly/monthly/custom time span picker, a chart-type switch
/// (line/bar/pie), and loading/error/empty states around [dataLoader].
/// A concrete widget just supplies [name], [description], [valueLabel] and
/// [dataLoader] — see new_customer_companies_widget.dart for an example.
class DashboardWidgetTemplate extends StatefulWidget {
  const DashboardWidgetTemplate({
    super.key,
    required this.name,
    required this.description,
    required this.dataLoader,
    this.valueLabel = 'Value',
    this.initialTimeSpan = DashboardTimeSpan.weekly,
    this.initialChartType = DashboardChartType.line,
    this.allowedChartTypes = const [
      DashboardChartType.line,
      DashboardChartType.bar,
      DashboardChartType.pie,
    ],
  });

  final String name;
  final String description;
  final DashboardDataLoader dataLoader;
  final String valueLabel;
  final DashboardTimeSpan initialTimeSpan;
  final DashboardChartType initialChartType;
  final List<DashboardChartType> allowedChartTypes;

  @override
  State<DashboardWidgetTemplate> createState() =>
      _DashboardWidgetTemplateState();
}

class _DashboardWidgetTemplateState extends State<DashboardWidgetTemplate> {
  late DashboardTimeSpan _timeSpan = widget.initialTimeSpan;
  late DashboardChartType _chartType = widget.initialChartType;
  DateTime? _customFrom;
  DateTime? _customTill;

  late Future<List<DashboardDataPoint>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DashboardTimeRange get _range => DashboardTimeRange.resolve(
        _timeSpan,
        customFrom: _customFrom,
        customTill: _customTill,
      );

  void _reload() {
    _dataFuture = widget.dataLoader(_range);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: (_customFrom != null && _customTill != null)
          ? DateTimeRange(start: _customFrom!, end: _customTill!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
    );
    if (picked == null) return;
    setState(() {
      _customFrom = picked.start;
      _customTill = picked.end;
      _timeSpan = DashboardTimeSpan.custom;
      _reload();
    });
  }

  void _setTimeSpan(DashboardTimeSpan span) {
    if (span == DashboardTimeSpan.custom) {
      _pickCustomRange();
      return;
    }
    setState(() {
      _timeSpan = span;
      _reload();
    });
  }

  void _setChartType(DashboardChartType type) {
    setState(() => _chartType = type);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildTimeSpanSelector(),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: FutureBuilder<List<DashboardDataPoint>>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load data: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  final data = snapshot.data ?? const [];
                  if (data.isEmpty || data.every((d) => d.value == 0)) {
                    return const Center(
                      child: Text(
                        'No data in this time span.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return _buildChart(data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.description,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (widget.allowedChartTypes.length > 1) _buildChartTypeSwitch(),
      ],
    );
  }

  Widget _buildChartTypeSwitch() {
    return SegmentedButton<DashboardChartType>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        if (widget.allowedChartTypes.contains(DashboardChartType.line))
          const ButtonSegment(
            value: DashboardChartType.line,
            icon: Icon(Icons.show_chart, size: 18),
            tooltip: 'Line chart',
          ),
        if (widget.allowedChartTypes.contains(DashboardChartType.bar))
          const ButtonSegment(
            value: DashboardChartType.bar,
            icon: Icon(Icons.bar_chart, size: 18),
            tooltip: 'Bar chart',
          ),
        if (widget.allowedChartTypes.contains(DashboardChartType.pie))
          const ButtonSegment(
            value: DashboardChartType.pie,
            icon: Icon(Icons.pie_chart, size: 18),
            tooltip: 'Pie chart',
          ),
      ],
      selected: {_chartType},
      onSelectionChanged: (selection) => _setChartType(selection.first),
    );
  }

  Widget _buildTimeSpanSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Daily'),
          selected: _timeSpan == DashboardTimeSpan.daily,
          onSelected: (_) => _setTimeSpan(DashboardTimeSpan.daily),
        ),
        ChoiceChip(
          label: const Text('Weekly'),
          selected: _timeSpan == DashboardTimeSpan.weekly,
          onSelected: (_) => _setTimeSpan(DashboardTimeSpan.weekly),
        ),
        ChoiceChip(
          label: const Text('Monthly'),
          selected: _timeSpan == DashboardTimeSpan.monthly,
          onSelected: (_) => _setTimeSpan(DashboardTimeSpan.monthly),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 16),
          label: Text(
            _timeSpan == DashboardTimeSpan.custom &&
                    _customFrom != null &&
                    _customTill != null
                ? '${_customFrom!.day}.${_customFrom!.month}. - ${_customTill!.day}.${_customTill!.month}.'
                : 'From - Till',
          ),
          backgroundColor: _timeSpan == DashboardTimeSpan.custom
              ? AppColors.primaryDark.withValues(alpha: 0.15)
              : null,
          onPressed: _pickCustomRange,
        ),
      ],
    );
  }

  Widget _buildChart(List<DashboardDataPoint> data) {
    switch (_chartType) {
      case DashboardChartType.line:
        return _buildLineChart(data);
      case DashboardChartType.bar:
        return _buildBarChart(data);
      case DashboardChartType.pie:
        return _buildPieChart(data);
    }
  }

  Widget _titleFor(List<DashboardDataPoint> data, double value) {
    final index = value.round();
    if (index < 0 || index >= data.length) return const SizedBox.shrink();
    // Thin out labels when there are many buckets so they don't overlap.
    final step = (data.length / 8).ceil().clamp(1, data.length);
    if (step > 1 && index % step != 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(data[index].label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _buildLineChart(List<DashboardDataPoint> data) {
    final maxY = data.map((d) => d.value).fold<double>(0, (a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => _titleFor(data, value),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].value),
            ],
            isCurved: true,
            color: AppColors.primaryDark,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primaryDark.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<DashboardDataPoint> data) {
    final maxY = data.map((d) => d.value).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => _titleFor(data, value),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].value,
                  color: AppColors.primaryDark,
                  width: 14,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<DashboardDataPoint> data) {
    final total = data.fold<double>(0, (a, d) => a + d.value);
    final nonZero = data.where((d) => d.value > 0).toList();
    final palette = [
      AppColors.primaryDark,
      AppColors.primaryLight,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.indigo,
      Colors.pink,
      Colors.brown,
    ];

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: [
                for (var i = 0; i < nonZero.length; i++)
                  PieChartSectionData(
                    value: nonZero[i].value,
                    color: palette[i % palette.length],
                    title: total == 0
                        ? ''
                        : '${(nonZero[i].value / total * 100).round()}%',
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < nonZero.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          color: palette[i % palette.length],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${nonZero[i].label}: ${nonZero[i].value.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
