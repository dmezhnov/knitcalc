import 'package:flutter_test/flutter_test.dart';

import 'package:knitcalc/firebase/google_oauth.dart';
import 'package:knitcalc/firebase/native_google_sign_in.dart';

/// A loopback flow stand-in that records how it was driven.
class _FakeFlow implements GoogleSignInFlow {
  int obtained = 0;
  int cancels = 0;

  @override
  GoogleOAuthConfig get config => const GoogleOAuthConfig(
    clientId: 'C',
    redirectUri: 'http://localhost:8421',
    callbackUrlScheme: 'http://localhost:8421',
  );

  @override
  Future<String> obtainIdToken() async {
    obtained++;
    return 'FALLBACK';
  }

  @override
  void cancel() => cancels++;
}

void main() {
  NativeFirstGoogleSignInFlow flow(
    _FakeFlow fallback, {
    required NativeIdTokenFetcher fetchNative,
  }) => NativeFirstGoogleSignInFlow(
    serverClientId: 'srv',
    fallback: fallback,
    fetchNative: fetchNative,
  );

  test('returns the native id token without touching the fallback', () async {
    final fb = _FakeFlow();
    final f = flow(fb, fetchNative: (_) async => 'NATIVE');

    expect(await f.obtainIdToken(), 'NATIVE');
    expect(fb.obtained, 0);
  });

  test('passes the server client id through to the fetcher', () async {
    final fb = _FakeFlow();
    String? seen;
    final f = flow(
      fb,
      fetchNative: (id) async {
        seen = id;
        return 'NATIVE';
      },
    );

    await f.obtainIdToken();

    expect(seen, 'srv');
  });

  test('falls back to the browser flow when native is unavailable', () async {
    final fb = _FakeFlow();
    final f = flow(
      fb,
      fetchNative: (_) async => throw const NativeSignInUnavailable('no play'),
    );

    expect(await f.obtainIdToken(), 'FALLBACK');
    expect(fb.obtained, 1);
  });

  test('a native cancel is surfaced, not fallen back', () async {
    final fb = _FakeFlow();
    final f = flow(
      fb,
      fetchNative: (_) async => throw const GoogleAuthCancelledException(),
    );

    await expectLater(
      f.obtainIdToken(),
      throwsA(isA<GoogleAuthCancelledException>()),
    );
    expect(fb.obtained, 0);
  });

  test('cancel forwards to the fallback only once it is engaged', () async {
    final fb = _FakeFlow();
    final f = flow(
      fb,
      fetchNative: (_) async => throw const NativeSignInUnavailable('no play'),
    );

    // Before the fallback runs, cancel must not pre-complete its abort signal.
    f.cancel();
    expect(fb.cancels, 0);

    await f.obtainIdToken();
    f.cancel();
    expect(fb.cancels, 1);
  });

  test('config mirrors the fallback so requestUri stays consistent', () {
    final fb = _FakeFlow();
    final f = flow(fb, fetchNative: (_) async => 'NATIVE');

    expect(f.config.redirectUri, fb.config.redirectUri);
  });
}
