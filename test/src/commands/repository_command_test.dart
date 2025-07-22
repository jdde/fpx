import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fpx/src/commands/repository_command.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('RepositoryCommand', () {
    late Logger logger;
    late RepositoryCommand command;
    late Directory testDir;
    late Directory originalDir;
    late CommandRunner<int> commandRunner;

    setUp(() async {
      logger = _MockLogger();
      command = RepositoryCommand(logger: logger);
      commandRunner = CommandRunner<int>('test', 'Test command runner')
        ..addCommand(command);

      // Create and switch to test directory
      originalDir = Directory.current;
      testDir = await Directory.systemTemp.createTemp('fpx_repository_test_');
      Directory.current = testDir;
    });

    tearDown(() async {
      // Return to original directory and clean up
      Directory.current = originalDir;
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    group('repository add', () {
      test('adds a new repository successfully', () async {
        final result = await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        expect(result, equals(0));

        // Check config file was created
        final configFile = File(RepositoryService.configFileName);
        expect(configFile.existsSync(), isTrue);

        final content = configFile.readAsStringSync();
        expect(content, contains('test-repo:'));
        expect(content, contains('url: https://github.com/test/repo.git'));
        expect(content, contains('path: bricks'));
      });

      test('uses default path when not specified', () async {
        final result = await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        expect(result, equals(0));

        final configFile = File(RepositoryService.configFileName);
        final content = configFile.readAsStringSync();
        expect(content, contains('path: bricks'));
      });

      test('fails when name is missing', () async {
        expect(
          () => commandRunner.run([
            'repository',
            'add',
            '--url=https://github.com/test/repo.git',
          ]),
          throwsA(isA<UsageException>()),
        );
      });

      test('fails when url is missing', () async {
        expect(
          () => commandRunner.run([
            'repository',
            'add',
            '--name=test-repo',
          ]),
          throwsA(isA<UsageException>()),
        );
      });
    });

    group('repository list', () {
      test('shows configured repositories', () async {
        // Add a repository first
        await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        final result = await commandRunner.run(['repository', 'list']);
        expect(result, equals(0));
      });

      test('works with alias "ls"', () async {
        final result = await commandRunner.run(['repository', 'ls']);
        expect(result, equals(0));
      });
    });

    group('repository remove', () {
      test('removes an existing repository', () async {
        // Add a repository first
        await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        // Remove it
        final result = await commandRunner.run([
          'repository',
          'remove',
          '--name=test-repo',
        ]);

        expect(result, equals(0));

        // Verify config is updated
        final configFile = File(RepositoryService.configFileName);
        if (configFile.existsSync()) {
          final content = configFile.readAsStringSync();
          expect(content, isNot(contains('test-repo:')));
        }
      });

      test('handles non-existent repository gracefully', () async {
        final result = await commandRunner.run([
          'repository',
          'remove',
          '--name=non-existent',
        ]);

        expect(result, equals(0));
      });

      test('works with alias "rm"', () async {
        final result = await commandRunner.run([
          'repository',
          'rm',
          '--name=non-existent',
        ]);

        expect(result, equals(0));
      });

      test('fails when name is missing', () async {
        expect(
          () => commandRunner.run(['repository', 'remove']),
          throwsA(isA<UsageException>()),
        );
      });
    });

    group('repository command aliases', () {
      test('works with "repo" alias', () async {
        final result = await commandRunner.run(['repo', 'list']);
        expect(result, equals(0));
      });
    });
  });
}
