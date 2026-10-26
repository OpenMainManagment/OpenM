import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/current_project_state.dart';

class _ChatEntry {
  const _ChatEntry({required this.text, required this.fromUser, this.isError = false});

  final String text;
  final bool fromUser;
  final bool isError;
}

/// Small floating "+" button pinned to the bottom-left of the app that
/// opens a chat overlay panel for talking to the local AI assistant.
class ChatOverlay extends ConsumerStatefulWidget {
  const ChatOverlay({super.key});

  @override
  ConsumerState<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends ConsumerState<ChatOverlay> {
  bool _open = false;
  bool _sending = false;
  final List<_ChatEntry> _messages = [];
  final TextEditingController _controller = TextEditingController();
  PlatformFile? _attachedFile;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) {
      return;
    }
    setState(() {
      _attachedFile = result.files.single;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFile == null) {
      return;
    }

    final displayText = _attachedFile == null
        ? text
        : '$text${text.isEmpty ? '' : '\n'}📎 ${_attachedFile!.name}';

    setState(() {
      _messages.add(_ChatEntry(text: displayText, fromUser: true));
      _sending = true;
    });
    _controller.clear();
    final attached = _attachedFile;
    setState(() => _attachedFile = null);

    final projectId = ref.read(currentProjectIdProvider);
    final api = ref.read(apiClientProvider);

    try {
      String? projectContext;
      if (projectId != null) {
        try {
          projectContext = await api.projectAiContext(projectId);
        } catch (_) {
          // Best-effort: still send the message without project context.
        }
      }

      final reply = await api.sendChatMessage(
            message: text,
            fileBytes: attached?.bytes,
            fileName: attached?.name,
            projectId: projectId,
            projectContext: projectContext,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatEntry(text: reply.response, fromUser: false, isError: reply.isError),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatEntry(
            text: 'Could not reach the AI assistant: $error',
            fromUser: false,
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // fit: expand is required — this Stack has only Positioned children, so
    // without it the Stack collapses to zero size and Positioned offsets
    // (and hit-testing) become unreliable when nested inside the app-wide
    // overlay Stack in main.dart.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_open)
          Positioned(
            left: 16,
            bottom: 76,
            child: _ChatPanel(
              messages: _messages,
              controller: _controller,
              sending: _sending,
              attachedFileName: _attachedFile?.name,
              onPickFile: _pickFile,
              onClearAttachment: () => setState(() => _attachedFile = null),
              onSend: _send,
              onClose: () => setState(() => _open = false),
            ),
          ),
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'chat_overlay_fab',
            onPressed: () => setState(() => _open = !_open),
            child: Icon(_open ? Icons.close : Icons.chat_bubble_outline),
          ),
        ),
      ],
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.sending,
    required this.attachedFileName,
    required this.onPickFile,
    required this.onClearAttachment,
    required this.onSend,
    required this.onClose,
  });

  final List<_ChatEntry> messages;
  final TextEditingController controller;
  final bool sending;
  final String? attachedFileName;
  final VoidCallback onPickFile;
  final VoidCallback onClearAttachment;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 340,
        height: 440,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('AI Assistant', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
            const Divider(height: 12),
            Expanded(
              child: messages.isEmpty
                  ? const Center(
                      child: Text('Ask me anything about your projects.'),
                    )
                  : ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final entry = messages[index];
                        return Align(
                          alignment: entry.fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(maxWidth: 260),
                            decoration: BoxDecoration(
                              color: entry.isError
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : entry.fromUser
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry.isError) ...[
                                  Icon(
                                    Icons.error_outline,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(child: Text(entry.text)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (attachedFileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        attachedFileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: onClearAttachment,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: sending ? null : onPickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !sending,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                IconButton(
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: sending ? null : onSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
