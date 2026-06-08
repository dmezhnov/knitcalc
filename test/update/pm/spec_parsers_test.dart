import 'package:flutter_test/flutter_test.dart';
import 'package:knitcalc/update/impl/pm/specs/apt_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/flatpak_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/homebrew_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/snap_spec.dart';
import 'package:knitcalc/update/impl/pm/specs/winget_spec.dart';

void main() {
  group('parseWingetUpgrade', () {
    const id = 'Dmezhnov.KnitCalc';

    test('reads the Available column of the package row', () {
      const out = '''
Name      Id                Version Available Source
-----------------------------------------------------
KnitCalc  Dmezhnov.KnitCalc 1.8.7   1.8.8     winget
1 upgrades available.
''';
      expect(parseWingetUpgrade(out, packageId: id), '1.8.8');
    });

    test('handles a name containing spaces', () {
      const out = '''
Name           Id                Version Available Source
----------------------------------------------------------
Knit Calc App  Dmezhnov.KnitCalc 1.8.7   1.9.0     winget
''';
      expect(parseWingetUpgrade(out, packageId: id), '1.9.0');
    });

    test('returns null when no upgrade is offered', () {
      expect(
        parseWingetUpgrade('No available upgrade found.', packageId: id),
        isNull,
      );
      expect(
        parseWingetUpgrade(
          'No installed package found matching input criteria.',
          packageId: id,
        ),
        isNull,
      );
    });
  });

  group('parseBrewOutdated', () {
    test('reads current_version of the first outdated cask', () {
      const out =
          '{"formulae":[],"casks":[{"name":"knitcalc","installed_versions":'
          '["1.8.7"],"current_version":"1.8.8"}]}';
      expect(parseBrewOutdated(out), '1.8.8');
    });

    test('returns null when nothing is outdated', () {
      expect(parseBrewOutdated('{"formulae":[],"casks":[]}'), isNull);
    });

    test('returns null on malformed json', () {
      expect(parseBrewOutdated('not json'), isNull);
      expect(parseBrewOutdated(''), isNull);
    });
  });

  group('parseFlatpakUpdates', () {
    const id = 'io.github.dmezhnov.KnitCalc';

    test('reads the version of the matching app row', () {
      expect(
        parseFlatpakUpdates('io.github.dmezhnov.KnitCalc\t1.8.8', appId: id),
        '1.8.8',
      );
    });

    test('returns null when the app is not in the update list', () {
      expect(parseFlatpakUpdates('org.other.App\t2.0', appId: id), isNull);
      expect(parseFlatpakUpdates('', appId: id), isNull);
    });
  });

  group('parseSnapRefreshList', () {
    test('reads the Version column of the snap row', () {
      const out = '''
Name      Version  Rev  Publisher  Notes
knitcalc  1.8.8    123  dmezhnov   -
''';
      expect(parseSnapRefreshList(out, name: 'knitcalc'), '1.8.8');
    });

    test('returns null when all snaps are up to date', () {
      expect(
        parseSnapRefreshList('All snaps up to date.', name: 'knitcalc'),
        isNull,
      );
    });

    test('does not mistake the header row for a version', () {
      // A header with no following data row must not yield "Version".
      expect(
        parseSnapRefreshList(
          'Name      Version  Rev  Publisher  Notes',
          name: 'Name',
        ),
        isNull,
      );
    });
  });

  group('parseAptSimulate', () {
    test('reads the candidate version from the Inst line', () {
      const out = '''
NOTE: This is only a simulation!
Inst knitcalc [1.8.7] (1.8.8 KnitCalc:stable [amd64])
Conf knitcalc (1.8.8 KnitCalc:stable [amd64])
''';
      expect(parseAptSimulate(out, package: 'knitcalc'), '1.8.8');
    });

    test('returns null when already the newest version', () {
      const out = '''
knitcalc is already the newest version (1.8.8).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
''';
      expect(parseAptSimulate(out, package: 'knitcalc'), isNull);
    });
  });
}
