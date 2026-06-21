import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/download_control.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// A service whose download blocks until the [DownloadControl] is cancelled,
/// then throws [UpdateCancelled] — modelling an in-flight APK download the user
/// pauses/resumes and finally cancels.
class _CancellableService implements UpdateService {
  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {
    onProgress?.call(const DownloadProgress(received: 1, total: 10));
    await control!.whenCancelled;
    throw const UpdateCancelled();
  }
}

/// A service whose download fails outright (a real error, not a cancel).
class _FailingService implements UpdateService {
  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    DownloadControl? control,
  }) async {
    throw Exception('download failed');
  }
}

void main() {
  final info = UpdateInfo(
    latestVersion: const AppVersion(1, 9, 0, 70),
    versionLabel: '1.9.0+70',
    action: UpdateAction.inApp,
  );

  Widget host(UpdateService service) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => runUpdateWithProgress(context, service, info),
          child: const Text('go'),
        ),
      ),
    ),
  );

  testWidgets('Cancel dismisses the dialog without an error snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(host(_CancellableService()));

    await tester.tap(find.text('go'));
    await tester.pump(); // show dialog
    await tester.pump(const Duration(milliseconds: 50));

    // The progress dialog is up with Pause and Cancel actions.
    expect(find.text('Загрузка обновления'), findsOneWidget);
    expect(find.text('Пауза'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    // Dialog gone, and a cancel is not a failure: no error snackbar.
    expect(find.text('Загрузка обновления'), findsNothing);
    expect(find.text('Не удалось загрузить обновление'), findsNothing);
  });

  testWidgets('Pause swaps the button to Resume and shows the paused status', (
    tester,
  ) async {
    await tester.pumpWidget(host(_CancellableService()));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Пауза'), findsOneWidget);

    await tester.tap(find.text('Пауза'));
    await tester.pump();

    // Now paused: the action becomes Resume and the status reads "Приостановлено".
    expect(find.text('Продолжить'), findsOneWidget);
    expect(find.text('Пауза'), findsNothing);
    expect(find.text('Приостановлено'), findsOneWidget);

    // Resume flips it back.
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(find.text('Пауза'), findsOneWidget);
    expect(find.text('Приостановлено'), findsNothing);

    // Clean up the still-running download.
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });

  testWidgets('a real download failure still shows the error snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(host(_FailingService()));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить обновление'), findsOneWidget);
  });
}
