import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knitcalc/firebase/firestore_client.dart';
import 'package:knitcalc/storage/saved_project.dart';
import 'package:knitcalc/storage/synced_projects_store.dart';

/// In-memory [RemoteProjects] standing in for Firestore.
class FakeRemote implements RemoteProjects {
  final Map<String, SavedProject> docs = {};
  int puts = 0;
  bool offline = false;

  @override
  Future<List<SavedProject>> listProjects(String uid) async {
    if (offline) throw const FirestoreException('offline');
    return docs.values.toList();
  }

  @override
  Future<void> putProject(String uid, SavedProject project) async {
    if (offline) throw const FirestoreException('offline');
    puts++;
    docs[project.id] = project;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SavedProject sample(String id, {DateTime? updatedAt, String name = 'n'}) {
    return SavedProject(
      id: id,
      name: name,
      productId: 'rectangular_scarf',
      values: const {'a': '1'},
      updatedAt: updatedAt ?? DateTime(2026, 6, 7),
    );
  }

  test('upsert writes the cache and pushes to remote', () async {
    final remote = FakeRemote();
    final store = SyncedProjectsStore(uid: 'u1', remote: remote);

    final visible = await store.upsert(sample('1'));

    expect(visible.map((p) => p.id), ['1']);
    expect(remote.docs.containsKey('1'), isTrue);
    expect(remote.puts, 1);
  });

  test('delete tombstones locally (hidden) and on remote', () async {
    final remote = FakeRemote();
    final store = SyncedProjectsStore(uid: 'u1', remote: remote);
    await store.upsert(sample('1'));

    final visible = await store.delete('1');

    expect(visible, isEmpty, reason: 'tombstone is filtered from the UI list');
    expect(remote.docs['1']!.deleted, isTrue);
  });

  test('offline edits persist locally and upload on the next sync', () async {
    final remote = FakeRemote()..offline = true;
    final store = SyncedProjectsStore(uid: 'u1', remote: remote);

    // Push fails silently, but the change is cached and still visible.
    final visible = await store.upsert(sample('1'));
    expect(visible.map((p) => p.id), ['1']);
    expect(remote.puts, 0);

    // Back online: sync uploads the queued local record.
    remote.offline = false;
    await store.sync();
    expect(remote.docs.containsKey('1'), isTrue);
  });

  test('sync pulls remote-only records into the local view', () async {
    final remote = FakeRemote();
    remote.docs['r'] = sample(
      'r',
      name: 'remote',
      updatedAt: DateTime(2026, 5, 1),
    );
    final store = SyncedProjectsStore(uid: 'u1', remote: remote);

    final visible = await store.sync();

    expect(visible.map((p) => p.id), ['r']);
    // A fresh store reads it from the cache without touching remote.
    expect(
      await SyncedProjectsStore(uid: 'u1', remote: FakeRemote()).loadAll(),
      hasLength(1),
    );
  });

  test('sync resolves conflicts last-write-wins', () async {
    final remote = FakeRemote();
    final store = SyncedProjectsStore(uid: 'u1', remote: remote);

    // Local newer than remote for the same id.
    await store.upsert(
      sample('x', name: 'local-new', updatedAt: DateTime(2026, 6, 1)),
    );
    remote.docs['x'] = sample(
      'x',
      name: 'remote-old',
      updatedAt: DateTime(2026, 1, 1),
    );

    final visible = await store.sync();

    expect(visible.single.name, 'local-new');
    expect(remote.docs['x']!.name, 'local-new', reason: 'newer local uploaded');
  });

  test('caches are isolated per user', () async {
    final remote = FakeRemote();
    await SyncedProjectsStore(uid: 'u1', remote: remote).upsert(sample('1'));

    final other = await SyncedProjectsStore(
      uid: 'u2',
      remote: FakeRemote(),
    ).loadAll();

    expect(other, isEmpty);
  });
}
