/// A [ProjectsStore] that mirrors the signed-in user's projects between a local
/// cache and Firestore.
///
/// The local cache (one JSON array under a per-user key) is the offline-first
/// source the UI reads instantly; it holds tombstones too. Edits write the cache
/// and best-effort push to Firestore — if the push fails (offline) the change is
/// still saved locally and uploaded on the next [sync]. [sync] pulls the remote,
/// merges per-id last-write-wins (see [mergeForSync]), saves the merge, and
/// uploads anything the server is missing or has older.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/firestore_client.dart';
import 'project_merge.dart';
import 'projects_store.dart';
import 'saved_project.dart';

class SyncedProjectsStore implements ProjectsStore {
  SyncedProjectsStore({required this.uid, required this.remote});

  final String uid;
  final RemoteProjects remote;

  /// Per-user so signing into a different account on the same device keeps a
  /// separate cache rather than mixing data.
  String get _cacheKey => 'synced_projects_$uid';

  @override
  Future<List<SavedProject>> loadAll() async => _visible(await _loadCache());

  @override
  Future<List<SavedProject>> upsert(SavedProject project) async {
    final all = await _loadCache();
    final index = all.indexWhere((p) => p.id == project.id);

    if (index >= 0) {
      all[index] = project;
    } else {
      all.add(project);
    }

    await _saveCache(all);
    await _push(project);

    return _visible(all);
  }

  @override
  Future<List<SavedProject>> delete(String id) async {
    final all = await _loadCache();
    final index = all.indexWhere((p) => p.id == id);

    if (index >= 0) {
      final tombstone = all[index].copyWith(
        deleted: true,
        updatedAt: DateTime.now(),
      );
      all[index] = tombstone;
      await _saveCache(all);
      await _push(tombstone);
    }

    return _visible(all);
  }

  /// Reconciles the cache with the server: pull, merge, save, upload the diff.
  /// Returns the merged visible list. Throws if the pull fails (caller falls
  /// back to [loadAll]).
  Future<List<SavedProject>> sync() async {
    final remoteProjects = await remote.listProjects(uid);
    final local = await _loadCache();

    final result = mergeForSync(local, remoteProjects);
    await _saveCache(result.merged);

    for (final project in result.toUpload) {
      await _push(project);
    }

    return _visible(result.merged);
  }

  /// Best-effort upload: a network/permission failure leaves the change in the
  /// cache to be retried by the next [sync].
  Future<void> _push(SavedProject project) async {
    try {
      await remote.putProject(uid, project);
    } on FirestoreException {
      // Swallowed on purpose; the cache keeps the newer copy for next sync.
    }
  }

  Future<List<SavedProject>> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;

    return [
      for (final e in decoded) SavedProject.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> _saveCache(List<SavedProject> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode([for (final p in all) p.toJson()]),
    );
  }

  List<SavedProject> _visible(List<SavedProject> all) {
    final visible = all.where((p) => !p.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return visible;
  }
}
