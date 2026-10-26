import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/actions/settings_menu.dart';
import '../../models/dtos.dart';
import '../../services/api_client.dart';
import '../../widgets/app_shell.dart';

class AdminPartsScreen extends ConsumerStatefulWidget {
  const AdminPartsScreen({super.key});

  @override
  ConsumerState<AdminPartsScreen> createState() => _AdminPartsScreenState();
}

class _AdminPartsScreenState extends ConsumerState<AdminPartsScreen> {
  final _searchCtrl = TextEditingController();
  List<PartDto> _parts = const [];
  bool _loading = true;
  bool _resetting = false;

  static const List<String> _rootOrder = ['Main Components', 'Sub Components'];

  Future<void> _confirmDeletePart(PartDto part) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Part'),
        content: Text('Delete ${part.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiClientProvider).deletePart(part.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
              await _load();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final parts = await ref
        .read(apiClientProvider)
        .parts(
          includeAll: true,
          search: _searchCtrl.text.trim().isEmpty
              ? null
              : _searchCtrl.text.trim(),
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _parts = parts;
      _loading = false;
    });
  }

  Future<void> _goToAddPartPage() async {
    final created = await context.push<bool>('/admin/parts/new');
    if (created == true) {
      await _load();
    }
  }

  Future<void> _goToEditPartPage(PartDto part) async {
    final updated = await context.push<bool>('/admin/parts/${part.id}/edit');
    if (updated == true) {
      await _load();
    }
  }

  Future<void> _confirmResetFromStructure() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Parts From Structure'),
        content: const Text(
          'This deletes ALL existing parts and rebuilds a fresh structure:\n\n'
          '- Main Components\n'
          '- Sub Components\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: _resetting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _resetting
                ? null
                : () async {
                    setState(() {
                      _resetting = true;
                    });
                    try {
                      await ref
                          .read(apiClientProvider)
                          .resetPartsFromStructure();
                      if (!mounted) {
                        return;
                      }
                      Navigator.pop(context);
                      await _load();
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Parts catalog rebuilt from structure.',
                          ),
                        ),
                      );
                    } finally {
                      if (mounted) {
                        setState(() {
                          _resetting = false;
                        });
                      }
                    }
                  },
            child: Text(_resetting ? 'Rebuilding...' : 'Delete + Rebuild'),
          ),
        ],
      ),
    );
  }

  Widget _buildPartTile(PartDto part, {double indent = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.precision_manufacturing_outlined),
          title: Text(part.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${part.idNumber ?? '-'}'),
              Text(
                'Role: ${part.partRole == 'main' ? 'Main Part' : 'Sub Part'}',
              ),
              Text(
                'Buy: ${part.buyPrice.toStringAsFixed(2)} | Sell: ${part.sellPrice.toStringAsFixed(2)}',
              ),
              Text('Category: ${part.categoryName ?? '-'}'),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _goToEditPartPage(part);
              } else if (value == 'delete') {
                _confirmDeletePart(part);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartTreeNode(
    PartDto part,
    Map<String?, List<PartDto>> byParent,
    double indent,
  ) {
    final children = (byParent[part.id] ?? const <PartDto>[]).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPartTile(part, indent: indent),
        for (final child in children)
          _buildPartTreeNode(child, byParent, indent + 18),
      ],
    );
  }

  Widget _buildStructureSection({
    required String title,
    required IconData icon,
    required PartDto? root,
    required Map<String?, List<PartDto>> byParent,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (root == null)
              const Text('Section not created yet. Use Delete + Rebuild.')
            else
              _buildPartTreeNode(root, byParent, 0),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecificationSummary() {
    const partFields = [
      'Unique ID',
      'Part Number',
      'Name',
      'Description',
      'Preview Image',
      'Part Source',
      'Purchase Price',
      'Sales Price',
      'Status',
      'Notes',
    ];
    const fileActions = [
      'Upload / Drag & Drop / Download / Open',
      'Replace / Delete / Search / Filter',
      'Rename display name / Description',
      'Version history support',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Part Management Blueprint',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Required part information:'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: partFields
                  .map((item) => Chip(label: Text(item)))
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
            const Text('File management capabilities:'),
            const SizedBox(height: 6),
            ...fileActions.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('- $item'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    openSettingsMenu(context: context, ref: ref);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Admin Parts',
      onAdd: _goToAddPartPage,
      onSettings: () => _openSettings(context, ref),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Parts Catalog: ${_parts.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _loading || _resetting
                    ? null
                    : _confirmResetFromStructure,
                icon: const Icon(Icons.restart_alt_outlined),
                label: Text(
                  _resetting
                      ? 'Rebuilding catalog...'
                      : 'Delete All + Rebuild From Structure',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search parts',
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _parts.isEmpty
                  ? const Center(
                      child: Text('No parts found. Add your first part.'),
                    )
                  : Builder(
                      builder: (context) {
                        final byParent = <String?, List<PartDto>>{};
                        for (final part in _parts) {
                          byParent
                              .putIfAbsent(part.parentPartId, () => [])
                              .add(part);
                        }

                        if (_searchCtrl.text.trim().isNotEmpty) {
                          final searched = _parts.toList()
                            ..sort(
                              (a, b) => a.name.toLowerCase().compareTo(
                                b.name.toLowerCase(),
                              ),
                            );
                          return ListView(
                            children: searched
                                .map((part) => _buildPartTile(part))
                                .toList(growable: false),
                          );
                        }

                        final roots = (byParent[null] ?? const <PartDto>[])
                            .toList();
                        PartDto? rootByName(String name) {
                          for (final part in roots) {
                            if (part.name.trim().toLowerCase() ==
                                name.trim().toLowerCase()) {
                              return part;
                            }
                          }
                          return null;
                        }

                        final consumedIds = <String>{};
                        final sections = <Widget>[
                          _buildSpecificationSummary(),
                          _buildStructureSection(
                            title: _rootOrder[0],
                            icon: Icons.inventory_2_outlined,
                            root: rootByName(_rootOrder[0]),
                            byParent: byParent,
                          ),
                          _buildStructureSection(
                            title: _rootOrder[1],
                            icon: Icons.memory_outlined,
                            root: rootByName(_rootOrder[1]),
                            byParent: byParent,
                          ),
                        ];

                        for (final title in _rootOrder) {
                          final root = rootByName(title);
                          if (root != null) {
                            consumedIds.add(root.id);
                          }
                        }

                        final otherRoots =
                            roots
                                .where((r) => !consumedIds.contains(r.id))
                                .toList()
                              ..sort(
                                (a, b) => a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                ),
                              );
                        if (otherRoots.isNotEmpty) {
                          sections.add(
                            Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Other Root Parts',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (final root in otherRoots)
                                      _buildPartTreeNode(root, byParent, 0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView(children: sections);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
