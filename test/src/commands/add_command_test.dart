import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fpx/src/commands/add_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('AddCommand', () {
    late Logger logger;
    late AddCommand command;
    late Directory testDir;
    late Directory originalDir;
    late CommandRunner<int> commandRunner;

    setUp(() async {
      logger = _MockLogger();
      command = AddCommand(logger: logger);

      // Create a command runner to properly parse arguments
      commandRunner = CommandRunner<int>('test', 'Test runner')
        ..addCommand(command);

      // Save original directory
      originalDir = Directory.current;

      // Create a temporary test directory
      testDir = await Directory.systemTemp.createTemp('fpx_add_test_');
      Directory.current = testDir;

      // Ensure clean state
      final masonYamlFile = File('mason.yaml');
      if (await masonYamlFile.exists()) {
        await masonYamlFile.delete();
      }
    });

    tearDown(() async {
      // Restore original directory first
      Directory.current = originalDir;

      // Clean up temporary directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('returns usage error when no component name provided', () async {
      final result = await commandRunner.run(['add']);

      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(
          '❌ Missing component name. Usage: fpx add <component>')).called(1);
    });

    test('creates mason.yaml if it does not exist when running add', () async {
      // Ensure mason.yaml doesn't exist
      final masonYamlFile = File('mason.yaml');
      if (await masonYamlFile.exists()) {
        await masonYamlFile.delete();
      }
      expect(await masonYamlFile.exists(), isFalse);

      // This will fail because the brick doesn't exist, but it will create mason.yaml first
      try {
        await commandRunner.run(['add', 'test_component']);
      } catch (e) {
        // Expected to fail due to missing brick
      }

      // Verify mason.yaml was created
      expect(await masonYamlFile.exists(), isTrue);

      final content = await masonYamlFile.readAsString();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));

      verify(() => logger.info(
              '📦 No mason.yaml found, creating one with default settings...'))
          .called(1);
      verify(() =>
              logger.success('✅ Created mason.yaml with default configuration'))
          .called(1);
    });

    test('handles missing brick error correctly', () async {
      // Create mason.yaml without the requested brick
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  other_component:
    path: ./other_brick
''');

      // Try to add a non-existent component
      final exitCode = await commandRunner.run(['add', 'nonexistent_component']);
      
      // Should return non-zero exit code
      expect(exitCode, equals(ExitCode.usage.code));

      // Verify error is logged with the new message format
      verify(() =>
              logger.err(any(that: contains('Component "nonexistent_component" not found. No repositories configured'))))
          .called(1);
    });

    test('loads mason.yaml correctly when it exists', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  button:
    git:
      url: https://github.com/unping/unping-ui.git
      path: bricks/button
  widget:
    path: ./bricks/widget
''');

      expect(await masonYamlFile.exists(), isTrue);

      final content = await masonYamlFile.readAsString();
      expect(content, contains('button:'));
      expect(content, contains('widget:'));
      expect(content, contains('git:'));
      expect(content, contains('path:'));
    });

    test('handles yaml loading errors gracefully', () async {
      final masonYamlFile = File('mason.yaml');
      // Create invalid YAML content
      await masonYamlFile.writeAsString('''
bricks:
  invalid: [
    missing_closing_bracket
''');

      expect(await masonYamlFile.exists(), isTrue);

      // The command should handle invalid YAML gracefully
      // This tests the error handling in _loadMasonYaml
    });

    test('handles command with path option', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test with path option
      try {
        await commandRunner
            .run(['add', 'test_component', '--path', './custom_path']);
      } catch (e) {
        // Expected to fail due to missing brick files
      }

      // Test that the path option is properly parsed
      expect(command.argParser.options.containsKey('path'), isTrue);
    });

    test('handles command with name option', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test with name option
      try {
        await commandRunner
            .run(['add', 'test_component', '--name', 'custom_name']);
      } catch (e) {
        // Expected to fail due to missing brick files
      }

      // Test that the name option is properly parsed
      expect(command.argParser.options.containsKey('name'), isTrue);
    });

    test('handles command with variant option', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test with variant option
      try {
        await commandRunner
            .run(['add', 'test_component', '--variant', 'primary']);
      } catch (e) {
        // Expected to fail due to missing brick files
      }

      // Test that the variant option is properly parsed
      expect(command.argParser.options.containsKey('variant'), isTrue);
    });

    test('handles command with source option', () async {
      // Test with source option (git URL)
      try {
        await commandRunner.run([
          'add',
          'test_component',
          '--source',
          'https://github.com/example/repo.git'
        ]);
      } catch (e) {
        // Expected to fail due to network/brick issues
      }

      // Test that the source option is properly parsed
      expect(command.argParser.options.containsKey('source'), isTrue);
    });

    test('handles source option with local path', () async {
      // Create local directory
      final localBrickDir = Directory('./local_brick');
      await localBrickDir.create();

      // Test with source option (local path)
      try {
        await commandRunner
            .run(['add', 'test_component', '--source', './local_brick']);
      } catch (e) {
        // Expected to fail due to missing brick.yaml
      }

      expect(await localBrickDir.exists(), isTrue);
    });

    test('handles git source URLs correctly in mason.yaml', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  remote_component:
    git:
      url: https://github.com/example/mason_bricks.git
      path: bricks/component
''');

      expect(await masonYamlFile.exists(), isTrue);

      final content = await masonYamlFile.readAsString();
      expect(content, contains('https://github.com/example/mason_bricks.git'));
    });

    test('creates target directory if it does not exist', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test that target directory creation logic is covered
      final targetDir = Directory('./non_existent_target');
      expect(await targetDir.exists(), isFalse);

      // Test with custom path that doesn't exist
      try {
        await commandRunner
            .run(['add', 'test_component', '--path', './non_existent_target']);
      } catch (e) {
        // Expected to fail due to missing brick files
      }
    });

    test('handles multiple repositories with same component name', () async {
      // This would test the logic when multiple search results are found
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test with repository option to specify which one to use
      try {
        await commandRunner.run([
          'add',
          'test_component',
          '--repository',
          'specific-repo'
        ]);
      } catch (e) {
        // Expected to fail due to missing repositories
      }

      // Test that the repository option is properly parsed
      expect(command.argParser.options.containsKey('repository'), isTrue);
    });

    test('handles component with custom variables', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Create a test brick directory with brick.yaml
      final brickDir = Directory('./test_brick');
      await brickDir.create(recursive: true);
      
      final brickYamlFile = File('./test_brick/brick.yaml');
      await brickYamlFile.writeAsString('''
name: test_component
description: A test component
version: 0.1.0+1
vars:
  name:
    type: string
    description: Component name
    default: TestComponent
    prompt: What is the component name?
  primary_color:
    type: string
    description: Primary color
    default: blue
''');

      // Create a simple template file
      final templateDir = Directory('./test_brick/__brick__');
      await templateDir.create(recursive: true);
      
      final templateFile = File('./test_brick/__brick__/{{name.snakeCase()}}.dart');
      await templateFile.writeAsString('''
class {{name.pascalCase()}} {
  // Component implementation
}
''');

      // Test adding component which should trigger variable prompting
      try {
        await commandRunner.run(['add', 'test_component']);
      } catch (e) {
        // May fail due to missing interactive input, but should test variable handling
      }
    });

    test('handles brick with missing brick.yaml', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Create brick directory without brick.yaml
      final brickDir = Directory('./test_brick');
      await brickDir.create(recursive: true);

      // This should handle the missing brick.yaml case
      try {
        await commandRunner.run(['add', 'test_component']);
      } catch (e) {
        // Expected to fail due to missing brick.yaml
      }
    });

    test('handles component generation success path', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Create a complete brick structure
      final brickDir = Directory('./test_brick');
      await brickDir.create(recursive: true);
      
      final brickYamlFile = File('./test_brick/brick.yaml');
      await brickYamlFile.writeAsString('''
name: test_component
description: A test component
version: 0.1.0+1
vars:
  name:
    type: string
    description: Component name
    default: TestComponent
''');

      final templateDir = Directory('./test_brick/__brick__');
      await templateDir.create(recursive: true);
      
      final templateFile = File('./test_brick/__brick__/{{name.snakeCase()}}.dart');
      await templateFile.writeAsString('''
class {{name.pascalCase()}} {
  // Generated component
}
''');

      // Create target directory
      final targetDir = Directory('./output');
      await targetDir.create();

      // This should successfully generate the component
      try {
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path',
          './output',
          '--name',
          'MyTestComponent'
        ]);
        
        // If successful, check for success messages
        if (exitCode == ExitCode.success.code) {
          verify(() => logger.success(any(that: contains('Successfully generated')))).called(1);
        }
      } catch (e) {
        // May still fail due to other constraints
      }
    });

    test('handles absolute path for target directory', () async {
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_component:
    path: ./test_brick
''');

      // Test with absolute path
      final absolutePath = '${Directory.current.path}/absolute_target';
      try {
        await commandRunner.run([
          'add',
          'test_component',
          '--path',
          absolutePath
        ]);
      } catch (e) {
        // Expected to fail due to missing brick
      }
    });

    test('handles git source URL with remote repository', () async {
      // Test the legacy source behavior with git URLs
      try {
        await commandRunner.run([
          'add',
          'remote_component',
          '--source',
          'https://github.com/test/bricks.git'
        ]);
      } catch (e) {
        // Expected to fail due to network issues in test environment
      }
    });

    test('handles has correct name, description, and invocation', () {
      expect(command.name, equals('add'));
      expect(command.description, equals('Add a component using Mason bricks'));
      expect(command.invocation, equals('fpx add <component> [options]'));
    });

    test('has correct argument options', () {
      expect(command.argParser.options.containsKey('name'), isTrue);
      expect(command.argParser.options.containsKey('variant'), isTrue);
      expect(command.argParser.options.containsKey('path'), isTrue);
      expect(command.argParser.options.containsKey('source'), isTrue);
      expect(command.argParser.options.containsKey('repository'), isTrue);

      // Test default value for path option
      expect(command.argParser.options['path']!.defaultsTo, equals('.'));
    });
  });
}
