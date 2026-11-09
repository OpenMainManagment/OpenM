import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openm/models/dtos.dart';
import 'package:openm/screens/user/offer_for_customer_screen.dart';
import 'package:openm/services/api_client.dart';

void main() {
  testWidgets('lists project offer PDFs by name, newest first', (tester) async {
    final api = _OfferListApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: OfferForCustomerScreen(
            projectId: 'project-1',
            projectName: 'Sample project',
            documentId: 'offer-new',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offer PDFs'), findsOneWidget);
    expect(find.text('Angebot_neu.pdf'), findsOneWidget);
    expect(find.text('Angebot_alt.pdf'), findsOneWidget);
    expect(find.text('Notiz.txt'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Angebot_neu.pdf')).dy,
      lessThan(tester.getTopLeft(find.text('Angebot_alt.pdf')).dy),
    );
  });
}

class _OfferListApiClient extends ApiClient {
  _OfferListApiClient() : super(Dio());

  @override
  Future<List<ProjectOfferRecipientDto>> projectOfferRecipients(
    String projectId,
  ) async => const [];

  @override
  Future<List<FolderDto>> folders(
    String projectId, {
    String? parentFolderId,
    String? search,
    bool includeAll = false,
  }) async => const [FolderDto(id: 'offers', name: 'Angebote')];

  @override
  Future<List<DocumentDto>> folderFiles(
    String folderId, {
    String? search,
  }) async => [
    DocumentDto(
      id: 'offer-old',
      fileName: 'Angebot_alt.pdf',
      mimeType: 'application/pdf',
      createdAt: DateTime(2026, 1, 1),
    ),
    DocumentDto(
      id: 'note',
      fileName: 'Notiz.txt',
      mimeType: 'text/plain',
      createdAt: DateTime(2026, 2, 1),
    ),
    DocumentDto(
      id: 'offer-new',
      fileName: 'Angebot_neu.pdf',
      mimeType: 'application/pdf',
      createdAt: DateTime(2026, 3, 1),
    ),
  ];
}
