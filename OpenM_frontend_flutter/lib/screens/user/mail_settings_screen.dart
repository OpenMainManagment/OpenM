import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class MailSettingsScreen extends ConsumerStatefulWidget {
  const MailSettingsScreen({super.key});

  @override
  ConsumerState<MailSettingsScreen> createState() =>
      _MailSettingsScreenState();
}

class _MailSettingsScreenState extends ConsumerState<MailSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasPassword = false;

  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '993');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _draftsFolderController = TextEditingController(text: 'Drafts');
  bool _useSsl = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _draftsFolderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final settings = await ref.read(apiClientProvider).getMyMailSettings();
      _hostController.text = settings.imapHost ?? '';
      _portController.text = settings.imapPort.toString();
      _usernameController.text = settings.imapUsername ?? '';
      _draftsFolderController.text = settings.draftsFolder;
      _useSsl = settings.imapUseSsl;
      _hasPassword = settings.hasPassword;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load mail settings: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final settings = await ref
          .read(apiClientProvider)
          .updateMyMailSettings(
            imapHost: _hostController.text.trim().isEmpty
                ? null
                : _hostController.text.trim(),
            imapPort: int.tryParse(_portController.text.trim()) ?? 993,
            imapUsername: _usernameController.text.trim().isEmpty
                ? null
                : _usernameController.text.trim(),
            imapPassword: _passwordController.text.trim().isEmpty
                ? null
                : _passwordController.text.trim(),
            imapUseSsl: _useSsl,
            draftsFolder: _draftsFolderController.text.trim().isEmpty
                ? 'Drafts'
                : _draftsFolderController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _hasPassword = settings.hasPassword;
          _passwordController.clear();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mail settings saved')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Mail Settings',
      onAdd: () {},
      onSettings: () {},
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Mailbox (IMAP)',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Used by the "Save Email Draft" workflow node to '
                          'file drafts directly into your own mailbox.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            labelText: 'IMAP Host',
                            hintText: 'imap.gmail.com',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'IMAP Port',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username (usually your email)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: _hasPassword
                                ? 'Password (leave blank to keep current)'
                                : 'Password',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _draftsFolderController,
                          decoration: const InputDecoration(
                            labelText: 'Drafts folder name',
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use SSL'),
                          value: _useSsl,
                          onChanged: (value) {
                            setState(() => _useSsl = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _save,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save Mail Settings'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
