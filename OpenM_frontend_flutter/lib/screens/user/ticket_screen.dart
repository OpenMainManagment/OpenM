import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/settings_menu.dart';
import '../../widgets/app_shell.dart';

class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key});

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  bool _loadingDepartments = true;
  bool _sending = false;
  
  @override
  void initState() {
    super.initState();
    // Initialize departments loading
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loadingDepartments = true;
    });
    
    // TODO: Load departments from API using authApiClientProvider
    // final api = ref.read(authApiClientProvider);
    // final departments = await api.getDepartments();
    
    setState(() {
      _loadingDepartments = false;
    });
  }

  Future<void> _openSettings() async {
    await openSettingsMenu(context: context, ref: ref);
  }

  Future<void> _addTicket() async {
    // TODO: Implement add functionality
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      pageName: 'Ticket Screen',
      onAdd: _addTicket,
      onSettings: _openSettings,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Ticket'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ticket Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              if (_loadingDepartments)
                const CircularProgressIndicator()
              else
                // TODO: Add department selection dropdown
                const Text('Departments will be loaded here'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sending ? null : _submitTicket,
                child: _sending 
                  ? const CircularProgressIndicator() 
                  : const Text('Submit Ticket'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitTicket() async {
    if (_nameCtrl.text.isEmpty || _descriptionCtrl.text.isEmpty) {
      // Show error message
      return;
    }
    
    setState(() {
      _sending = true;
    });
    
    try {
      // TODO: Submit ticket to API using authApiClientProvider
      // final api = ref.read(authApiClientProvider);
      // await api.createTicket(
      //   name: _nameCtrl.text,
      //   description: _descriptionCtrl.text,
      // );
      
      // Show success message and navigate back
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket submitted successfully')),
      );
      
      Navigator.of(context).pop();
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting ticket: $e')),
      );
    } finally {
      setState(() {
        _sending = false;
      });
    }
  }
}