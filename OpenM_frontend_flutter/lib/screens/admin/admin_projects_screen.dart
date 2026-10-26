import 'dart:async';

import 'package:openm/models/dtos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';

import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/todo_strip.dart';

class AdminProjectsScreen extends ConsumerStatefulWidget {
  const AdminProjectsScreen({super.key});

  @override
  ConsumerState<AdminProjectsScreen> createState() => _AdminProjectsScreenState();
}

class _AdminProjectsScreenState extends ConsumerState<AdminProjectsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<ProjectDto> _projects = const [];

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
    // For now, let's fetch all projects by getting them through companies
    // This is a temporary workaround until backend API supports direct project listing
    List<ProjectDto> projects = [];
    
    try {
      // Get all companies first to get their projects 
      final companies = await api.clientCompanies();
      for (final company in companies) {
        final companyProjects = await api.projectsByClientCompany(company.id);
        projects.addAll(companyProjects);
      }
      
      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
      });
    } catch (error) {
      // Handle error gracefully
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load projects: $error')),
        );
      }
    }
  }

  void _openSettings() {
    openSettingsMenu(context: context, ref: ref);
  }

  Color _statusColor(String status) {
    if (status == 'Done') {
      return AppColors.statusDone;
    }
    if (status == 'Overdue') {
      return AppColors.statusOverdue;
    }
    return AppColors.projectStatusDefault;
  }

  Color _statusBackgroundColor(String status) {
    return _statusColor(status).withValues(alpha: 0.12);
  }

  String _baseModelLabel(String baseModel) {
    switch (baseModel.toLowerCase()) {
      case 'normal':
        return 'Normal';
      case 'duble':
        return 'Duble';
      case 'extra':
        return 'Extra';
      default:
        return baseModel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Project Overview',
      onAdd: () {},
      onSettings: _openSettings,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TopTodoStrip(),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search projects',
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
                itemCount: _projects.length,
                itemBuilder: (_, index) {
                  final p = _projects[index];
                  final accentColor = _statusColor(p.status);
                  return Card(
                    color: _statusBackgroundColor(p.status),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: accentColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 10,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${p.status} • ${_baseModelLabel(p.baseModel)}',
                        style: TextStyle(color: accentColor),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () {},
                        child: const Text('Edit Base Model'),
                      ),
                      onTap: () => context.push(
                        '/projects/${p.id}/folders?name=${Uri.encodeComponent(p.name)}',
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