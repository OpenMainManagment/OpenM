import 'package:openm/screens/management_dashboard/dashboard_widget_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_state.dart';

/// Per-employee choice of which dashboard widgets to show, persisted
/// locally so each employee sees only what they picked.
class ManagementDashboardScreen extends ConsumerStatefulWidget {
  const ManagementDashboardScreen({super.key});

  @override
  ConsumerState<ManagementDashboardScreen> createState() =>
      _ManagementDashboardScreenState();
}

class _ManagementDashboardScreenState
    extends ConsumerState<ManagementDashboardScreen> {
  List<String>? _selectedWidgetIds;

  String get _prefsKey {
    final employeeName = ref.read(authStateProvider).employeeName ?? 'default';
    return 'dashboard.widgets.$employeeName';
  }

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  Future<void> _loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey);
    if (!mounted) return;
    setState(() {
      // Keep only ids that still exist in the catalog, so a widget that
      // gets removed later doesn't leave a dangling selection.
      final catalogIds = dashboardWidgetCatalog.map((e) => e.id).toSet();
      _selectedWidgetIds = (stored ?? defaultDashboardWidgetIds)
          .where(catalogIds.contains)
          .toList();
    });
  }

  Future<void> _saveSelection(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, ids);
  }

  Future<void> _openWidgetPicker() async {
    final current = {...?_selectedWidgetIds};
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _WidgetPickerDialog(initiallySelected: current),
    );
    if (updated == null) return;

    final orderedIds = dashboardWidgetCatalog
        .map((e) => e.id)
        .where(updated.contains)
        .toList();

    setState(() => _selectedWidgetIds = orderedIds);
    await _saveSelection(orderedIds);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = _selectedWidgetIds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Management Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined),
            tooltip: 'Choose widgets',
            onPressed: selectedIds == null ? null : _openWidgetPicker,
          ),
        ],
      ),
      body: selectedIds == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard Overview',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (selectedIds.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const Text(
                                'No widgets selected yet.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _openWidgetPicker,
                                icon: const Icon(Icons.add),
                                label: const Text('Add widgets'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      for (final entry in dashboardWidgetCatalog)
                        if (selectedIds.contains(entry.id))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: entry.builder(),
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WidgetPickerDialog extends StatefulWidget {
  const _WidgetPickerDialog({required this.initiallySelected});

  final Set<String> initiallySelected;

  @override
  State<_WidgetPickerDialog> createState() => _WidgetPickerDialogState();
}

class _WidgetPickerDialogState extends State<_WidgetPickerDialog> {
  late final Set<String> _selected = {...widget.initiallySelected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose your dashboard widgets'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in dashboardWidgetCatalog)
              CheckboxListTile(
                value: _selected.contains(entry.id),
                title: Text(entry.name),
                subtitle: Text(entry.description),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _selected.add(entry.id);
                    } else {
                      _selected.remove(entry.id);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
