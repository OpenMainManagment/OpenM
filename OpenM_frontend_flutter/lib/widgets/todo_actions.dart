import 'package:openm/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dtos.dart';

import 'todo_edit_dialog.dart';
import 'todo_overview_dialog.dart';

class TodoActions {
  TodoActions({required this.context, required this.ref, required this.reload});

  final BuildContext context;
  final WidgetRef ref;
  final Future<void> Function() reload;

  Future<void> markDone(TodoDto todo) async {
    try {
      await ref
          .read(apiClientProvider).updateTodo(
            todoId: todo.id,
            name: todo.name,
            companyId: todo.companyId,
            projectId: todo.projectId,
            folderId: todo.folderId,
            mainEmployer: todo.mainEmployer,
            coworkerLogins: todo.coworkerLogins,
            description: todo.description,
            startDate: todo.startDate,
            endDate: todo.endDate,
            projectStatus: 'Done',
          );
      await reload();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ToDo moved to Done.')));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move ToDo to Done.')),
      );
    }
  }

  Future<void> edit(TodoDto todo) async {
    await TodoEditDialog.show(
      context: context,
      todo: todo,
      onSave: (values) async {
        await ref
            .read(apiClientProvider)
            .updateTodo(
              todoId: todo.id,
              name: values.name,
              companyId: todo.companyId,
              projectId: todo.projectId,
              folderId: todo.folderId,
              mainEmployer: todo.mainEmployer,
              coworkerLogins: todo.coworkerLogins,
              description: values.description,
              startDate: values.startDate,
              endDate: values.endDate,
              projectStatus: todo.projectStatus,
            );
        await reload();
      },
    );
  }

  Future<void> openOverview(TodoDto todo) async {
    await showTodoOverviewDialog(
      context: context,
      todo: todo,
      onDone: () => markDone(todo),
      onEdit: () => edit(todo),
    );
  }
}
