/// Default account-avatar rendering (desktop/mobile): a [CircleAvatar] backed by
/// the network image, falling back to its background colour if it fails to load.
library;

import 'package:flutter/material.dart';

/// [onTap] is accepted for parity with the web implementation but ignored here:
/// off the web the avatar renders on the Flutter canvas, so the enclosing
/// [PopupMenuButton] receives taps natively — nothing intercepts them.
Widget buildAccountAvatar(
  String photoUrl,
  double radius, {
  VoidCallback? onTap,
}) {
  return CircleAvatar(
    radius: radius,
    backgroundImage: NetworkImage(photoUrl),
    // Fall back to the plain colour if the avatar fails to load.
    onBackgroundImageError: (_, _) {},
  );
}
