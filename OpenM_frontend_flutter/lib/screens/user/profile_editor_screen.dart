import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/actions/settings_menu.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _jobDescriptionController = TextEditingController();

  EmployeeDto? _employee;
  Uint8List? _photoBytes;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _jobDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final employee = await api.getCurrentEmployee();
      final photoBytes = await api.myProfilePhotoBytes();
      if (!mounted) return;
      setState(() {
        _employee = employee;
        _firstNameController.text = employee.firstName;
        _lastNameController.text = employee.lastName;
        _emailController.text = employee.email;
        _jobDescriptionController.text = employee.jobDescription ?? '';
        _photoBytes = photoBytes != null ? Uint8List.fromList(photoBytes) : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Could not load your profile: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePhoto() async {
    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not open the photo picker: $e');
      return;
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() => _isUploadingPhoto = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.uploadMyProfilePhoto(
        imageBytes: bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _employee = updated;
        _photoBytes = bytes;
        _isUploadingPhoto = false;
      });
      _showSuccess('Profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      _showError('Could not upload photo: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      final updated = await api.updateMyProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        jobDescription: _jobDescriptionController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _employee = updated;
        _isSaving = false;
      });
      _showSuccess('Profile saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Could not save profile: $e');
    }
  }

  Future<void> _openChangePasswordDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ChangePasswordDialog(
        onSubmit: (currentPassword, newPassword) async {
          final api = ref.read(apiClientProvider);
          await api.changeMyPassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'My Profile',
      onAdd: () {},
      onSettings: () => openSettingsMenu(context: context, ref: ref),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _buildPhotoPicker()),
                        const SizedBox(height: 24),
                        _buildInfoCard(),
                        const SizedBox(height: 20),
                        _buildPasswordCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPhotoPicker() {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
              backgroundImage: _photoBytes != null ? MemoryImage(_photoBytes!) : null,
              child: _photoBytes == null
                  ? Text(
                      _initials(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: InkWell(
                onTap: _isUploadingPhoto ? null : _changePhoto,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: _isUploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isUploadingPhoto ? null : _changePhoto,
          child: const Text('Change photo'),
        ),
      ],
    );
  }

  String _initials() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final a = first.isNotEmpty ? first[0] : '';
    final b = last.isNotEmpty ? last[0] : '';
    final initials = ('$a$b').toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  Widget _buildInfoCard() {
    final employee = _employee;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(labelText: 'First Name'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(labelText: 'Last Name'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Required';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _jobDescriptionController,
              decoration: const InputDecoration(labelText: 'Job Description'),
            ),
            if (employee != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _buildReadOnlyRow('Login Name', employee.loginName),
              _buildReadOnlyRow('Role', employee.role ?? '-'),
              _buildReadOnlyRow('Department', employee.department ?? '-'),
              const SizedBox(height: 4),
              Text(
                'Login name, role and department are managed by an admin.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Change the password you use to log in.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _openChangePasswordDialog,
              child: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onSubmit});

  final Future<void> Function(String currentPassword, String newPassword) onSubmit;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _currentPasswordController.text,
        _newPasswordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Could not change password: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentPasswordController,
                decoration: const InputDecoration(labelText: 'Current Password'),
                obscureText: true,
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPasswordController,
                decoration: const InputDecoration(labelText: 'New Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (value.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(labelText: 'Confirm New Password'),
                obscureText: true,
                validator: (value) {
                  if (value != _newPasswordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }
}
