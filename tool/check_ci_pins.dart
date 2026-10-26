// Fails if a GitHub Actions workflow uses a version that can move on its own.
//
//   dart run tool/check_ci_pins.dart
//
// Two kinds of floating references are rejected:
//   - runner labels `ubuntu-latest`, `windows-latest`, `macos-latest` (and
//     their `-large`, `-xlarge` variants), which GitHub migrates to a new
//     image — ubuntu-latest is about to become Ubuntu 26.04 — so a build that
//     passed yesterday can break, or quietly link a newer glibc or Visual
//     Studio, without a commit here. Name the exact image instead
//     (ubuntu-24.04, windows-2025, macos-26);
//   - actions referenced by a tag or branch (`actions/checkout@v5`), which the
//     action's owner can re-point. Pin the commit SHA with the version as a
//     comment: `actions/checkout@<40 hex> # v5.1.0`. Local actions
//     (`./.github/actions/...`) are part of this repository and need no pin.
//
// Renovate (.github/renovate.json) proposes every upgrade of these as a pull
// request into `test`; nothing here is bumped by hand.
//
// The whole workflow tree is walked rather than just `runs-on`, so a label
// coming in through a matrix (`runs-on: ${{ matrix.os }}`) is caught too.
//
// `mise lint` runs this check.
import 'dart:io';

import 'package:yaml/yaml.dart';

const List<String> scannedDirectories = [
  '.github/workflows',
  '.github/actions',
];

final RegExp movingLabel = RegExp(r'^(ubuntu|windows|macos)-latest(-\w+)?$');

final RegExp pinnedAction = RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$');

void main() {
  final files = <File>[
    for (final directory in scannedDirectories)
      if (Directory(directory).existsSync())
        ...Directory(directory)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
            ),
  ]..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('check_ci_pins: no workflows found in .github');
    exit(1);
  }

  final problems = <String>[];
  for (final file in files) {
    _collect(loadYaml(file.readAsStringSync()), file.path, '', problems);
  }

  if (problems.isNotEmpty) {
    stderr.writeln(
      'check_ci_pins: floating versions; name the exact runner image '
      '(ubuntu-24.04, windows-2025, macos-26) and pin actions to a '
      'commit SHA with a "# vX.Y.Z" comment:',
    );
    for (final problem in problems) {
      stderr.writeln('  $problem');
    }
    exit(1);
  }
  stdout.writeln(
    'check_ci_pins: every runner and action in ${files.length} files is pinned.',
  );
}

/// Walks [node] and records every moving runner label and every action not
/// pinned to a commit, with the file and the key path that lead to it.
void _collect(Object? node, String file, String path, List<String> problems) {
  if (node is YamlMap) {
    for (final entry in node.entries) {
      final key = '$path.${entry.key}';
      final value = entry.value;
      if (entry.key == 'uses' && value is String) {
        final ref = value.trim();
        if (!ref.startsWith('./') && !pinnedAction.hasMatch(ref)) {
          problems.add('$file: $key = $ref');
        }
      } else {
        _collect(value, file, key, problems);
      }
    }
  } else if (node is YamlList) {
    for (final (index, item) in node.indexed) {
      _collect(item, file, '$path[$index]', problems);
    }
  } else if (node is String && movingLabel.hasMatch(node.trim())) {
    problems.add('$file: $path = $node');
  }
}
