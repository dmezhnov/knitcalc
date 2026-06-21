import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/cancel_token.dart';

void main() {
  test('cancel flips isCancelled and completes whenCancelled', () async {
    final token = CancelToken();
    expect(token.isCancelled, isFalse);

    var fired = false;
    final waiter = token.whenCancelled.then((_) => fired = true);

    token.cancel();
    await waiter;

    expect(token.isCancelled, isTrue);
    expect(fired, isTrue);
  });

  test('cancelling twice is a safe no-op', () async {
    final token = CancelToken();
    token.cancel();
    // A second cancel must not throw (StateError on a completed Completer).
    expect(token.cancel, returnsNormally);
    expect(token.isCancelled, isTrue);
  });
}
