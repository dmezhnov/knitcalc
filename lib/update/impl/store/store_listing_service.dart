import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';
import 'package:knitcalc/update/impl/store/android_store_links.dart';
import 'package:knitcalc/update/impl/store/store_launch.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';

/// Returns the listing-based update service for a store [channel] (Samsung,
/// Amazon, Huawei, F-Droid, Accrescent).
UpdateService createStoreListingService(Channel channel, AppVersion? current) =>
    StoreListingUpdateService(channel: channel, current: current);

/// Update service for stores that ship and install the binary themselves.
///
/// Reads the version the store has published from the remote store-versions
/// document (so it never announces a release the store has not approved yet)
/// and, on update, opens the store listing — the store installs the actual
/// binary. The app downloads nothing here.
class StoreListingUpdateService implements UpdateService {
  StoreListingUpdateService({
    required Channel channel,
    required AppVersion? current,
    RemoteVersionsFetcher? fetch,
    UrlLauncher? launchUrl,
  }) : _versionKey = storeVersionKey(channel),
       _urls = storeListingUrls(channel),
       _current = current,
       _fetch = fetch ?? fetchStoreVersions,
       _launch = launchUrl ?? launchExternal;

  final String? _versionKey;
  final List<Uri> _urls;
  final AppVersion? _current;
  final RemoteVersionsFetcher _fetch;
  final UrlLauncher _launch;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final key = _versionKey;

    if (key == null) {
      return null;
    }

    final versions = await _fetch();

    return evaluateRemoteUpdate(
      _current,
      versions?[key],
      action: UpdateAction.openUrl,
      url: _urls.isNotEmpty ? _urls.first.toString() : null,
    );
  }

  @override
  Future<void> startUpdate(
    UpdateInfo info, {
    UpdateProgressCallback? onProgress,
  }) async {
    final urls = _urls.isNotEmpty
        ? _urls
        : [if (info.url != null) Uri.parse(info.url!)];

    if (!await launchFirstAvailable(urls, _launch)) {
      throw StateError('Could not open the store listing: $urls');
    }
  }
}
