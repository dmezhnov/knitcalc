/// Web account avatar: a real HTML `<img>` element via a platform view.
///
/// Google profile images (`lh3.googleusercontent.com`) fail to load through
/// Flutter's image pipeline on the web — the CanvasKit fetch sends a Referer and
/// Google answers 403, leaving an empty (grey) [CircleAvatar]. A plain `<img>`
/// with `referrerPolicy="no-referrer"` loads fine and needs no CORS to display.
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Platform-view types already registered, keyed by avatar URL (registering the
/// same type twice throws).
final Set<String> _registered = <String>{};

/// Latest tap handler per avatar view type. The platform-view factory is
/// registered once per URL and cached, but the same avatar is shown on more than
/// one screen (each with its own menu button). Reading the handler from here —
/// refreshed on every build — means a tap opens the menu of the screen that is
/// currently on top, not whichever one happened to register the factory first.
final Map<String, VoidCallback> _onTaps = <String, VoidCallback>{};

Widget buildAccountAvatar(
  String photoUrl,
  double radius, {
  VoidCallback? onTap,
}) {
  final viewType = 'account-avatar-${photoUrl.hashCode}';

  if (onTap != null) {
    _onTaps[viewType] = onTap;
  }

  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = web.HTMLImageElement()
        ..src = photoUrl
        ..referrerPolicy = 'no-referrer'
        ..style.setProperty('width', '100%')
        ..style.setProperty('height', '100%')
        ..style.setProperty('object-fit', 'cover')
        ..style.setProperty('cursor', 'pointer');
      // The engine wraps this <img> in a <flt-platform-view> whose slot is given
      // `pointer-events: auto`, so the platform view — not the PopupMenuButton's
      // InkWell beneath it — receives the tap. (Setting `pointer-events: none` on
      // the <img> didn't help: the wrapper still captured the tap.) Rather than
      // fight the engine, let the image handle its own click in the DOM and
      // forward it to the current [onTap], which opens the account menu.
      img.addEventListener(
        'click',
        ((web.Event _) => _onTaps[viewType]?.call()).toJS,
      );
      return img;
    });
  }

  return SizedBox(
    width: radius * 2,
    height: radius * 2,
    child: ClipOval(child: HtmlElementView(viewType: viewType)),
  );
}
