/// Exposes the app's [AuthService] to the widget tree so any screen can read the
/// current sign-in state and react when it changes.
///
/// Wrap it above [MaterialApp]; descendants read it with `AuthScope.of(context)`
/// and rebuild automatically when the session changes (sign in / out / refresh).
library;

import 'package:flutter/widgets.dart';

import 'auth_service.dart';

class AuthScope extends InheritedNotifier<AuthService> {
  const AuthScope({
    super.key,
    required AuthService service,
    required super.child,
  }) : super(notifier: service);

  static AuthService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in context');

    return scope!.notifier!;
  }
}
