import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/firebase/auth_service.dart';
import 'package:knitcalc/firebase/auth_session.dart';
import 'package:knitcalc/firebase/firebase_auth_client.dart';
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/firebase/firestore_client.dart';
import 'package:knitcalc/firebase/session_store.dart';
import 'package:knitcalc/home.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/l10n/locale_scope.dart';
import 'package:knitcalc/storage/saved_project.dart';
import 'package:knitcalc/storage/synced_projects_store.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// A remote whose pull fails, modelling a blocked/offline cloud. The first
/// [calls] count lets a retry test see the pull was attempted again.
class FailingRemote implements RemoteProjects {
  int calls = 0;

  @override
  Future<List<SavedProject>> listProjects(String uid) async {
    calls++;
    throw const FirestoreException('offline');
  }

  @override
  Future<void> putProject(String uid, SavedProject project) async {}
}

/// A reachable update source that reports "no update available" without
/// throwing — models web, where the update check reads `version.json` from the
/// page's own origin even while Firestore (cloud sync) is blocked.
class ReachableNoUpdateService implements UpdateService {
  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {}
}

AuthService _signedInAuth() => AuthService(
  client: FirebaseAuthClient(
    config: const FirebaseConfig(projectId: 'p', apiKey: 'K'),
    httpClient: MockClient((_) async => http.Response('{}', 500)),
  ),
  store: PrefsSessionStore(),
);

Widget _wrap(AuthService auth, Widget child) => AuthScope(
  service: auth,
  child: LocaleScope(
    controller: LocaleController(const Locale('ru')),
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  const bannerText =
      'Нет подключения к сети. '
      'Не удалось синхронизировать или проверить обновления.';

  testWidgets('a failed sync shows the retryable network-error banner', (
    tester,
  ) async {
    final session = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'ID',
      refreshToken: 'R',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(session.toJson()),
      // Skip the first-login migration prompt so it doesn't cover the banner.
      'migrated_uid1': true,
    });

    final auth = _signedInAuth();
    await auth.init();

    final remote = FailingRemote();
    await tester.pumpWidget(
      _wrap(
        auth,
        Home(
          storeBuilder: (a) => SyncedProjectsStore(uid: a.uid!, remote: remote),
        ),
      ),
    );

    await _settle(tester);

    expect(find.text(bannerText), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('Retry re-attempts the pull', (tester) async {
    final session = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'ID',
      refreshToken: 'R',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(session.toJson()),
      'migrated_uid1': true,
    });

    final auth = _signedInAuth();
    await auth.init();

    final remote = FailingRemote();
    await tester.pumpWidget(
      _wrap(
        auth,
        Home(
          storeBuilder: (a) => SyncedProjectsStore(uid: a.uid!, remote: remote),
        ),
      ),
    );

    await _settle(tester);
    final attemptsBeforeRetry = remote.calls;

    await tester.tap(find.text('Повторить'));
    await _settle(tester);

    expect(remote.calls, greaterThan(attemptsBeforeRetry));
    // Still failing, so the banner is back.
    expect(find.text(bannerText), findsOneWidget);
  });

  testWidgets('a reachable update source does not clear a blocked-sync banner', (
    tester,
  ) async {
    // Models web: Firestore (sync) is blocked but version.json (the update
    // check) is reachable. The successful update check must not tear down the
    // banner the failed sync raised.
    final session = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'ID',
      refreshToken: 'R',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(session.toJson()),
      'migrated_uid1': true,
    });

    final auth = _signedInAuth();
    await auth.init();

    final remote = FailingRemote();
    await tester.pumpWidget(
      _wrap(
        auth,
        Home(
          storeBuilder: (a) => SyncedProjectsStore(uid: a.uid!, remote: remote),
          updateServiceBuilder: () async => ReachableNoUpdateService(),
        ),
      ),
    );

    await _settle(tester);

    // Sync failed while the update check succeeded — the banner must stay.
    expect(find.text(bannerText), findsOneWidget);

    // And it survives a retry: the pull is re-attempted and still fails, while
    // the update check keeps succeeding, so the banner remains on screen.
    final attemptsBeforeRetry = remote.calls;
    await tester.tap(find.text('Повторить'));
    await _settle(tester);

    expect(remote.calls, greaterThan(attemptsBeforeRetry));
    expect(find.text(bannerText), findsOneWidget);
  });
}
