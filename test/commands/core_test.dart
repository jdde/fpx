import 'dart:io';

import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('fpx core functionality', () {
    setUp(() {
      setUpTestingEnvironment(cwd, suffix: '.core');
    });

    tearDown(() {
      Directory.current = cwd;
    });

    group('mason.yaml handling', () {
      test('creates default mason.yaml with correct structure', () async {
        await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'init'],
          workingDirectory: Directory.current.path,
        );
        
        final masonYamlFile = File('mason.yaml');
        expect(masonYamlFile.existsSync(), isTrue);
        
        final content = masonYamlFile.readAsStringSync();
        
        // Check structure
        expect(content, contains('bricks:'));
        expect(content, contains('# Add your bricks here'));
        expect(content, contains('# Example:'));
        expect(content, contains('# button:'));
        expect(content, contains('#   git:'));
        expect(content, contains('#     url: https://github.com/felangel/mason.git'));
        expect(content, contains('#     path: bricks/button'));
        expect(content, contains('# widget:'));
        expect(content, contains('#   path: ./bricks/widget'));
      });

      test('preserves existing mason.yaml', () async {
        final originalContent = '''
bricks:
  my_custom_brick:
    path: ./custom_path
  another_brick:
    git:
      url: https://github.com/custom/repo.git
''';
        
        File('mason.yaml').writeAsStringSync(originalContent);
        
        await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'init'],
          workingDirectory: Directory.current.path,
        );
        
        final content = File('mason.yaml').readAsStringSync();
        expect(content, equals(originalContent));
      });
    });

    group('argument parsing', () {
      test('parses component name correctly', () async {
        final result = await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'add', 'my_component'],
          workingDirectory: Directory.current.path,
        );
        
        // Will fail due to missing brick, but should parse component name
        expect(result.exitCode, equals(1));
        final stderr = result.stderr as String;
        expect(stderr, contains('my_component'));
      });

      test('parses path option correctly', () async {
        final customPath = './custom/components';
        
        await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'add', 'button', '--path=$customPath'],
          workingDirectory: Directory.current.path,
        );
        
        // Should create the path directory
        expect(Directory(customPath).existsSync(), isTrue);
      });
    });

    group('error handling', () {
      test('handles missing mason.yaml gracefully', () async {
        expect(File('mason.yaml').existsSync(), isFalse);
        
        final result = await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'list'],
          workingDirectory: Directory.current.path,
        );
        
        expect(result.exitCode, equals(0));
        final stdout = result.stdout as String;
        expect(stdout, contains('No mason.yaml found, creating one'));
        
        // Should auto-create
        expect(File('mason.yaml').existsSync(), isTrue);
      });

      test('handles corrupted mason.yaml', () async {
        File('mason.yaml').writeAsStringSync('invalid: yaml: content: [}');
        
        final result = await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'list'],
          workingDirectory: Directory.current.path,
        );
        
        expect(result.exitCode, equals(0));
        final stdout = result.stdout as String;
        expect(stdout, contains('No bricks configured'));
      });
    });

    group('path handling', () {
      test('handles relative paths', () async {
        const relativePath = './relative/test/path';
        
        await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'add', 'test', '--path=$relativePath'],
          workingDirectory: Directory.current.path,
        );
        
        expect(Directory(relativePath).existsSync(), isTrue);
      });

      test('handles nested path creation', () async {
        const nestedPath = './very/deeply/nested/path/structure';
        
        await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'add', 'test', '--path=$nestedPath'],
          workingDirectory: Directory.current.path,
        );
        
        expect(Directory(nestedPath).existsSync(), isTrue);
      });
    });

    group('variable handling', () {
      test('sets component variable correctly', () async {
        File('mason.yaml').writeAsStringSync('''
bricks:
  test_brick:
    path: ./non-existent
''');
        
        final result = await Process.run(
          'dart',
          ['run', '../../../bin/fpx.dart', 'add', 'my_component'],
          workingDirectory: Directory.current.path,
        );
        
        // Should process component variable internally
        expect(result.exitCode, equals(1));
        final stderr = result.stderr as String;
        expect(stderr, contains('Failed to generate component'));
      });
    });
  });
}
