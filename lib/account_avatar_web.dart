/// Web account avatar: a real HTML `<img>` element via a platform view.
///
/// Google profile images (`lh3.googleusercontent.com`) fail to load through
/// Flutter's image pipeline on the web — the CanvasKit fetch sends a Referer and
/// Google answers 403, leaving an empty (grey) [CircleAvatar]. A plain `<img>`
/// with `referrerPolicy="no-referrer"` loads fine and needs no CORS to display.
library;

import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Platform-view types already registered, keyed by avatar URL (registering the
/// same type twice throws).
final Set<String> _registered = <String>{};

Widget buildAccountAvatar(String photoUrl, double radius) {
  final viewType = 'account-avatar-${photoUrl.hashCode}';

  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      return web.HTMLImageElement()
        ..src = photoUrl
        ..referrerPolicy = 'no-referrer'
        ..style.setProperty('width', '100%')
        ..style.setProperty('height', '100%')
        ..style.setProperty('object-fit', 'cover')
        // The <img> is a DOM element layered over the Flutter canvas, so it
        // would otherwise swallow taps before they reach the PopupMenuButton
        // underneath — only the ring around the image (plain canvas) opened the
        // menu. Letting pointer events pass through restores tapping the photo.
        ..style.setProperty('pointer-events', 'none');
    });
  }

  return SizedBox(
    width: radius * 2,
    height: radius * 2,
    child: ClipOval(child: HtmlElementView(viewType: viewType)),
  );
}
