import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_locale.dart';
import 'core/app_router.dart';
import 'core/localization.dart';
import 'core/theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/auth_state.dart';

final startupSessionCheckProvider = FutureProvider<void>((ref) async {
  final auth = ref.read(authStateProvider.notifier);
  await auth.ready;
  if (!ref.read(authStateProvider).isAuthenticated) return;

  final setupStatus = await ref.read(apiClientProvider).initialSetupStatus();
  if (setupStatus.setupRequired) {
    await auth.logout();
  }
});

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(appLocaleProvider);
    final startupCheck = ref.watch(startupSessionCheckProvider);

    if (startupCheck.isLoading || startupCheck.hasError) {
      return MaterialApp(
        title: 'OpenM',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: startupCheck.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not check whether OpenM needs initial setup. '
                        'Please verify the server connection.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(startupSessionCheckProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    }

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'OpenM',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: appLocale,
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: const [
        L10n.delegate,
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
