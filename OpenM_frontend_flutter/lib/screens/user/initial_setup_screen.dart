import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';

class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({
    required this.onSetupComplete,
    this.resetLegacyAdminPassword = false,
    this.existingOrganizationName,
    super.key,
  });

  final Future<void> Function(String token, String loginName) onSetupComplete;
  final bool resetLegacyAdminPassword;
  final String? existingOrganizationName;

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _organizationNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _loginNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.resetLegacyAdminPassword) {
      _organizationNameController.text =
          widget.existingOrganizationName ?? 'OpenM';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      final token = await api.initializeApplication(
        organizationName: _organizationNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        loginName: _loginNameController.text.trim(),
        password: _passwordController.text,
      );
      await widget.onSetupComplete(token, _loginNameController.text.trim());
    } on DioException catch (error) {
      final responseData = error.response?.data;
      final detail = responseData is Map<String, dynamic>
          ? responseData['detail']
          : null;
      _showError(
        detail?.toString() ??
            'Could not complete setup. Check the server connection and try again.',
      );
    } catch (error) {
      _showError('Could not complete setup: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _organizationNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _loginNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OpenM initial setup')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.resetLegacyAdminPassword
                        ? 'Secure your administrator account'
                        : 'Create your administrator account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.resetLegacyAdminPassword
                        ? 'The existing administrator account is locked until you set a new password. '
                              'Your organization and project data will be kept.'
                        : 'This one-time setup creates the organization and its first administrator. '
                              'Choose a unique password with at least 12 characters.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (widget.resetLegacyAdminPassword) ...[
                    Text(
                      'Organization: ${_organizationNameController.text}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    _requiredField(
                      controller: _organizationNameController,
                      label: 'Organization name',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _requiredField(
                    controller: _firstNameController,
                    label: 'First name',
                  ),
                  const SizedBox(height: 12),
                  _requiredField(
                    controller: _lastNameController,
                    label: 'Last name',
                  ),
                  const SizedBox(height: 12),
                  _requiredField(
                    controller: _emailController,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty || !text.contains('@')) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _requiredField(
                    controller: _loginNameController,
                    label: 'Login name',
                    validator: (value) {
                      if ((value?.trim().length ?? 0) < 3) {
                        return 'Use at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _requiredField(
                    controller: _passwordController,
                    label: 'Administrator password',
                    obscureText: true,
                    validator: (value) {
                      if ((value?.length ?? 0) < 12) {
                        return 'Use at least 12 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _requiredField(
                    controller: _confirmPasswordController,
                    label: 'Confirm password',
                    obscureText: true,
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(
                      _isSaving
                          ? 'Creating account...'
                          : 'Create administrator',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _requiredField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: obscureText ? null : const [AutofillHints.username],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => value == null || value.trim().isEmpty
              ? 'This field is required'
              : null,
    );
  }
}
