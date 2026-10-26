import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the project the user is currently viewing (if any), so the
/// global chat overlay can attach full project context when asked a
/// question while on a project screen.
final currentProjectIdProvider = StateProvider<String?>((ref) => null);
