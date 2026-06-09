import 'package:flutter/material.dart';
import 'package:knitcalc/account_menu.dart';
import 'package:knitcalc/calculator.dart';
import 'package:knitcalc/firebase/auth_scope.dart';
import 'package:knitcalc/firebase/auth_service.dart';
import 'package:knitcalc/firebase/firebase_config.dart';
import 'package:knitcalc/firebase/firestore_client.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';
import 'package:knitcalc/name_dialog.dart';
import 'package:knitcalc/products/products.dart';
import 'package:knitcalc/storage/photo_codec.dart';
import 'package:knitcalc/storage/projects_repository.dart';
import 'package:knitcalc/storage/projects_store.dart';
import 'package:knitcalc/storage/saved_project.dart';
import 'package:knitcalc/storage/synced_projects_store.dart';
import 'package:knitcalc/update/app_version.dart';
import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/ui/update_banner.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_factory.dart';
import 'package:knitcalc/update/update_info.dart';
import 'package:knitcalc/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Root screen. With nothing saved it shows only the calculator (there is no
/// empty list to navigate to); once at least one project exists it shows the
/// list, from which projects are opened, renamed or deleted.
///
/// The backing [ProjectsStore] follows the cloud sign-in state: a local-only
/// repository when signed out, a [SyncedProjectsStore] (with a first-login
/// upload prompt) when signed in. Switching accounts rebuilds the store.
class Home extends StatefulWidget {
  const Home({super.key, this.storeBuilder});

  /// Builds the backing store for the given auth state. Defaults to the real
  /// local/synced selection; overridden in tests to inject a fake remote.
  final ProjectsStore Function(AuthService auth)? storeBuilder;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late ProjectsStore _store;

  /// Tracks the signed-in user the current [_store] was built for, so we only
  /// rebuild it when the account actually changes (not on, say, locale changes).
  String? _activeUid;
  bool _initialized = false;

  /// The saved projects, newest-first.
  List<SavedProject> _saved = [];

  /// Whether the first load has finished; until then we show nothing rather than
  /// flashing the empty-state calculator before any saved projects appear.
  bool _loaded = false;

  /// Re-checks for updates whenever the app returns to the foreground, so a
  /// long-running session still notices a release without a restart.
  late final AppLifecycleListener _lifecycle;

  /// Minimum gap between update checks. The startup check covers fresh
  /// launches, so this in-memory throttle need not survive a restart; it only
  /// stops repeated resumes from hammering the GitHub releases API.
  static const Duration _updateCheckInterval = Duration(hours: 6);
  DateTime? _lastUpdateCheck;

  /// The version already surfaced via a banner this session. A resume re-check
  /// that returns the same release skips re-showing, so banners never stack.
  AppVersion? _shownUpdateVersion;

  /// Drives the pull-to-refresh indicator so the account menu's "Sync" item can
  /// trigger the same gesture (spinner + [_sync]) without a real pull.
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();

    _lifecycle = AppLifecycleListener(onResume: _maybeCheckForUpdate);

    // Check for an update once the first frame is on screen. Off the web target
    // the factory returns a no-op service, so this is harmless there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = AuthScope.of(context);

