// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openm/main.dart';
import 'package:openm/services/api_client.dart';
import 'package:openm/services/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App shows first-run admin setup when no users exist', (
    WidgetTester tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'setup_required': true,
                'legacy_admin_password_reset': false,
                'organization_name': null,
              },
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWith((ref) => ApiClient(dio))],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your administrator account'), findsOneWidget);
    expect(find.text('Administrator password'), findsOneWidget);
  });

  testWidgets('Empty database opens setup despite a saved session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth.accessToken.v2': 'stale-token',
      'auth.employeeName': 'old-user',
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'setup_required': true,
                'legacy_admin_password_reset': false,
                'organization_name': null,
              },
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWith((ref) => ApiClient(dio))],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your administrator account'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.accessToken.v2'), isNull);
  });

  testWidgets('Initialized database opens login without a saved session', (
    tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'setup_required': false,
              'legacy_admin_password_reset': false,
              'organization_name': null,
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWith((ref) => ApiClient(dio))],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Create your administrator account'), findsNothing);
  });

  test('Completed setup retains a restored session', () async {
    SharedPreferences.setMockInitialValues({
      'auth.accessToken.v2': 'valid-token',
      'auth.employeeName': 'admin',
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'setup_required': false,
              'legacy_admin_password_reset': false,
              'organization_name': null,
            },
          ),
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => ApiClient(dio))],
    );
    addTearDown(container.dispose);

    await container.read(startupSessionCheckProvider.future);
    expect(container.read(authStateProvider).accessToken, 'valid-token');
  });

  testWidgets('Failed setup status check can be retried', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.accessToken.v2': 'stale-token',
    });
    var available = false;
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!available) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'setup_required': true,
                'legacy_admin_password_reset': false,
                'organization_name': null,
              },
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWith((ref) => ApiClient(dio))],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Create your administrator account'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.accessToken.v2'), 'stale-token');

    available = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Create your administrator account'), findsOneWidget);
    expect(prefs.getString('auth.accessToken.v2'), isNull);
  });
}
