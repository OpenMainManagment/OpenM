import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminServerSettingsScreen extends ConsumerStatefulWidget {
  const AdminServerSettingsScreen({super.key});

  @override
  ConsumerState<AdminServerSettingsScreen> createState() =>
      _AdminServerSettingsScreenState();
}

class _AdminServerSettingsScreenState
    extends ConsumerState<AdminServerSettingsScreen> {
  bool _isLoading = true;
  String? _error;

  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUsernameController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _mailFromController = TextEditingController();
  bool _smtpUseTls = true;
  bool _hasSmtpPassword = false;

  List<AiServerConfigDto> _aiServers = [];
  bool _isSavingEmail = false;
  bool _isSavingAiServers = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUsernameController.dispose();
    _smtpPasswordController.dispose();
    _mailFromController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final settings = await ref.read(apiClientProvider).getServerSettings();
      _smtpHostController.text = settings.smtpHost ?? '';
      _smtpPortController.text = settings.smtpPort?.toString() ?? '587';
      _smtpUsernameController.text = settings.smtpUsername ?? '';
      _mailFromController.text = settings.mailFrom ?? '';
      _smtpUseTls = settings.smtpUseTls;
      _hasSmtpPassword = settings.hasSmtpPassword;
      _aiServers = List.of(settings.aiServers);
    } catch (error) {
      _error = 'Failed to load server settings: $error';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveEmailSettings() async {
    setState(() => _isSavingEmail = true);
    try {
      final settings = await ref
          .read(apiClientProvider)
          .updateEmailSettings(
            smtpHost: _smtpHostController.text.trim().isEmpty
                ? null
                : _smtpHostController.text.trim(),
            smtpPort: int.tryParse(_smtpPortController.text.trim()),
            smtpUsername: _smtpUsernameController.text.trim().isEmpty
                ? null
                : _smtpUsernameController.text.trim(),
            smtpPassword: _smtpPasswordController.text.trim().isEmpty
                ? null
                : _smtpPasswordController.text.trim(),
            smtpUseTls: _smtpUseTls,
            mailFrom: _mailFromController.text.trim().isEmpty
                ? null
                : _mailFromController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _hasSmtpPassword = settings.hasSmtpPassword;
          _smtpPasswordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email server settings saved')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingEmail = false);
      }
    }
  }

  Future<void> _saveAiServers() async {
    setState(() => _isSavingAiServers = true);
    try {
      await ref.read(apiClientProvider).updateAiServers(_aiServers);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI servers saved')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingAiServers = false);
      }
    }
  }

  Future<void> _openAiServerDialog({AiServerConfigDto? existing, int? index}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final baseUrlController = TextEditingController(
      text: existing?.baseUrl ?? (existing == null ? 'http://localhost:11434' : ''),
    );
    final apiKeyController = TextEditingController(text: existing?.apiKey ?? '');
    final modelController = TextEditingController(text: existing?.model ?? '');
    var provider = existing?.provider ?? 'ollama';

    final result = await showDialog<AiServerConfigDto>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add AI Server' : 'Edit AI Server'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name (shown in the node dropdown)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: provider,
                      decoration: const InputDecoration(labelText: 'Provider'),
                      items: const [
                        DropdownMenuItem(
                          value: 'ollama',
                          child: Text('Ollama (native API)'),
                        ),
                        DropdownMenuItem(
                          value: 'openai_compatible',
                          child: Text('OpenAI-compatible (LM Studio, etc.)'),
                        ),
                      ],
                      onChanged: (value) {
                        setLocalState(() {
                          provider = value ?? 'ollama';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'http://localhost:11434',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelController,
                      decoration: const InputDecoration(
                        labelText: 'Model (optional)',
                        hintText: 'llama3',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key (optional)',
                      ),
                      obscureText: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        baseUrlController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Name and Base URL are required.'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      AiServerConfigDto(
                        name: nameController.text.trim(),
                        provider: provider,
                        baseUrl: baseUrlController.text.trim(),
                        apiKey: apiKeyController.text.trim().isEmpty
                            ? null
                            : apiKeyController.text.trim(),
                        model: modelController.text.trim().isEmpty
                            ? null
                            : modelController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    baseUrlController.dispose();
    apiKeyController.dispose();
    modelController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      if (index != null) {
        _aiServers[index] = result;
      } else {
        _aiServers.add(result);
      }
    });
    await _saveAiServers();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Server Settings',
      onAdd: () {},
      onSettings: () {},
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.email_outlined,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Email Server (SMTP)',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Used by every workflow node that sends email '
                            '(Ticket, Parts Offer, Parts Order, ...).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _smtpHostController,
                            decoration: const InputDecoration(
                              labelText: 'SMTP Host',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _smtpPortController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'SMTP Port',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _smtpUsernameController,
                            decoration: const InputDecoration(
                              labelText: 'SMTP Username',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _smtpPasswordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: _hasSmtpPassword
                                  ? 'SMTP Password (leave blank to keep current)'
                                  : 'SMTP Password',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _mailFromController,
                            decoration: const InputDecoration(
                              labelText: 'Mail From (defaults to username)',
                            ),
                          ),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use STARTTLS'),
                            value: _smtpUseTls,
                            onChanged: (value) {
                              setState(() => _smtpUseTls = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _isSavingEmail
                                  ? null
                                  : _saveEmailSettings,
                              icon: _isSavingEmail
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Save Email Settings'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.smart_toy_outlined,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'AI Servers',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => _openAiServerDialog(),
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Add AI Server',
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Presets for a locally-hosted AI server (Ollama, '
                            'LM Studio, or any OpenAI-compatible endpoint). '
                            'These show up in the dropdown on AI Text nodes.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          if (_aiServers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No AI servers configured yet.'),
                            ),
                          ..._aiServers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final server = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.dns_outlined),
                                title: Text(server.name),
                                subtitle: Text(
                                  '${server.provider == 'ollama' ? 'Ollama' : 'OpenAI-compatible'} '
                                  '\u2022 ${server.baseUrl}'
                                  '${server.model != null && server.model!.isNotEmpty ? ' \u2022 ${server.model}' : ''}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _openAiServerDialog(
                                        existing: server,
                                        index: index,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        setState(() {
                                          _aiServers.removeAt(index);
                                        });
                                        await _saveAiServers();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
