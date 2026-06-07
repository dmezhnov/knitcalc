/// Common interface for the saved-projects backing store, so the UI does not
/// care whether projects live only on this device or are synced to the cloud.
///
/// [ProjectsRepository] is the local-only implementation (guest mode);
/// [SyncedProjectsStore] adds Firebase sync once signed in. Every method returns
/// the resulting visible list (tombstones excluded), newest-first by
/// [SavedProject.updatedAt].
library;

import 'saved_project.dart';

abstract interface class ProjectsStore {
  Future<List<SavedProject>> loadAll();
  Future<List<SavedProject>> upsert(SavedProject project);
  Future<List<SavedProject>> delete(String id);
}
