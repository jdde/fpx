import 'dart:io';

import 'package:path/path.dart' as path;

String testFixturesPath(Directory cwd, {String suffix = ''}) {
  return path.join(cwd.path, 'test', 'fixtures', suffix);
}

void setUpTestingEnvironment(Directory cwd, {String suffix = ''}) {
  try {
    final testDir = Directory(testFixturesPath(cwd, suffix: suffix));
    if (testDir.existsSync()) testDir.deleteSync(recursive: true);
    testDir.createSync(recursive: true);
    Directory.current = testDir.path;
    // Clean up any existing mason files from previous tests
    try {
      File(path.join(Directory.current.path, 'mason.yaml')).deleteSync();
    } catch (_) {}
    try {
      Directory(path.join(Directory.current.path, '.mason')).deleteSync(recursive: true);
    } catch (_) {}
  } catch (_) {}
}
