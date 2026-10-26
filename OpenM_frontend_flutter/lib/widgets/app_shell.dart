import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.pageName,
    required this.onAdd,
    required this.onSettings,
    required this.child,
  });

  final String pageName;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.appShellHeaderBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.appShellHeaderBorder),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.go('/companies'),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        'Organisation',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: onAdd,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.hoverLight,
                      foregroundColor: AppColors.primaryDark,
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        pageName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.hoverLight,
                      foregroundColor: AppColors.primaryDark,
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
