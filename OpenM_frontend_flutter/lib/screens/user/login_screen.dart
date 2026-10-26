import 'package:openm/core/app_router.dart';
import 'package:openm/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_state.dart';
import 'initial_setup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isCheckingSetup = true;
  bool _setupRequired = false;
  Object? _setupCheckError;
  InitialSetupStatus? _setupStatus;

  @override
  void initState() {
    super.initState();
    _checkInitialSetup();
  }

  Future<void> _checkInitialSetup() async {
    setState(() {
      _isCheckingSetup = true;
      _setupCheckError = null;
    });
    try {
      final setupStatus = await ref
          .read(apiClientProvider)
          .initialSetupStatus();
      if (!mounted) return;
      setState(() {
        _setupStatus = setupStatus;
        _setupRequired = setupStatus.setupRequired;
        _isCheckingSetup = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _setupCheckError = error;
        _isCheckingSetup = false;
      });
    }
  }

  Future<void> _completeSetup(String token, String loginName) async {
    await ref
        .read(authStateProvider.notifier)
        .login(token: token, employeeName: loginName);
    if (!mounted) return;
    ref.read(appRouterProvider).go('/companies');
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both username and password'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ref.read(apiClientProvider);
      final token = await api.login(
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      // Save token to auth state and persist it for reloads
      final authNotifier = ref.read(authStateProvider.notifier);
      await authNotifier.login(
        token: token,
        employeeName: _usernameController.text,
      );

      if (!mounted) {
        return;
      }

      // Navigate directly to companies screen (we'll get role in a separate call if needed)
      final router = ref.read(appRouterProvider);
      router.push('/companies');
    } on DioException catch (e) {
      debugPrint('Login error: $e');
      String errorMessage = 'Login failed. Please check your credentials.';

      // Handle specific types of errors
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Connection timeout. Please check your internet connection.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Request timeout. Server is taking too long to respond.';
      } else if (e.type == DioExceptionType.sendTimeout) {
        errorMessage = 'Send timeout. Please try again.';
      } else if (e.response?.statusCode == 401) {
        errorMessage = 'Invalid username or password. Please try again.';
      } else if (e.response?.statusCode == 404) {
        errorMessage = 'Server not found. Please contact support.';
      } else if (e.response?.statusCode == 500) {
        errorMessage = 'Internal server error. Please try again later.';
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login failed. Please check your credentials. Error: ${e.toString()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSetup) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_setupCheckError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('OpenM')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not check whether OpenM needs initial setup. '
                  'Please verify the server connection.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _checkInitialSetup,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_setupRequired) {
      return InitialSetupScreen(
        onSetupComplete: _completeSetup,
        resetLegacyAdminPassword:
            _setupStatus?.legacyAdminPasswordReset ?? false,
        existingOrganizationName: _setupStatus?.organizationName,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Login'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo or App Title
            const Icon(Icons.account_circle, size: 100, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Management System',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            // Username field
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),

            // Password field
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 20),

            // Remember me checkbox
            Row(
              children: [
                Checkbox(
                  value: false,
                  onChanged: (bool? value) {
                    // Handle remember me logic
                  },
                ),
                const Text('Remember me'),
              ],
            ),
            const SizedBox(height: 16),

            // Login button
            if (_isLoading)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Login', style: TextStyle(fontSize: 18)),
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
