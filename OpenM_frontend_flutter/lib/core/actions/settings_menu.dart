import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_locale.dart';
import '../../services/auth_state.dart';

Future<void> openSettingsMenu({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final size = MediaQuery.sizeOf(context);
  final selection = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(size.width, kToolbarHeight + 12, 12, 0),
    items: const [
      PopupMenuItem(value: 'profile', child: Text('Profile')),
      PopupMenuItem(value: 'admin', child: Text('Admin')),
      PopupMenuItem(value: 'kanboard', child: Text('Kanboard')),
      PopupMenuItem(value: 'calendar', child: Text('Calendar')),
      PopupMenuItem(value: 'ticket', child: Text('Ticket')),
      PopupMenuItem(value: 'dashboard', child: Text('Dashboard')),
      PopupMenuItem(value: 'project', child: Text('Projects')),
      PopupMenuItem(value: 'mail_settings', child: Text('Mail Settings')),
      PopupMenuItem(value: 'de', child: Text('Deutsch')),
      PopupMenuItem(value: 'en', child: Text('Englisch')),
      PopupMenuItem(value: 'logout', child: Text('Logout')),
    ],
  );

  if (!context.mounted || selection == null) {
    return;
  }

  if (selection == 'logout') {
    await ref.read(authStateProvider.notifier).logout();
    if (!context.mounted) {
      return;
    }
    context.go('/login');
    return;
  }

  if (selection == 'admin') {
    context.push('/admin');
    return;
  }

  if (selection == 'kanboard') {
    context.push('/kanboard');
    return;
  }

  if (selection == 'calendar') {
    context.push('/calendar');
    return;
  }

  if (selection == 'ticket') {
    context.push('/ticket');
    return;
  }
  
  if (selection == 'dashboard') {
    context.push('/dashboard/overview');
    return;
  }


  if (selection == 'project') {
    context.push('/projectsoverview');
    return;
  }

  if (selection == 'mail_settings') {
    context.push('/account/mail-settings');
    return;
  }

  if (selection == 'profile') {
    context.push('/profile');
    return;
  }

  if (selection == 'de' || selection == 'en') {
    if (selection == 'de') {
      ref.read(appLocaleProvider.notifier).setGerman();
    } else {
      ref.read(appLocaleProvider.notifier).setEnglish();
    }
    final locale = ref.read(appLocaleProvider);
    final language = isGermanLocale(locale) ? 'Deutsch' : 'Englisch';
    final message = isGermanLocale(locale)
        ? 'Sprache wurde auf $language gesetzt.'
        : 'Language switched to $language.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
