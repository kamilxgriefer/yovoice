import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_audit_timeline.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';

void main() {
  Widget polishHost(Widget child) => MaterialApp(
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );

  test('every report reason has deliberate Polish copy', () {
    const copy = AppLocalizations(Locale('pl'));

    expect(
      ReportReason.values.map(
        (reason) => reportReasonLabel(reason, copy: copy),
      ),
      [
        'Spam lub oszustwo',
        'Nękanie lub zastraszanie',
        'Mowa nienawiści',
        'Treści seksualne',
        'Przemoc lub groźby',
        'Samookaleczenie',
        'Podszywanie się pod inną osobę',
        'Inny powód',
      ],
    );
  });

  testWidgets('the reason picker localizes labels and sheet semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      polishHost(
        const ReportReasonSheet(
          title: 'Zgłoś treść',
          subtitle: 'Wybierz powód zgłoszenia.',
        ),
      ),
    );

    expect(find.text('Nękanie lub zastraszanie'), findsOneWidget);
    expect(find.text('Podszywanie się pod inną osobę'), findsOneWidget);
    expect(find.bySemanticsLabel('powód zgłoszenia'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a Polish reporting failure stays specific and actionable', (
    tester,
  ) async {
    await tester.pumpWidget(
      polishHost(
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => reportContent(
                context: context,
                content: const ReportedContent.directMessage(
                  conversationId: 'conversation',
                  messageId: 'message',
                ),
                title: 'Zgłoś wiadomość',
                subtitle: 'Wybierz powód zgłoszenia.',
                service: _FailingContentReportService(),
              ),
              child: const Text('Zgłoś'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Zgłoś'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam lub oszustwo'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ta wiadomość została już przez Ciebie zgłoszona. '
        'Nasz zespół nadal ma to zgłoszenie.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('already reported'), findsNothing);
  });

  testWidgets('the Polish Moderation Center localizes its full empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      polishHost(
        ModerationCenterScreen(
          embedded: true,
          moderationService: _PolishModerationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Otwarte'), findsWidgets);
    expect(find.text('W trakcie weryfikacji'), findsWidgets);
    expect(find.text('Szukaj we wczytanych zgłoszeniach…'), findsOneWidget);
    expect(find.text('Filtry'), findsOneWidget);
    expect(find.text('Brak zgłoszeń'), findsOneWidget);
    expect(
      find.text('Nowe zgłoszenia społeczności pojawią się tutaj.'),
      findsOneWidget,
    );
  });

  testWidgets('the Reel queue filter has deliberate Polish copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      polishHost(
        ModerationCenterScreen(
          embedded: true,
          moderationService: _PolishModerationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filtry'));
    await tester.pumpAndSettle();

    expect(find.text('Rolka'), findsOneWidget);
    expect(find.text('Reel'), findsNothing);
  });

  testWidgets('the audit trail localizes actions, states and accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final service = _PolishModerationService(
      auditPage: ModerationAuditPage(
        events: [
          ModerationAuditEvent(
            id: 'event',
            kind: ModerationAuditKind.reportWorkflow,
            action: 'report_claim',
            actorId: 'moderator',
            actorName: 'Anna',
            actorRole: 'moderator',
            previousStatus: 'open',
            newStatus: 'inReview',
            resolution: null,
            note: null,
            contentRemoved: false,
            removedContent: null,
            createdAt: DateTime(2026, 9),
          ),
        ],
        hasMore: false,
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(
      polishHost(
        SingleChildScrollView(
          child: ReportAuditTimeline(
            reportId: 'report',
            service: service,
            onAccessExpired: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Historia moderacji'), findsOneWidget);
    expect(find.text('Przejęto do weryfikacji'), findsOneWidget);
    expect(find.text('Otwarte › W trakcie weryfikacji'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Przejęto do weryfikacji, moderator: Anna'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}

class _FailingContentReportService extends ContentReportService {
  @override
  Future<void> report({
    required ReportedContent content,
    required ReportReason reason,
  }) async {
    throw ContentReportException(
      ContentReportFailure.alreadyReported,
      noun: content.noun,
    );
  }
}

class _PolishModerationService extends ModerationService {
  _PolishModerationService({this.auditPage = ModerationAuditPage.empty})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'moderator'),
        ),
      );

  final ModerationAuditPage auditPage;

  @override
  Future<bool> isActiveStaff() async => true;

  @override
  Future<String> currentRole() async => 'moderator';

  @override
  Future<int?> countByStatus(ReportStatus status) async => 0;

  @override
  Stream<List<ModerationReport>> watchQueue({
    ReportStatus status = ReportStatus.open,
    ReportTargetType? targetType,
    ReportReason? reason,
    int limit = ModerationService.pageSize,
  }) => Stream.value(const []);

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) async => auditPage;
}
