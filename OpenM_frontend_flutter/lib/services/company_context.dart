import 'package:openm/services/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dtos.dart';

/// Manages the currently selected company for the entire application.
///
/// This provider handles:
/// - Loading available companies from the API
/// - Tracking the currently selected company
/// - Providing company context to all screens
class CurrentCompanyNotifier extends StateNotifier<CompanyDto?> {
  final Ref _ref;

  CurrentCompanyNotifier(this._ref) : super(null) {
    _initializeCompany();
  }

  /// Initialize company from API on first load
  Future<void> _initializeCompany() async {
    try {
      final api = _ref.read(apiClientProvider);
      final companies = await api.companies();

      if (companies.isNotEmpty) {
        state = companies.first;
      }
    } catch (e) {
      // If loading fails, state remains null
      // This is handled gracefully in UI
    }
  }

  /// Set the current company
  void setCompany(CompanyDto company) {
    state = company;
  }

  /// Clear the current company
  void clearCompany() {
    state = null;
  }

  /// Load company by searching in the list
  Future<void> loadCompanyByName(String companyName) async {
    try {
      final api = _ref.read(apiClientProvider);
      final companies = await api.companies(search: companyName);

      if (companies.isNotEmpty) {
        state = companies.first;
      } else {
        state = null;
      }
    } catch (e) {
      state = null;
      rethrow;
    }
  }

  /// Refresh current company data from API
  Future<void> refreshCurrentCompany() async {
    final currentCompany = state;
    if (currentCompany == null) {
      await _initializeCompany();
      return;
    }

    try {
      final api = _ref.read(apiClientProvider);
      // Reload all companies and find the current one
      final companies = await api.companies();
      final updated = companies.firstWhere(
        (c) => c.id == currentCompany.id,
        orElse: () => currentCompany,
      );
      state = updated;
    } catch (e) {
      // On error, keep the current company
      rethrow;
    }
  }
}

/// Provider for the current company
///
/// Usage:
/// ```dart
/// final company = ref.watch(currentCompanyProvider);
/// if (company != null) {
///   // Use company data
/// }
/// ```
final currentCompanyProvider =
    StateNotifierProvider<CurrentCompanyNotifier, CompanyDto?>((ref) {
      return CurrentCompanyNotifier(ref);
    });

/// Async provider to load all companies
///
/// Usage:
/// ```dart
/// final companiesAsync = ref.watch(companiesProvider);
/// companiesAsync.when(
///   data: (companies) => Text('${companies.length} companies'),
///   loading: () => CircularProgressIndicator(),
///   error: (err, stack) => Text('Error loading companies'),
/// );
/// ```
final companiesProvider = FutureProvider<List<CompanyDto>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.companies();
});

/// Helper provider to get the current company ID
///
/// Returns null if no company is selected
/// Usage:
/// ```dart
/// final companyId = ref.watch(currentCompanyIdProvider);
/// ```
final currentCompanyIdProvider = Provider<String?>((ref) {
  final company = ref.watch(currentCompanyProvider);
  return company?.id;
});