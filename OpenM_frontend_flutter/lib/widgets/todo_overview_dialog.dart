import 'package:flutter/material.dart';

import '../models/dtos.dart';

String _displayTodoValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '-' : text;
}

Future<void> showTodoOverviewDialog({
  required BuildContext context,
  required TodoDto todo,
  required Future<void> Function() onDone,
  required Future<void> Function() onEdit,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ToDo Overview'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                todo.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text('Description: ${_displayTodoValue(todo.description)}'),
              const SizedBox(height: 6),
              Text(
                'Status: ${_displayTodoValue(todo.projectStatus ?? 'inWork')}',
              ),
              const SizedBox(height: 6),
              Text('Start date: ${_displayTodoValue(todo.startDate)}'),
              const SizedBox(height: 6),
              Text('End date: ${_displayTodoValue(todo.endDate)}'),
              const SizedBox(height: 6),
              Text('Main employer: ${_displayTodoValue(todo.mainEmployer)}'),
              const SizedBox(height: 6),
              Text(
                'Coworkers: ${todo.coworkerLogins.isEmpty ? '-' : todo.coworkerLogins.join(', ')}',
              ),
              const SizedBox(height: 6),
              Text('Company ID: ${_displayTodoValue(todo.companyId)}'),
              const SizedBox(height: 6),
              Text('Project ID: ${_displayTodoValue(todo.projectId)}'),
              const SizedBox(height: 6),
              Text('Folder ID: ${_displayTodoValue(todo.folderId)}'),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await onEdit();
                },
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await onDone();
                },
                child: const Text('Task done'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
