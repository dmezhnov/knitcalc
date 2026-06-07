/// Default account-avatar rendering (desktop/mobile): a [CircleAvatar] backed by
/// the network image, falling back to its background colour if it fails to load.
library;

import 'package:flutter/material.dart';

Widget buildAccountAvatar(String photoUrl, double radius) {
  return CircleAvatar(
    radius: radius,
    backgroundImage: NetworkImage(photoUrl),
    // Fall back to the plain colour if the avatar fails to load.
    onBackgroundImageError: (_, _) {},
  );
}
