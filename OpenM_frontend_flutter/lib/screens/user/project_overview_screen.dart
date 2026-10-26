import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/project_status_bar.dart';

class ProjectOverviewScreen extends ConsumerStatefulWidget {
  const ProjectOverviewScreen({super.key});

  @override
  ConsumerState<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends ConsumerState<ProjectOverviewScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<ProjectDto> _projects = [];
  final List<ProjectDto> _filteredProjects = [];
  bool _isLoading = false;
  bool _showCompleted = false;
  String _sortBy = 'start_date_newest';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _filterProjects();
      });
    });
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      // We need to get the current employee's company ID first
      final employee = await api.getCurrentEmployee();
      
      if (!mounted) return;
      
      List<ProjectDto> projects;
      if (employee.companyId != null) {
        // If employee belongs to a company, load projects for that company
        projects = await api.projectsByMainCompany(employee.companyId!);
      } else {
        // Otherwise, we might need to handle this case differently
        projects = [];
      }
      
      setState(() {
        _projects.clear();
        _projects.addAll(projects);
        _filterProjects();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading projects: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _filterProjects() {
    String searchTerm = _searchController.text.trim().toLowerCase();
    
    List<ProjectDto> filtered = _projects;
    
    // Filter by search term
    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((project) {
        return project.name.toLowerCase().contains(searchTerm) ||
            project.companyId.toLowerCase().contains(searchTerm);
      }).toList();
    }
    
    // Filter by completed status
    if (!_showCompleted) {
      filtered = filtered.where((project) => project.status != 'Completed').toList();
    }
    
    // Sort projects
    switch (_sortBy) {
      case 'start_date_newest':
        filtered.sort((a, b) => a.id.compareTo(b.id)); // Simplified sorting for now
        break;
      case 'start_date_oldest':
        filtered.sort((a, b) => b.id.compareTo(a.id)); // Reverse for oldest first
        break;
      case 'name_az':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'name_za':
        filtered.sort((a, b) => b.name.compareTo(a.name));
        break;
    }

    _filteredProjects.clear();
    _filteredProjects.addAll(filtered);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Project Overview',
      onAdd: () {},
      onSettings: () {},
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search field and controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search projects...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(value: 'start_date_newest', child: Text('Start Date (Newest)')),
                    DropdownMenuItem(value: 'start_date_oldest', child: Text('Start Date (Oldest)')),
                    DropdownMenuItem(value: 'name_az', child: Text('Project Name (A-Z)')),
                    DropdownMenuItem(value: 'name_za', child: Text('Project Name (Z-A)')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _sortBy = value;
                        _filterProjects();
                      });
                    }
                  },
                ),
                const SizedBox(width: 16),
                Checkbox(
                  value: _showCompleted,
                  onChanged: (value) {
                    setState(() {
                      _showCompleted = value ?? false;
                      _filterProjects();
                    });
                  },
                ),
                const Text('Show Completed'),
              ],
            ),
            const SizedBox(height: 16),
            
            // Projects list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProjects.isEmpty
                      ? const Center(child: Text('No projects found'))
                      : ListView.builder(
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                onTap: () {
                                  context.push('/companies/${project.companyId}/projects/${project.id}/notes');
                                },
                                title: Text(
                                  project.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Company: ${project.companyId}'), // Note: we don't have company name here
                                    Text('Status: ${project.status}'),
                                    const SizedBox(height: 8),
                                    ProjectStatusBar(project: project, showNavigationButtons: false),
                                  ],
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