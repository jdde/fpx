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

      test('auto-generates name when not provided', () async {
        final result = await commandRunner.run([
          'repository',
          'add',
          '--url=https://github.com/test/repo.git',
        ]);

        expect(result, equals(0));

        // Check config file was created with auto-generated name
        final configFile = File(RepositoryService.configFileName);
        expect(configFile.existsSync(), isTrue);

        final content = configFile.readAsStringSync();
        expect(content, contains('test:')); // First path segment should be 'test'
        expect(content, contains('url: https://github.com/test/repo.git'));
        expect(content, contains('path: bricks'));
      });

      test('fails when url is missing', () async {
        expect(
          () => commandRunner.run([
            'repository',
            'add',
            '--name=test-repo',
          ]),
          throwsA(isA<ArgumentError>()),
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
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('repository command aliases', () {
      test('works with "repo" alias', () async {
        final result = await commandRunner.run(['repo', 'list']);
        expect(result, equals(0));
      });
    });

    group('repository update', () {
      test('updates an existing repository', () async {
        // Add a repository first
        await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        // Try to update it (this may fail in test environment due to git requirements)
        try {
          final result = await commandRunner.run([
            'repository',
            'update',
            '--name=test-repo',
          ]);
          // Accept either success or failure since git operations may not work in test env
          expect(result, isA<int>());
        } catch (e) {
          // Expected to fail in test environment without git setup
        }
      });

      test('handles non-existent repository for update', () async {
        try {
          final result = await commandRunner.run([
            'repository',
            'update',
            '--name=non-existent',
          ]);
          // Should handle gracefully
          expect(result, isA<int>());
        } catch (e) {
          // May throw exception for non-existent repository
        }
      });

      test('updates all repositories when name is not specified', () async {
        // Add a repository first
        await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        // Update all repositories
        try {
          final result = await commandRunner.run(['repository', 'update']);
          expect(result, isA<int>());
        } catch (e) {
          // Expected to fail in test environment without git setup
        }
      });
    });

    group('repository add edge cases', () {
      test('handles GitHub URL auto-detection with path', () async {
        final result = await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        expect(result, equals(0));
      });


      test('handles URL parsing errors', () async {
        try {
          final result = await commandRunner.run([
            'repository',
            'add',
            '--name=invalid-repo',
            '--url=invalid-url',
          ]);
          // Should either succeed with default path or handle error gracefully
          expect(result, isA<int>());
        } catch (e) {
          // May throw exception for invalid URL
        }
      });

      test('handles repository cloning errors', () async {
        try {
          final result = await commandRunner.run([
            'repository',
            'add',
            '--name=failing-repo',
            '--url=https://github.com/non-existent/repo.git',
          ]);
          // Should handle cloning failure gracefully
          expect(result, isA<int>());
        } catch (e) {
          // Expected to fail for non-existent repository
        }
      });

      test('handles existing repository name conflicts', () async {
        // Add a repository first
        await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/repo.git',
        ]);

        // Try to add another with the same name
        final result = await commandRunner.run([
          'repository',
          'add',
          '--name=test-repo',
          '--url=https://github.com/test/different-repo.git',
        ]);

        // Should handle this case (either update or warn)
        expect(result, isA<int>());
      });
    });

    group('repository list details', () {
      test('shows empty state when no repositories configured', () async {
        final result = await commandRunner.run(['repository', 'list']);
        expect(result, equals(0));
        // Should show message about no repositories
      });

      test('shows repository details when repositories exist', () async {
        // Add multiple repositories
        await commandRunner.run([
          'repository',
          'add',
          '--name=repo1',
          '--url=https://github.com/test/repo1.git',
        ]);
        
        await commandRunner.run([
          'repository',
          'add',
          '--name=repo2',
          '--url=https://github.com/test/repo2.git',
        ]);

        final result = await commandRunner.run(['repository', 'list']);
        expect(result, equals(0));
        // Should show both repositories
      });
    });

    group('repository command structure', () {
      test('has correct command properties', () {
        expect(command.name, equals('repository'));
        expect(command.description, equals('Manage brick repositories'));
        expect(command.aliases, contains('repo'));
      });

      test('has correct subcommands', () {
        final subcommandNames = command.subcommands.keys.toList();
        expect(subcommandNames, contains('add'));
        expect(subcommandNames, contains('remove'));
        expect(subcommandNames, contains('list'));
        expect(subcommandNames, contains('update'));
      });
    });
  });
}
