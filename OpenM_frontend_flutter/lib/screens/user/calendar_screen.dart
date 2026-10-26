import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  bool _loading = true;
  bool _connecting = false;
  bool _googleConnected = false;
  bool _microsoftConnected = false;
  bool _officeConnected = true;
  DateTime _focusDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  List<TodoDto> _todos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final todos = await ref.read(apiClientProvider).todos();
    if (!mounted) {
      return;
    }
    setState(() {
      _todos = todos;
      _loading = false;
    });
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime? _todoDate(TodoDto todo) {
    final source = todo.endDate ?? todo.startDate;
    return source == null ? null : DateTime.tryParse(source);
  }

  List<TodoDto> _todosForDate(DateTime date) {
    final selected = _normalizeDate(date);
    final items = _todos.where((todo) {
      final parsed = _todoDate(todo);
      return parsed != null && _normalizeDate(parsed) == selected;
    }).toList();

    items.sort((a, b) {
      final left = _todoDate(a) ?? DateTime(2999);
      final right = _todoDate(b) ?? DateTime(2999);
      return left.compareTo(right);
    });
    return items;
  }

  Color _statusColor(String? status) {
    if (status == 'Done') {
      return AppColors.statusDone;
    }
    if (status == 'Overdue') {
      return AppColors.statusOverdue;
    }
    return AppColors.statusInWork;
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  bool get _hasConnectedProvider {
    return _googleConnected || _microsoftConnected || _officeConnected;
  }

  bool _isConnected(_CalendarProvider provider) {
    switch (provider) {
      case _CalendarProvider.google:
        return _googleConnected;
      case _CalendarProvider.microsoft:
        return _microsoftConnected;
      case _CalendarProvider.office:
        return _officeConnected;
    }
  }

  void _setConnected(_CalendarProvider provider, bool value) {
    switch (provider) {
      case _CalendarProvider.google:
        _googleConnected = value;
        break;
      case _CalendarProvider.microsoft:
        _microsoftConnected = value;
        break;
      case _CalendarProvider.office:
        _officeConnected = value;
        break;
    }
  }

  Future<void> _connectProvider(_CalendarProvider provider) async {
    final uri = Uri.parse(provider.connectUrl);
    setState(() {
      _connecting = true;
    });

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _connecting = false;
      if (launched) {
        _setConnected(provider, true);
      }
    });

    final message = launched
        ? '${provider.label} connection started. Finish sign-in in your browser.'
        : 'Could not open ${provider.label}. Please try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _disconnectProvider(_CalendarProvider provider) {
    if (provider == _CalendarProvider.office) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Office Calendar is the primary To-Do calendar and stays active.',
            ),
          ),
        );
      return;
    }

    setState(() {
      _setConnected(provider, false);
    });
  }

  Widget _buildProviderCard(_CalendarProvider provider) {
    final connected = _isConnected(provider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: provider.color.withValues(alpha: 0.18),
              child: Icon(provider.icon, color: provider.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.description,
                    style: TextStyle(color: AppColors.calendarTextMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            connected
                ? OutlinedButton.icon(
                    onPressed: provider == _CalendarProvider.office
                        ? null
                        : () => _disconnectProvider(provider),
                    icon: Icon(
                      provider == _CalendarProvider.office
                          ? Icons.lock
                          : Icons.link_off,
                    ),
                    label: Text(
                      provider == _CalendarProvider.office
                          ? 'Primary'
                          : 'Disconnect',
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _connecting
                        ? null
                        : () => _connectProvider(provider),
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionFirstView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.calendarInfoBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.calendarInfoBorder),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect your work calendar first',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'To-Dos are always kept in Office Calendar. You can also connect Google or Microsoft for additional visibility.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildProviderCard(_CalendarProvider.google),
        _buildProviderCard(_CalendarProvider.microsoft),
        _buildProviderCard(_CalendarProvider.office),
      ],
    );
  }

  Widget _buildCalendarTimeline() {
    final selectedDayTodos = _todosForDate(_selectedDate);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TableCalendar<TodoDto>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusDate,
            calendarFormat: CalendarFormat.week,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableCalendarFormats: const {CalendarFormat.week: 'Week'},
            selectedDayPredicate: (day) =>
                isSameDay(day, _normalizeDate(_selectedDate)),
            eventLoader: _todosForDate,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDate = _normalizeDate(selectedDay);
                _focusDate = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusDate = focusedDay;
              });
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: AppColors.calendarToday,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: AppColors.calendarSelected,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: AppColors.calendarMarker,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: selectedDayTodos.isEmpty
                ? const Center(child: Text('No scheduled actions on this day.'))
                : ListView.separated(
                    itemCount: selectedDayTodos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final todo = selectedDayTodos[index];
                      final start = todo.startDate ?? '-';
                      final end = todo.endDate ?? '-';
                      return Card(
                        color: _statusColor(todo.projectStatus),
                        child: ListTile(
                          title: Text(todo.name),
                          subtitle: Text(
                            'Start: $start | End: $end\n${todo.description ?? ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(todo.projectStatus ?? 'inWork'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Calendar',
      onAdd: _load,
      onSettings: _openSettings,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(flex: 3, child: _buildConnectionFirstView()),
                const Divider(height: 1),
                Expanded(
                  flex: 4,
                  child: _hasConnectedProvider
                      ? _buildCalendarTimeline()
                      : Center(
                          child: Text(
                            'Calendar timeline will appear after you connect a provider.',
                            style: TextStyle(
                              color: AppColors.calendarTextMuted,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

enum _CalendarProvider { google, microsoft, office }

extension _CalendarProviderValues on _CalendarProvider {
  String get label {
    switch (this) {
      case _CalendarProvider.google:
        return 'Google Calendar';
      case _CalendarProvider.microsoft:
        return 'Microsoft Calendar';
      case _CalendarProvider.office:
        return 'Office Calendar';
    }
  }

  String get description {
    switch (this) {
      case _CalendarProvider.google:
        return 'Connect to your Google Workspace calendar events.';
      case _CalendarProvider.microsoft:
        return 'Connect to Microsoft 365 and Outlook calendar.';
      case _CalendarProvider.office:
        return 'Connect with your Office account for shared meetings.';
    }
  }

  IconData get icon {
    switch (this) {
      case _CalendarProvider.google:
        return Icons.calendar_month;
      case _CalendarProvider.microsoft:
        return Icons.event_available;
      case _CalendarProvider.office:
        return Icons.business_center;
    }
  }

  Color get color {
    switch (this) {
      case _CalendarProvider.google:
        return AppColors.providerGoogle;
      case _CalendarProvider.microsoft:
        return AppColors.providerMicrosoft;
      case _CalendarProvider.office:
        return AppColors.providerOffice;
    }
  }

  String get connectUrl {
    switch (this) {
      case _CalendarProvider.google:
        return 'https://calendar.google.com/';
      case _CalendarProvider.microsoft:
        return 'https://outlook.office.com/calendar/';
      case _CalendarProvider.office:
        return 'https://www.office.com/launch/outlook';
    }
  }
}
