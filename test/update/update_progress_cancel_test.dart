import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/cancel_token.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// A service whose download blocks until the [CancelToken] trips, then throws
/// [UpdateCancelled] — modelling an in-flight APK download the user cancels.
class _CancellableService implements UpdateService {
  bool reachedInstall = false;

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(const DownloadProgress(received: 1, total: 10));
    await cancelToken!.whenCancelled;
    throw const UpdateCancelled();
    // The install handoff after the await is unreachable once cancelled; a flag
    // would be set here in the real service.
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
    CancelToken? cancelToken,
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

    // The progress dialog is up with a Cancel action.
    expect(find.text('Загрузка обновления'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    // Dialog gone, and a cancel is not a failure: no error snackbar.
    expect(find.text('Загрузка обновления'), findsNothing);
    expect(find.text('Не удалось загрузить обновление'), findsNothing);
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
