import 'package:flutter/widgets.dart';

/// Holds the app's active [Locale] and notifies listeners when it changes.
class LocaleController extends ValueNotifier<Locale> {
  LocaleController(super.value);
}

/// Exposes a [LocaleController] to the widget tree so any descendant can read
/// the current locale and switch it at runtime.
///
/// Wrap the app above [MaterialApp] and feed [LocaleController.value] into
/// `MaterialApp.locale`. Descendants switch language via
/// `LocaleScope.of(context).value = const Locale('en')`.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'No LocaleScope found in context');
    return scope!.notifier!;
  }
}
