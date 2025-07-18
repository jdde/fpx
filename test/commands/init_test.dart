import 'dart:io';

import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('fpx init', () {
    setUp(() {
      setUpTestingEnvironment(cwd, suffix: '.init');
    });

    tearDown(() {
      Directory.current = cwd;
    });

    test('creates mason.yaml when it does not exist', () async {
      expect(File('mason.yaml').existsSync(), isFalse);
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'init'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final masonYamlFile = File('mason.yaml');
      expect(masonYamlFile.existsSync(), isTrue);
      
      final content = masonYamlFile.readAsStringSync();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));
      expect(content, contains('# Example:'));
      expect(content, contains('# button:'));
      expect(content, contains('#   git:'));
      expect(content, contains('#     url: https://github.com/felangel/mason.git'));
      expect(content, contains('#     path: bricks/button'));
      expect(content, contains('# widget:'));
      expect(content, contains('#   path: ./bricks/widget'));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('No mason.yaml found, creating one'));
      expect(stdout, contains('Created mason.yaml with default configuration'));
      expect(stdout, contains('Add your bricks to mason.yaml'));
    });

    test('warns when mason.yaml already exists', () async {
      // Create existing mason.yaml
      File('mason.yaml').writeAsStringSync('bricks:\n  existing: true\n');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'init'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stderr = result.stderr as String;
      expect(stderr, contains('mason.yaml already exists'));
      
      // Verify original content is preserved
      final content = File('mason.yaml').readAsStringSync();
      expect(content, contains('existing: true'));
    });

    test('handles file creation errors gracefully', () async {
      // Create a directory named mason.yaml to simulate file creation error
      Directory('mason.yaml').createSync();
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'init'],
        workingDirectory: Directory.current.path,
      );
      
      // Should handle error (Dart exits with 255 for unhandled exceptions)
      expect(result.exitCode, equals(255));
      
      final stderr = result.stderr as String;
      // Check for either FileSystemException (Unix) or PathAccessException (Windows)
      expect(stderr, anyOf(
        contains('FileSystemException'),
        contains('PathAccessException'),
      ));
    });

    test('creates mason.yaml in subdirectory', () async {
      final subDir = Directory('subdir')..createSync();
      Directory.current = subDir;
      
      final result = await Process.run(
        'dart',
        ['run', '../../../../bin/fpx.dart', 'init'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      expect(File('mason.yaml').existsSync(), isTrue);
    });
  });
}
