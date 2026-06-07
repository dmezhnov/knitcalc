/// Persists the list of [SavedProject]s.
///
/// The whole list lives as a single JSON array under one [SharedPreferences]
/// key, which works uniformly across every target (localStorage on web, native
/// preferences elsewhere). Each mutation reads the current list, edits it, and
/// writes it back, keeping the stored ordering newest-first by [updatedAt].
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'saved_project.dart';

class ProjectsRepository {
  const ProjectsRepository();

  static const String _storageKey = 'saved_projects';

  /// All saved projects, newest-first by [SavedProject.updatedAt].
  Future<List<SavedProject>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final projects = decoded
        .map((e) => SavedProject.fromJson(e as Map<String, dynamic>))
        .toList();

    _sort(projects);

    return projects;
  }

  /// Inserts [project], or replaces the existing one with the same
  /// [SavedProject.id]. Returns the resulting full list, newest-first.
  Future<List<SavedProject>> upsert(SavedProject project) async {
    final projects = await loadAll();
    final index = projects.indexWhere((p) => p.id == project.id);

    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.add(project);
    }

    return _persist(projects);
  }

  /// Removes the project with [id] if present. Returns the remaining list.
  Future<List<SavedProject>> delete(String id) async {
    final projects = await loadAll();
    projects.removeWhere((p) => p.id == id);

    return _persist(projects);
  }

  Future<List<SavedProject>> _persist(List<SavedProject> projects) async {
    _sort(projects);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );

    return projects;
  }

  void _sort(List<SavedProject> projects) =>
      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
