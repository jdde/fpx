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

    test('shows no repositories message when no repositories configured',
        () async {
      // Run the command
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));

      // Verify logger calls
      verify(() => logger.info('📋 No repositories configured yet'))
          .called(1);
      verify(() => logger.info('💡 Configure repositories:'))
          .called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>'))
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
      
      // Should not show the "no repositories" message
      verifyNever(() => logger.info('📋 No repositories configured yet'));
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
