import 'package:flutter/material.dart';
import 'package:knitcalc/calculator.dart';
import 'package:knitcalc/l10n/app_localizations.dart';
import 'package:knitcalc/language_menu.dart';
import 'package:knitcalc/name_dialog.dart';
import 'package:knitcalc/products/products.dart';
import 'package:knitcalc/storage/photo_codec.dart';
import 'package:knitcalc/storage/projects_repository.dart';
import 'package:knitcalc/storage/saved_project.dart';
import 'package:knitcalc/update/channel.dart';
import 'package:knitcalc/update/ui/update_banner.dart';
import 'package:knitcalc/update/ui/update_progress.dart';
import 'package:knitcalc/update/update_factory.dart';

/// Root screen. With nothing saved it shows only the calculator (there is no
/// empty list to navigate to); once at least one project exists it shows the
/// list, from which projects are opened, renamed or deleted.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final ProjectsRepository _repository = const ProjectsRepository();

  /// The saved projects, newest-first.
  List<SavedProject> _saved = [];

  /// Whether the first load has finished; until then we show nothing rather than
  /// flashing the empty-state calculator before any saved projects appear.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();

    // Check for an update once the first frame is on screen. Off the web target
    // the factory returns a no-op service, so this is harmless there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());

    _loadSaved();
  }

  Future<void> _checkForUpdate() async {
    final channel = await detectChannel();
    final service = createUpdateService(channel);
    final info = await service.checkForUpdate();

    if (info == null || !mounted) {
      return;
    }

    showUpdateBanner(
      context,
      info: info,
      onUpdate: () => runUpdateWithProgress(context, service, info),
    );
  }

  Future<void> _loadSaved() async {
    final saved = await _repository.loadAll();

    if (!mounted) {
      return;
    }

    setState(() {
      _saved = saved;
      _loaded = true;
    });
  }

  /// Opens the calculator for [project] (or a fresh draft when `null`) as a
  /// pushed route, and refreshes the list once it returns.
  Future<void> _openCalculator([SavedProject? project]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Calculator(
          repository: _repository,
          initial: project,
          onSaved: _loadSaved,
        ),
      ),
    );

    await _loadSaved();
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

    final saved = await _repository.upsert(
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

    final saved = await _repository.delete(project.id);

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
      return Calculator(repository: _repository, onSaved: _loadSaved);
    }

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnitCalc'),
        actions: const [LanguageMenu()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCalculator(),
        icon: const Icon(Icons.add),
        label: Text(l10n.newProjectAction),
      ),
      body: SafeArea(
        child: ListView(
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
        ),
      ),
    );
  }
}
