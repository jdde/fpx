import 'dart:io';

import 'package:fpx/src/commands/list_command.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  group('ListCommand', () {
    late Logger logger;
    late RepositoryService repositoryService;
    late ListCommand command;
    late Directory testDir;
    late Directory originalDir;

    setUp(() async {
      logger = _MockLogger();
      repositoryService = _MockRepositoryService();
      command = ListCommand(logger: logger, repositoryService: repositoryService);

      // Mock empty repositories by default
      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => <String, RepositoryInfo>{});

      // Save original directory
      originalDir = Directory.current;

      // Create a temporary test directory
      testDir = await Directory.systemTemp.createTemp('fpx_list_test_');
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

    test('creates mason.yaml if it does not exist and shows no bricks message',
        () async {
      // Ensure mason.yaml doesn't exist
      final masonYamlFile = File('mason.yaml');
      if (await masonYamlFile.exists()) {
        await masonYamlFile.delete();
      }
      expect(await masonYamlFile.exists(), isFalse);

      // Run the command
      final result = await command.run();

      // Verify the file was created
      expect(await masonYamlFile.exists(), isTrue);
      expect(result, equals(ExitCode.success.code));

      // Verify the content
      final content = await masonYamlFile.readAsString();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));

      // Verify logger calls
      verify(() => logger.info(
              '📦 No mason.yaml found, creating one with default settings...'))
          .called(1);
      verify(() =>
              logger.success('✅ Created mason.yaml with default configuration'))
          .called(1);
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
    });

    test('shows no bricks message when mason.yaml has empty bricks', () async {
      // Create mason.yaml with empty bricks
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
''');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
      verifyNever(() => logger.info(
          '📦 No mason.yaml found, creating one with default settings...'));
    });

    test('shows no bricks message when bricks node is null', () async {
      // Create mason.yaml without bricks node
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
some_other_config: value
''');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
    });

    test('lists available bricks when they exist', () async {
      // Create mason.yaml with bricks
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  button:
    git:
      url: https://github.com/unping/unping-ui.git
      path: bricks/button
  widget:
    path: ./bricks/widget
  form:
    git:
      url: https://github.com/example/forms.git
''');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls
      verify(() => logger.info('Local bricks (mason.yaml):')).called(1);
      verify(() => logger.info('  button')).called(1);
      verify(() => logger.info('  widget')).called(1);
      verify(() => logger.info('  form')).called(1);
      verify(() => logger.info('')).called(1);
      verifyNever(
          () => logger.info('📋 No bricks or repositories configured yet'));
    });

    test('handles invalid yaml gracefully', () async {
      // Create mason.yaml with invalid content
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks: [
  invalid yaml content
''');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Should show no bricks message when YAML is invalid
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
    });

    test('handles non-map yaml content', () async {
      // Create mason.yaml with non-map content
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
- item1
- item2
''');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Should show no bricks message when YAML is not a map
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
    });

    test('handles empty file', () async {
      // Create empty mason.yaml
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('');

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Should show no bricks message when file is empty
      verify(() => logger.info('📋 No bricks or repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Add bricks to mason.yaml or configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
          .called(1);
      verify(() => logger.info('   fpx init  # to create mason.yaml and default repositories'))
          .called(1);
    });

    test('shows configured repositories when they exist', () async {
      // Create mason.yaml with no bricks
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
''');

      // Mock repositories
      when(() => repositoryService.getRepositories()).thenAnswer((_) async => {
        'unping-ui': RepositoryInfo(
          name: 'unping-ui',
          url: 'https://github.com/unping/unping-ui.git',
          path: 'bricks',
        ),
        'test-repo': RepositoryInfo(
          name: 'test-repo',
          url: 'https://github.com/test/repo.git',
          path: 'components',
        ),
      });

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls for repositories
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  unping-ui: https://github.com/unping/unping-ui.git')).called(1);
      verify(() => logger.info('  test-repo: https://github.com/test/repo.git')).called(1);
      verify(() => logger.info('')).called(1);
      verify(() => logger.info('💡 Use "fpx add <brick-name>" to search all repositories')).called(1);
      verify(() => logger.info('   Or "fpx add @repo/<brick-name>" for a specific repository')).called(1);
      
      // Should not show the "no bricks or repositories" message
      verifyNever(() => logger.info('📋 No bricks or repositories configured yet'));
    });

    test('shows both local bricks and repositories when both exist', () async {
      // Create mason.yaml with bricks
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  button:
    git:
      url: https://github.com/unping/unping-ui.git
      path: bricks/button
''');

      // Mock repositories
      when(() => repositoryService.getRepositories()).thenAnswer((_) async => {
        'unping-ui': RepositoryInfo(
          name: 'unping-ui',
          url: 'https://github.com/unping/unping-ui.git',
          path: 'bricks',
        ),
      });

      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls for both local bricks and repositories
      verify(() => logger.info('Local bricks (mason.yaml):')).called(1);
      verify(() => logger.info('  button')).called(1);
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  unping-ui: https://github.com/unping/unping-ui.git')).called(1);
      verify(() => logger.info('💡 Use "fpx add <brick-name>" to search all repositories')).called(1);
      verify(() => logger.info('   Or "fpx add @repo/<brick-name>" for a specific repository')).called(1);
      
      // Should not show the "no bricks or repositories" message
      verifyNever(() => logger.info('📋 No bricks or repositories configured yet'));
    });

    test('can be instantiated without explicit repository service', () {
      final logger = _MockLogger();
      final command = ListCommand(logger: logger);
      expect(command, isNotNull);
    });

    test('has correct name and description', () {
      expect(command.name, equals('list'));
      expect(command.description, equals('List available bricks'));
    });
  });
}
