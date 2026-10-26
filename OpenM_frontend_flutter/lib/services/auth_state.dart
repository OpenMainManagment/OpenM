import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageAccessToken = 'auth.accessToken.v2';
const _legacyStorageAccessToken = 'auth.accessToken';
const _storageEmployeeName = 'auth.employeeName';
const _storageCompanyId = 'auth.companyId';

class AuthState {
  const AuthState({this.accessToken, this.employeeName, this.companyId});

  final String? accessToken;
  final String? employeeName;
  final String? companyId;

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;

  AuthState copyWith({
    String? accessToken,
    String? employeeName,
    String? companyId,
  }) {
    return AuthState(
      accessToken: accessToken ?? this.accessToken,
      employeeName: employeeName ?? this.employeeName,
      companyId: companyId ?? this.companyId,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyStorageAccessToken);
      final token = prefs.getString(_storageAccessToken);
      if (token == null || token.isEmpty) {
        return;
      }

      state = AuthState(
        accessToken: token,
        employeeName: prefs.getString(_storageEmployeeName),
        companyId: prefs.getString(_storageCompanyId),
      );
    } catch (_) {
      state = const AuthState();
    }
  }

  Future<void> login({
    required String token,
    required String employeeName,
    String? companyId,
  }) async {
    state = AuthState(
      accessToken: token,
      employeeName: employeeName,
      companyId: companyId,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageAccessToken, token);
      await prefs.setString(_storageEmployeeName, employeeName);
      if (companyId != null && companyId.isNotEmpty) {
        await prefs.setString(_storageCompanyId, companyId);
      } else {
        await prefs.remove(_storageCompanyId);
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    state = const AuthState();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageAccessToken);
      await prefs.remove(_storageEmployeeName);
      await prefs.remove(_storageCompanyId);
    } catch (_) {}
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
