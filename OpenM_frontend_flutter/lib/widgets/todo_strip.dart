import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../models/dtos.dart';
import '../services/api_client.dart';
import 'todo_actions.dart';

class TopTodoStrip extends StatelessWidget {
  const TopTodoStrip({
    super.key,
    this.companyId,
    this.customerCompanyId,
    this.projectId,
    this.folderId,
    this.emptyLabel = 'No ToDos',
  });

  final String? companyId;
  final String? customerCompanyId;
  final String? projectId;
  final String? folderId;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return TodoStrip(
      companyId: companyId,
      customerCompanyId: customerCompanyId,
      projectId: projectId,
      folderId: folderId,
      emptyLabel: emptyLabel,
    );
  }
}

class TodoStrip extends ConsumerStatefulWidget {
  const TodoStrip({
    super.key,
    this.companyId,
    this.customerCompanyId,
    this.projectId,
    this.folderId,
    this.emptyLabel = 'No ToDos',
    this.height = 90,
  });

  final String? companyId;
  final String? customerCompanyId;
  final String? projectId;
  final String? folderId;
  final String emptyLabel;
  final double height;

  @override
  ConsumerState<TodoStrip> createState() => _TodoStripState();
}

class _TodoStripState extends ConsumerState<TodoStrip> {
  List<TodoDto> _todos = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodoStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.customerCompanyId != widget.customerCompanyId ||
        oldWidget.projectId != widget.projectId ||
        oldWidget.folderId != widget.folderId) {
      _load();
    }
  }

  bool _isDoneStatus(String? status) =>
      (status ?? '').trim().toLowerCase() == 'done';

  bool _isOverdueStatus(String? status) =>
      (status ?? '').trim().toLowerCase() == 'overdue';

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final todos = await api.todos(
        companyId: widget.companyId,
        clientCompanyId: widget.customerCompanyId,
        projectId: widget.projectId,
        folderId: widget.folderId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _todos = todos
            .where((todo) => !_isDoneStatus(todo.projectStatus))
            .toList();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load ToDos: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoActions = TodoActions(context: context, ref: ref, reload: _load);

    return SizedBox(
      height: widget.height,
      child: _loading && _todos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _todos.isEmpty
          ? Center(
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.error_outline, color: Colors.red),
                label: const Text(
                  'Failed to load ToDos — tap to retry',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            )
          : _todos.isEmpty
          ? Center(child: Text(widget.emptyLabel))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(width: 8),
                  ...List.generate(_todos.length, (index) {
                    final todo = _todos[index];
                    final isOverdue = _isOverdueStatus(todo.projectStatus);
                    final hasCoworkers = todo.coworkerLogins.isNotEmpty;
                    return ActionChip(
                      onPressed: () => todoActions.openOverview(todo),
                      backgroundColor: isOverdue
                          ? AppColors.statusOverdue
                          : hasCoworkers
                          ? AppColors.coworkerHighlight
                          : null,
                      label: Text('${todo.name}  ${todo.endDate ?? ''}'),
                    );
                  }),
                  SizedBox(width: 8),
                ],
              ),
            ),
    );
  }
}