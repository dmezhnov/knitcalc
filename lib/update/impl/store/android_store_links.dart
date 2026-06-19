/// Per-store version keys and listing links for the Android stores that ship
/// and install the binary themselves (Samsung, Amazon, Huawei, F-Droid,
/// Accrescent).
///
/// For these channels the app does not download anything: the update banner
/// shows when the remote store-versions document reports a newer version for the
/// store, and the "update" button opens that store's listing so the store can
/// install it. Each store's version is bumped in the document only once it has
/// actually published, so the banner never runs ahead of the store.
///
/// The application id is the same on every platform.
///
/// TODO(update): the deep links/web fallbacks are best-effort placeholders until
/// the listings are live; verify each once published (Huawei AppGallery web URLs
/// in particular key on a numeric app id, not the package name).
library;

import 'package:knitcalc/update/channel.dart';

/// The published application id, shared across stores and platforms.
const String appApplicationId = 'io.github.dmezhnov.knitcalc';

/// Field key for [channel] in the remote store-versions document, or `null`
/// when the channel is not a store-listing channel.
String? storeVersionKey(Channel channel) => switch (channel) {
  Channel.androidSamsung => 'samsung',
  Channel.androidAmazon => 'amazon',
  Channel.androidHuawei => 'huawei',
  Channel.androidFdroid => 'fdroid',
  Channel.androidAccrescent => 'accrescent',
  _ => null,
};

/// Listing links to open for [channel], native deep link first and an https
/// fallback second (tried in order by `launchFirstAvailable`). Empty when the
/// channel has no store listing.
List<Uri> storeListingUrls(Channel channel) {
  switch (channel) {
    case Channel.androidSamsung:
      return [
        Uri.parse('samsungapps://ProductDetail/$appApplicationId'),
        Uri.parse('https://galaxystore.samsung.com/detail/$appApplicationId'),
      ];
    case Channel.androidAmazon:
      return [
        Uri.parse('amzn://apps/android?p=$appApplicationId'),
        Uri.parse(
          'https://www.amazon.com/gp/mas/dl/android?p=$appApplicationId',
        ),
      ];
    case Channel.androidHuawei:
      return [
        Uri.parse('appmarket://details?id=$appApplicationId'),
        Uri.parse('https://appgallery.huawei.com/app/$appApplicationId'),
      ];
    case Channel.androidFdroid:
      return [Uri.parse('https://f-droid.org/packages/$appApplicationId/')];
    case Channel.androidAccrescent:
      return [Uri.parse('https://accrescent.app/app/$appApplicationId')];
    // ignore: no_default_cases
    default:
      return const [];
  }
}
