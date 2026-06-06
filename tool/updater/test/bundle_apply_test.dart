import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:knitcalc_updater/bundle_apply.dart';
import 'package:test/test.dart';

ArchiveFile _file(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

String _zip(Directory dir, List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  final path = '${dir.path}/bundle.zip';
  File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return path;
}

void main() {
  late Directory tmp;
  late Directory install;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bundle_apply_test');
    install = Directory('${tmp.path}/install')..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('applyZipOverDirectory', () {
    test('extracts files and creates subdirectories', () {
      final archive = _zip(tmp, [
        _file('knitcalc.exe', 'new-exe'),
        _file('data/flutter_assets/asset.txt', 'asset-body'),
      ]);

      applyZipOverDirectory(archive, install.path);

      expect(
        File('${install.path}/knitcalc.exe').readAsStringSync(),
        'new-exe',
      );
      expect(
        File(
          '${install.path}/data/flutter_assets/asset.txt',
        ).readAsStringSync(),
        'asset-body',
      );
    });

    test('overwrites an existing file in place', () {
      File('${install.path}/knitcalc.exe').writeAsStringSync('old-exe');

      final archive = _zip(tmp, [_file('knitcalc.exe', 'updated-exe')]);
      applyZipOverDirectory(archive, install.path);

      expect(
        File('${install.path}/knitcalc.exe').readAsStringSync(),
        'updated-exe',
      );
    });

    test('leaves unrelated existing files untouched', () {
      File('${install.path}/user-data.txt').writeAsStringSync('keep me');

      final archive = _zip(tmp, [_file('knitcalc.exe', 'new-exe')]);
      applyZipOverDirectory(archive, install.path);

      expect(
        File('${install.path}/user-data.txt').readAsStringSync(),
        'keep me',
      );
    });

    test('leaves no temporary staging files behind', () {
      final archive = _zip(tmp, [
        _file('knitcalc.exe', 'new-exe'),
        _file('data/icudtl.dat', 'icu'),
      ]);

      applyZipOverDirectory(archive, install.path);

      final leftovers = install
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.knitcalc-new'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('skips directory entries without writing files for them', () {
      final archive = Archive()
        ..addFile(_file('knitcalc.exe', 'new-exe'))
        ..addFile(ArchiveFile('data/', 0, const <int>[])..isFile = false);
      final path = '${tmp.path}/with-dir.zip';
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));

      applyZipOverDirectory(path, install.path);

      expect(File('${install.path}/knitcalc.exe').existsSync(), isTrue);
      // The directory entry must not have produced a file named `data`.
      expect(FileSystemEntity.isFileSync('${install.path}/data'), isFalse);
    });
  });
}
