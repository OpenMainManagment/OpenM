import 'package:flutter/material.dart';

import '../models/dtos.dart';

class TodoEditValues {
  const TodoEditValues({
    required this.name,
    required this.description,
    required this.startDate,
    required this.endDate,
  });

  final String name;
  final String? description;
  final String? startDate;
  final String? endDate;
}

class TodoEditDialog extends StatefulWidget {
  const TodoEditDialog({super.key, required this.todo, required this.onSave});

  final TodoDto todo;
  final Future<void> Function(TodoEditValues values) onSave;

  static Future<void> show({
    required BuildContext context,
    required TodoDto todo,
    required Future<void> Function(TodoEditValues values) onSave,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => TodoEditDialog(todo: todo, onSave: onSave),
    );
  }

  @override
  State<TodoEditDialog> createState() => _TodoEditDialogState();
}

class _TodoEditDialogState extends State<TodoEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  String? _startDate;
  String? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.todo.name);
    _descriptionCtrl = TextEditingController(
      text: widget.todo.description ?? '',
    );
    _startDate = widget.todo.startDate;
    _endDate = widget.todo.endDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<String?> _pickDateValue({String? initialDate}) async {
    final initial = DateTime.tryParse(initialDate ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return null;
    }
    return picked.toIso8601String().split('T').first;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await widget.onSave(
        TodoEditValues(
          name: title,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
        ),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not update ToDo.')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit ToDo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickDateValue(
                        initialDate: _startDate,
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _startDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _startDate == null ? 'Start date' : 'Start: $_startDate',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickDateValue(
                        initialDate: _endDate,
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _endDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      _endDate == null ? 'End date' : 'End: $_endDate',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