    // Rebuild the store and reload only when the signed-in account changes; this
    // also fires on other inherited changes (e.g. locale), which we ignore.
    if (!_initialized || auth.uid != _activeUid) {
      _initialized = true;
      _activeUid = auth.uid;
      _store = (widget.storeBuilder ?? _buildStore)(auth);
      _refresh();
    }
  }

  ProjectsStore _buildStore(AuthService auth) {
    final uid = auth.uid;

    if (uid == null) {
      return const ProjectsRepository();
    }

    return SyncedProjectsStore(
      uid: uid,
      remote: FirestoreClient(
        config: firebaseConfig,
        tokenProvider: auth.freshIdToken,
      ),
    );
  }

  /// Throttled entry point for the resume trigger: skips the check when the
  /// last one was recent enough to keep within [_updateCheckInterval].
  void _maybeCheckForUpdate() {
    final last = _lastUpdateCheck;
    if (last != null &&
        DateTime.now().difference(last) < _updateCheckInterval) {
      return;
    }

    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    _lastUpdateCheck = DateTime.now();

    final channel = await detectChannel();
    final service = createUpdateService(channel);
    final info = await service.checkForUpdate();

    if (info == null || !mounted) {
      return;
    }

    // A resume re-check can return the release we already surfaced; don't stack
    // a second banner for the same version.
    if (info.latestVersion == _shownUpdateVersion) {
      return;
    }
    _shownUpdateVersion = info.latestVersion;

    _showUpdateBanner(service, info);
  }

  /// Shows the update banner and brings it back if the update flow returns
  /// without replacing the running app — i.e. the download failed or the user
  /// backed out of the progress dialog / install prompt. Without this the
  /// banner would stay hidden for the rest of the session (the
  /// [_shownUpdateVersion] guard blocks the resume re-check from re-showing it).
  /// On web [UpdateService.startUpdate] reloads the page, so the re-show after
  /// the await never runs there.
  void _showUpdateBanner(UpdateService service, UpdateInfo info) {
    showUpdateBanner(
      context,
      info: info,
      onUpdate: () async {
        if (info.action == UpdateAction.openUrl ||
            info.action == UpdateAction.runCommand) {
          // External channels open a listing or hand off to a package manager;
          // no in-app download dialog. On runCommand the app exits before this
          // returns. Surface a failure the same way runUpdateWithProgress does.
          final messenger = ScaffoldMessenger.of(context);
          final l10n = AppLocalizations.of(context);
          try {
            await service.startUpdate(info);
          } on Object {
            messenger.showSnackBar(SnackBar(content: Text(l10n.updateFailed)));
          }
        } else {
          await runUpdateWithProgress(context, service, info);
        }
        if (mounted) {
          _showUpdateBanner(service, info);
        }
      },
    );
  }

  /// Loads the project list for the active store. For a synced store it first
  /// offers to migrate any local projects, then pulls and merges from the cloud,
  /// falling back to the cache (with a notice) when offline.
  Future<List<SavedProject>> _loadProjects() async {
    final store = _store;

    if (store is SyncedProjectsStore) {
      await _maybeMigrate(store);
      try {
        return await store.sync();
      } on FirestoreException {
        final cached = await store.loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).syncFailedSnack),
            ),
          );
        }
        return cached;
      }
    }

    return store.loadAll();
  }

  /// Reloads the list with the full-screen loader, used on first open and after
  /// returning from the editor.
  Future<void> _refresh() async {
    setState(() => _loaded = false);

    final projects = await _loadProjects();

    if (!mounted) {
      return;
    }

    setState(() {
      _saved = projects;
      _loaded = true;
    });
  }

  /// Pull-to-refresh: re-syncs while the list stays visible, so the
  /// [RefreshIndicator]'s own spinner at the top conveys progress instead of
  /// the full-screen loader. Alongside the data pull it refreshes the Google
  /// avatar (if it changed) and re-checks for an app update.
  Future<void> _sync() async {
    // Pick up a changed Google avatar (no-op for password accounts).
    await AuthScope.of(context).refreshProfile();

    final projects = await _loadProjects();

    if (mounted) {
      setState(() => _saved = projects);
    }

    // Surface a newer release the same way the startup/resume check does.
    await _checkForUpdate();
  }

  /// On the first sign-in on this device, offers to upload any projects saved
  /// locally as a guest into the account. The decision is remembered per user.
  Future<void> _maybeMigrate(SyncedProjectsStore store) async {
    final prefs = await SharedPreferences.getInstance();
    final flagKey = 'migrated_${store.uid}';

    if (prefs.getBool(flagKey) ?? false) {
      return;
    }

    const guest = ProjectsRepository();
    final local = await guest.loadAll();

    if (local.isEmpty) {
      await prefs.setBool(flagKey, true);
      return;
    }

    if (!mounted) {
      return;
    }

    final upload = await _confirmMigrate(local.length);
    await prefs.setBool(flagKey, true);

    if (upload) {
      for (final project in local) {
        await store.upsert(project);
      }
      for (final project in local) {
        await guest.delete(project.id);
      }
    }
  }

  Future<bool> _confirmMigrate(int count) async {
    final l10n = AppLocalizations.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.migrateTitle),
        content: Text(l10n.migrateMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.migrateKeepLocalAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.migrateUploadAction),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Opens the calculator for [project] (or a fresh draft when `null`) as a
  /// pushed route, and refreshes the list once it returns.
  Future<void> _openCalculator([SavedProject? project]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            Calculator(repository: _store, initial: project, onSaved: _refresh),
      ),
    );

    await _refresh();
  }

  Future<void> _rename(SavedProject project) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptProjectName(
      context,
      title: l10n.renameDialogTitle,
      initial: project.name,
    );

    if (name == null) {
      return;
    }

    final saved = await _store.upsert(
      project.copyWith(name: name, updatedAt: DateTime.now()),
    );

    if (!mounted) {
      return;
    }

    setState(() => _saved = saved);
  }

  Future<void> _delete(SavedProject project) async {
    if (!await _confirmDelete(project)) {
      return;
    }

    final saved = await _store.delete(project.id);

    if (!mounted) {
      return;
    }

    setState(() => _saved = saved);
  }

  Future<bool> _confirmDelete(SavedProject project) async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(project.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Nothing saved yet: the calculator is the whole app, with no way back to an
    // empty list. Saving the first project repopulates the list (via onSaved).
    if (_saved.isEmpty) {
      return Calculator(repository: _store, onSaved: _refresh);
    }

    final l10n = AppLocalizations.of(context);

    // Pull-to-refresh re-syncs with the cloud when signed in; a local-only store
    // has nothing to pull, so its pull only re-checks for an app update.
    final synced = _store is SyncedProjectsStore;

    final list = ListView(
      // Stay scrollable so the list can be pulled down even with few projects.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final project in _saved)
          ListTile(
            key: Key('saved_${project.id}'),
            leading: project.photos.isEmpty
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      decodePhoto(project.photos.first),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
            title: Text(project.name),
            subtitle: Text(productById(project.productId).name(l10n)),
            onTap: () => _openCalculator(project),
            trailing: PopupMenuButton<void>(
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _rename(project),
                  child: Text(l10n.renameAction),
                ),
                PopupMenuItem(
                  onTap: () => _delete(project),
                  child: Text(l10n.deleteAction),
                ),
              ],
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnitCalc'),
        actions: [
          const LanguageMenu(),
          // Only signed-in (synced) shows the "Sync" item; it shows the same
          // refresh spinner the pull gesture does.
          AccountMenu(
            onSync: synced ? () => _refreshKey.currentState?.show() : null,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCalculator(),
        icon: const Icon(Icons.add),
        label: Text(l10n.newProjectAction),
      ),
      body: SafeArea(
        // Both states are pullable; only the signed-in pull re-syncs data, a
        // local pull just re-checks for an app update.
        child: RefreshIndicator(
          key: _refreshKey,
          onRefresh: synced ? _sync : _checkForUpdate,
          child: list,
        ),
      ),
    );
  }
}
