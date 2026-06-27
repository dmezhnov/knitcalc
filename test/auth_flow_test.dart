import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/auth_screen.dart';
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
import 'package:knitcalc/storage/projects_repository.dart';
import 'package:knitcalc/storage/saved_project.dart';
import 'package:knitcalc/storage/synced_projects_store.dart';
import 'package:knitcalc/verify_email_screen.dart';

/// In-memory remote so Home's synced store never touches the network.
class FakeRemote implements RemoteProjects {
  final Map<String, SavedProject> docs = {};

  @override
  Future<List<SavedProject>> listProjects(String uid) async =>
      docs.values.toList();

  @override
  Future<void> putProject(String uid, SavedProject project) async =>
      docs[project.id] = project;
}

AuthService authWith(MockClientHandler handler) {
  return AuthService(
    client: FirebaseAuthClient(
      config: const FirebaseConfig(projectId: 'p', apiKey: 'K'),
      httpClient: MockClient(handler),
    ),
    store: PrefsSessionStore(),
  );
}

Widget wrap(AuthService auth, Widget child) {
  return AuthScope(
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AuthScreen shows a localized error on bad credentials', (
    tester,
  ) async {
    final auth = authWith(
      (request) async => http.Response(
        '{"error":{"message":"INVALID_LOGIN_CREDENTIALS"}}',
        400,
      ),
    );

    await tester.pumpWidget(wrap(auth, const AuthScreen()));

    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('auth_password')), 'wrong');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Неверная почта или пароль'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('AuthScreen signs in and pops on success', (tester) async {
    final auth = authWith(
      (request) async => http.Response(
        jsonEncode({
          'localId': 'uid1',
          'email': 'a@b.com',
          'idToken': 'ID',
          'refreshToken': 'R',
          'expiresIn': '3600',
        }),
        200,
      ),
    );

    // Host with a button that pushes AuthScreen, so it has something to pop to.
    await tester.pumpWidget(
      wrap(
        auth,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('auth_password')), 'pw');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      find.byType(AuthScreen),
      findsNothing,
      reason: 'popped after sign-in',
    );
    expect(auth.isSignedIn, isTrue);
  });

  testWidgets('registration requires the two passwords to match', (
    tester,
  ) async {
    final auth = authWith((request) async => http.Response('{}', 200));

    await tester.pumpWidget(wrap(auth, const AuthScreen()));

    // Switch to registration; a confirm-password field appears.
    await tester.tap(find.text('Нет аккаунта? Зарегистрироваться'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth_password_confirm')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('auth_password')), 'pw123456');
    await tester.enterText(
      find.byKey(const Key('auth_password_confirm')),
      'different',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('registration signs in unverified and needs verification', (
    tester,
  ) async {
    final auth = authWith((request) async {
      if (request.url.path.endsWith('accounts:signUp')) {
        return http.Response(
          jsonEncode({
            'localId': 'uid1',
            'email': 'a@b.com',
            'idToken': 'ID',
            'refreshToken': 'R',
            'expiresIn': '3600',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    // Host so the screen has somewhere to pop to.
    await tester.pumpWidget(
      wrap(
        auth,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Нет аккаунта? Зарегистрироваться'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('auth_password')), 'pw123456');
    await tester.enterText(
      find.byKey(const Key('auth_password_confirm')),
      'pw123456',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      find.byType(AuthScreen),
      findsNothing,
      reason: 'popped after sign-up',
    );
    expect(auth.isSignedIn, isTrue);
    expect(auth.needsVerification, isTrue);
  });

  testWidgets('unverified account is gated until the email is verified', (
    tester,
  ) async {
    var verified = false;
    final session = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'ID',
      refreshToken: 'R',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(session.toJson()),
    });

    final auth = authWith((request) async {
      if (request.url.path.endsWith('accounts:lookup')) {
        return http.Response(
          jsonEncode({
            'users': [
              {'emailVerified': verified},
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    await auth.init();
    expect(auth.needsVerification, isTrue);

    // Root mirrors main.dart: gate while unverified, otherwise the app.
    await tester.pumpWidget(
      wrap(
        auth,
        Builder(
          builder: (context) => AuthScope.of(context).needsVerification
              ? const VerifyEmailScreen()
              : const Scaffold(body: Text('app')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.text('app'), findsNothing);

    // The link gets clicked elsewhere; tapping "I've verified" re-checks.
    verified = true;
    await tester.tap(find.text('Я подтвердил(а)'));
    await tester.pumpAndSettle();

    expect(find.text('app'), findsOneWidget, reason: 'gate cleared');
    expect(auth.needsVerification, isFalse);
  });

  testWidgets('forgot password sends a reset email', (tester) async {
    final auth = authWith((request) async => http.Response('{}', 200));

    await tester.pumpWidget(wrap(auth, const AuthScreen()));

    await tester.enterText(find.byKey(const Key('auth_email')), 'a@b.com');
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reset_email')), findsOneWidget);
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();

    expect(find.text('Письмо для сброса пароля отправлено'), findsOneWidget);
  });

  testWidgets('first sign-in offers to upload local projects', (tester) async {
    final guest = SavedProject.create(
      name: 'Локальный шарф',
      productId: 'rectangular_scarf',
      values: const {'stitches': '10'},
    );
    final session = AuthSession(
      uid: 'uid1',
      email: 'a@b.com',
      idToken: 'ID',
      refreshToken: 'R',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'auth_session': jsonEncode(session.toJson()),
      'saved_projects': jsonEncode([guest.toJson()]),
    });

    final auth = authWith((request) async => http.Response('{}', 500));
    await auth.init();
    expect(auth.isSignedIn, isTrue);

    final remote = FakeRemote();
    await tester.pumpWidget(
      wrap(
        auth,
        Home(
          storeBuilder: (a) => SyncedProjectsStore(uid: a.uid!, remote: remote),
        ),
      ),
    );

    // The first-load spinner animates indefinitely, so pump fixed frames rather
    // than pumpAndSettle while the migration dialog is up over it.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();

    // Migration prompt is shown; choose to upload.
    expect(find.text('Перенести изделия в аккаунт?'), findsOneWidget);
    await tester.tap(find.text('Загрузить'));
    await settle();

    // The local project is now on the remote and visible in the list.
    expect(remote.docs.values.map((p) => p.name), contains('Локальный шарф'));
    expect(find.text('Локальный шарф'), findsOneWidget);

    // Guest store was cleared so it is not offered again.
    expect(await const ProjectsRepository().loadAll(), isEmpty);
  });
}
