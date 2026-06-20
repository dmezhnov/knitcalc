import 'package:knitcalc/update/impl/remote/remote_versions_source.dart';
import 'package:knitcalc/update/impl/remote/store_versions.dart';

/// A [RemoteVersionsFetcher] that resolves to [entries] — the decoded
/// store-versions document a real fetch would return.
RemoteVersionsFetcher fakeStoreVersions(Map<String, RemoteEntry> entries) =>
    () async => entries;

/// A [RemoteVersionsFetcher] that throws [UpdateCheckException], modelling an
/// offline or blocked fetch (the source could not be reached).
RemoteVersionsFetcher failingStoreVersions() =>
    () async => throw const UpdateCheckException('offline');
