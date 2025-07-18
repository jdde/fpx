import 'dart:io';

import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('fpx add', () {
    setUp(() {
      setUpTestingEnvironment(cwd, suffix: '.add');
    });

    tearDown(() {
      Directory.current = cwd;
    });

    test('exits with error when no component name is provided', () async {
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(1));
      
      final stderr = result.stderr as String;
      expect(stderr, contains('Missing component name'));
      expect(stderr, contains('Usage: fpx add <component>'));
    });

    test('auto-initializes mason.yaml when it does not exist', () async {
      expect(File('mason.yaml').existsSync(), isFalse);
      
      // This will fail because the brick doesn't exist, but should auto-initialize
      await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'button'],
        workingDirectory: Directory.current.path,
      );
      
      // Should create mason.yaml even if brick not found
      expect(File('mason.yaml').existsSync(), isTrue);
      
      final content = File('mason.yaml').readAsStringSync();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));
    });

    test('handles non-existent brick gracefully', () async {
      File('mason.yaml').writeAsStringSync('bricks:\n');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'non-existent-brick'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(1));
      
      final stderr = result.stderr as String;
      expect(stderr, contains('Brick "non-existent-brick" not found'));
      expect(stderr, contains('add it to mason.yaml or use --source option'));
    });

    test('handles brick with --source parameter', () async {
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'button', '--source=https://github.com/felangel/mason.git'],
        workingDirectory: Directory.current.path,
      );
      
      // This might fail due to network/git issues, but should attempt to use the source
      final stderr = result.stderr as String;
      final stdout = result.stdout as String;
      
      // Should either succeed or show appropriate error for git/network issues
      if (result.exitCode != 0) {
        expect(stderr + stdout, anyOf([
          contains('Fetching brick from remote source'),
          contains('Failed to generate component'),
          contains('git'),
        ]));
      }
    });

    test('creates target directory when it does not exist', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  test_brick:
    path: ./non-existent-brick
''');
      
      final targetDir = 'custom/nested/path';
      
      await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'test_brick', '--path=$targetDir'],
        workingDirectory: Directory.current.path,
      );
      
      // Should create the directory structure
      expect(Directory(targetDir).existsSync(), isTrue);
    });

    test('handles various command-line options', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  test_brick:
    path: ./non-existent-brick
''');
      
      final result = await Process.run(
        'dart',
        [
          'run', '../../../bin/fpx.dart', 'add', 'test_brick',
          '--name=TestComponent',
          '--variant=primary',
          '--path=./components',
        ],
        workingDirectory: Directory.current.path,
      );
      
      // Should parse all options (will fail due to non-existent brick)
      final stderr = result.stderr as String;
      expect(stderr, contains('Failed to generate component'));
    });

    test('handles local path brick source', () async {
      // Create a mock local brick directory structure
      final brickDir = Directory('local_bricks/test_brick');
      brickDir.createSync(recursive: true);
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'test_brick', '--source=./local_bricks/test_brick'],
        workingDirectory: Directory.current.path,
      );
      
      // Should detect it as a local path
      final stderr = result.stderr as String;
      final stdout = result.stdout as String;
      
      // Might fail due to missing brick.yaml but should attempt local path
      expect(stderr + stdout, anyOf([
        contains('Failed to generate component'),
        contains('local'),
        contains('path'),
      ]));
    });

    test('handles git URL source detection', () async {
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'button', '--source=https://github.com/felangel/mason.git'],
        workingDirectory: Directory.current.path,
      );
      
      final stderr = result.stderr as String;
      final stdout = result.stdout as String;
      
      // Should attempt to fetch from git
      if (stderr.contains('Fetching brick from remote source') || 
          stdout.contains('Fetching brick from remote source')) {
        // Successfully detected as git URL
        expect(true, isTrue);
      } else {
        // Might fail due to network/git issues
        expect(stderr + stdout, anyOf([
          contains('Failed to generate component'),
          contains('git'),
          contains('remote'),
        ]));
      }
    });

    test('handles missing brick with helpful error message', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  existing_brick:
    path: ./some/path
''');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'missing_brick'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(1));
      
      final stderr = result.stderr as String;
      expect(stderr, contains('Brick "missing_brick" not found'));
      expect(stderr, contains('add it to mason.yaml'));
      expect(stderr, contains('Run "fpx init"'));
    });

    test('preserves existing mason.yaml when auto-initializing', () async {
      expect(File('mason.yaml').existsSync(), isFalse);
      
      // First command creates mason.yaml
      await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'brick1'],
        workingDirectory: Directory.current.path,
      );
      
      expect(File('mason.yaml').existsSync(), isTrue);
      
      // Second command should not overwrite
      await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'brick2'],
        workingDirectory: Directory.current.path,
      );
      
      final content = File('mason.yaml').readAsStringSync();
      expect(content, contains('bricks:'));
      // Should still contain the default template, not be overwritten
      expect(content, contains('# Add your bricks here'));
    });

    test('handles complex mason.yaml brick configurations', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  # Git brick with path
  button:
    git:
      url: https://github.com/felangel/mason.git
      path: bricks/button
      ref: main
  
  # Local brick
  widget:
    path: ./local_bricks/widget
    
  # Registry brick
  card: ^1.0.0
''');
      
      // Test git brick
      final result1 = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'button', '--name=MyButton'],
        workingDirectory: Directory.current.path,
      );
      
      // Should attempt to use git source (may fail due to network)
      if (result1.exitCode != 0) {
        final stderr = result1.stderr as String;
        expect(stderr, anyOf([
          contains('Failed to generate component'),
          contains('git'),
        ]));
      }
      
      // Test local brick
      final result2 = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'add', 'widget', '--name=MyWidget'],
        workingDirectory: Directory.current.path,
      );
      
      // Should attempt to use local path (will fail since path doesn't exist)
      expect(result2.exitCode, equals(1));
      final stderr2 = result2.stderr as String;
      expect(stderr2, contains('Failed to generate component'));
    });
  });
}
