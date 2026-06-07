/// Pure last-write-wins merge used by cloud sync.
///
/// Local and remote each hold at most one record per project id (a real project
/// or a deletion tombstone). For every id seen on either side the record with
/// the greater [SavedProject.updatedAt] wins; ties go to remote, the shared
/// source of truth. The result also reports which winners the remote is missing
/// or has an older copy of, so the caller knows what to upload.
library;

import 'saved_project.dart';

class MergeResult {
  const MergeResult({required this.merged, required this.toUpload});

  /// The winning record for every id, across both sides (includes tombstones).
  final List<SavedProject> merged;

  /// Winners that came from local and that remote lacks or has older — i.e. the
  /// records the caller should push to the server.
  final List<SavedProject> toUpload;
}

MergeResult mergeForSync(List<SavedProject> local, List<SavedProject> remote) {
  final remoteById = {for (final p in remote) p.id: p};
  final localById = {for (final p in local) p.id: p};

  final merged = <SavedProject>[];
  final toUpload = <SavedProject>[];

  for (final id in {...localById.keys, ...remoteById.keys}) {
    final l = localById[id];
    final r = remoteById[id];

    if (l == null) {
      merged.add(r!);
      continue;
    }
    if (r == null) {
      merged.add(l);
      toUpload.add(l);
      continue;
    }

    // Both sides have it: greater updatedAt wins, ties to remote.
    if (l.updatedAt.isAfter(r.updatedAt)) {
      merged.add(l);
      toUpload.add(l);
    } else {
      merged.add(r);
    }
  }

  return MergeResult(merged: merged, toUpload: toUpload);
}
