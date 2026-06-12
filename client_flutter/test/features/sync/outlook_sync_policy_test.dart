import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutlookSyncPolicy', () {
    test('managed Outlook containers are identifiable by reserved prefixes',
        () {
      final scheduleName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.scheduleBook,
        containerName: 'Work',
      );
      final mirrorName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.taskMirrorBook,
        containerName: 'Inbox',
      );

      expect(
        OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(scheduleName),
        isTrue,
      );
      expect(
        OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(mirrorName),
        isTrue,
      );
      expect(OutlookSyncPolicy.isTaskMirrorCalendarName(mirrorName), isTrue);
      expect(
        OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName('Personal'),
        isFalse,
      );
    });

    test('managed calendar names trim containers without broadening prefixes',
        () {
      final mirrorName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.taskMirrorBook,
        containerName: '  Inbox  ',
      );
      final scheduleName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.scheduleBook,
        containerName: '  Work  ',
      );

      expect(mirrorName, '${OutlookSyncPolicy.taskMirrorBookPrefix}Inbox');
      expect(scheduleName, '${OutlookSyncPolicy.scheduleBookPrefix}Work');
      expect(
        OutlookSyncPolicy.isTaskMirrorCalendarName(' $mirrorName '),
        isTrue,
      );
      expect(OutlookSyncPolicy.isTaskMirrorCalendarName(scheduleName), isFalse);
      expect(
        OutlookSyncPolicy.isFlowPlanV2ManagedCalendarName(
          'Personal ${OutlookSyncPolicy.taskMirrorBookPrefix}Inbox',
        ),
        isFalse,
      );
    });

    test('localCalendarDescription names external and managed boundaries', () {
      final scheduleName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.scheduleBook,
        containerName: 'Work',
      );
      final mirrorName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.taskMirrorBook,
        containerName: 'Inbox',
      );

      expect(
        OutlookSyncPolicy.localCalendarDescription('Personal'),
        contains('\u53ea\u8bfb'),
      );
      expect(
        OutlookSyncPolicy.localCalendarDescription(scheduleName),
        contains('\u53d7\u63a7\u53cc\u5411\u540c\u6b65'),
      );
      expect(
        OutlookSyncPolicy.localCalendarDescription(mirrorName),
        contains('\u4efb\u52a1\u955c\u50cf'),
      );
    });
  });

  group('Outlook auth model boundaries', () {
    test('sync modes round-trip storage aliases and permission flags', () {
      expect(outlookSyncModeFromStorage('disabled'), OutlookSyncMode.paused);
      expect(outlookSyncModeFromStorage('paused'), OutlookSyncMode.paused);
      expect(
          outlookSyncModeFromStorage('import_only'), OutlookSyncMode.readOnly);
      expect(outlookSyncModeFromStorage('read_only'), OutlookSyncMode.readOnly);
      expect(
        outlookSyncModeFromStorage('bidirectional'),
        OutlookSyncMode.bidirectional,
      );
      expect(outlookSyncModeFromStorage('unknown'), OutlookSyncMode.readOnly);

      expect(OutlookSyncMode.paused.allowsPull, isFalse);
      expect(OutlookSyncMode.paused.allowsPush, isFalse);
      expect(OutlookSyncMode.readOnly.allowsPull, isTrue);
      expect(OutlookSyncMode.readOnly.allowsPush, isFalse);
      expect(OutlookSyncMode.bidirectional.allowsPull, isTrue);
      expect(OutlookSyncMode.bidirectional.allowsPush, isTrue);
      expect(OutlookSyncMode.bidirectional.requiresWritePermission, isTrue);
      expect(OutlookSyncMode.readOnly.requiresWritePermission, isFalse);
      for (final mode in OutlookSyncMode.values) {
        expect(mode.storageValue, isNotEmpty);
        expect(mode.label, isNotEmpty);
        expect(mode.description, isNotEmpty);
        expect(mode.syncActionLabel, isNotEmpty);
        expect(mode.authSummary, isNotEmpty);
      }
    });

    test('auth token JSON coerces numbers and checks granted mode boundaries',
        () {
      final token = AuthToken.fromJson({
        'access_token': 'access',
        'refresh_token': 'refresh',
        'expires_in': '7200',
        'expires_at': DateTime.utc(2099).toIso8601String(),
        'granted_mode': OutlookSyncMode.readOnly.storageValue,
        'scope': ' Calendars.Read ',
      });

      expect(token.expiresInSeconds, 7200);
      expect(token.scope, 'Calendars.Read');
      expect(token.isExpired, isFalse);
      expect(token.supportsMode(OutlookSyncMode.paused), isTrue);
      expect(token.supportsMode(OutlookSyncMode.readOnly), isTrue);
      expect(token.supportsMode(OutlookSyncMode.bidirectional), isFalse);

      final bidirectionalToken = AuthToken.fromJson({
        'access_token': 'access',
        'expires_in': 3600.0,
        'expires_at': DateTime.utc(2099).toIso8601String(),
        'granted_mode': OutlookSyncMode.bidirectional.storageValue,
        'scope': 'Calendars.ReadWrite offline_access',
      });
      expect(
        bidirectionalToken.supportsMode(OutlookSyncMode.bidirectional),
        isTrue,
      );
      expect(bidirectionalToken.scope, isNotEmpty);
    });

    test('read-only scope does not support bidirectional writes', () {
      final token = AuthToken.fromJson({
        'access_token': 'access',
        'expires_in': 3600,
        'expires_at': DateTime.utc(2099).toIso8601String(),
        'granted_mode': OutlookSyncMode.bidirectional.storageValue,
        'scope': 'Calendars.Read offline_access',
      });

      expect(token.supportsMode(OutlookSyncMode.readOnly), isTrue);
      expect(token.supportsMode(OutlookSyncMode.bidirectional), isFalse);
    });

    test('auth token response falls back to previous refresh token', () {
      final previous = AuthToken(
        accessToken: 'old',
        refreshToken: 'refresh-old',
        expiresInSeconds: 3600,
        obtainedAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2099),
        grantedMode: OutlookSyncMode.readOnly,
        scope: 'Calendars.Read',
      );

      final token = AuthToken.fromTokenResponse(
        {
          'access_token': 'new',
          'expires_in': '1800',
          'scope': '',
        },
        previousToken: previous,
      );

      expect(token.accessToken, 'new');
      expect(token.refreshToken, 'refresh-old');
      expect(token.expiresInSeconds, 1800);
      expect(token.grantedMode, OutlookSyncMode.readOnly);
      expect(token.scope, isNotEmpty);
    });
  });
}
