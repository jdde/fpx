import 'dart:io';

import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('RepositoryService', () {
    late Logger logger;
    late RepositoryService service;
    late Directory testDir;
    late Directory originalDir;

    setUp(() async {
      logger = _MockLogger();
      service = RepositoryService(logger: logger);

      // Save original directory
      originalDir = Directory.current;

      // Create a temporary test directory
      testDir = await Directory.systemTemp.createTemp('fpx_repo_test_');
      Directory.current = testDir;

      // Clean up any existing config files
      final configFile = File('.fpx_repositories.yaml');
      if (await configFile.exists()) {
        await configFile.delete();
      }
      final userConfigFile = File('.fpx_repositories.local.yaml');
      if (await userConfigFile.exists()) {
        await userConfigFile.delete();
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

    test('can be instantiated with logger', () {
      final service = RepositoryService(logger: logger);
      expect(service, isNotNull);
    });

    test('can be instantiated without logger', () {
      final service = RepositoryService();
      expect(service, isNotNull);
    });

    test('loadRepositoryConfig returns empty config when no files exist', () async {
      final config = await service.loadRepositoryConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['repositories'], isA<Map<String, dynamic>>());
      expect((config['repositories'] as Map).isEmpty, isTrue);
    });

    test('loadRepositoryConfig loads from default config file', () async {
      // Create a default config file
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

      final config = await service.loadRepositoryConfig();
      
      expect(config['repositories'], isA<Map<String, dynamic>>());
      final repos = config['repositories'] as Map<String, dynamic>;
      expect(repos.containsKey('test-repo'), isTrue);
      expect(repos['test-repo']['url'], equals('https://github.com/test/repo.git'));
      expect(repos['test-repo']['path'], equals('bricks'));
    });

    test('loadRepositoryConfig merges default and user configs', () async {
      // Create default config
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('''
repositories:
  default-repo:
    url: https://github.com/default/repo.git
    path: bricks
''');

      // Create user config
      final userConfigFile = File('.fpx_repositories.local.yaml');
      await userConfigFile.writeAsString('''
repositories:
  user-repo:
    url: https://github.com/user/repo.git
    path: components
''');

      final config = await service.loadRepositoryConfig();
      
      expect(config['repositories'], isA<Map<String, dynamic>>());
      final repos = config['repositories'] as Map<String, dynamic>;
      expect(repos.containsKey('default-repo'), isTrue);
      expect(repos.containsKey('user-repo'), isTrue);
      expect(repos['default-repo']['url'], equals('https://github.com/default/repo.git'));
      expect(repos['user-repo']['url'], equals('https://github.com/user/repo.git'));
    });

    test('loadRepositoryConfig handles invalid yaml gracefully', () async {
      // Create invalid YAML config
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('''
repositories: [
  invalid yaml content
''');

      final config = await service.loadRepositoryConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['repositories'], isA<Map<String, dynamic>>());
      expect((config['repositories'] as Map).isEmpty, isTrue);
    });

    test('loadRepositoryConfig handles empty file', () async {
      // Create empty config file
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('');

      final config = await service.loadRepositoryConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['repositories'], isA<Map<String, dynamic>>());
      expect((config['repositories'] as Map).isEmpty, isTrue);
    });

    test('loadRepositoryConfig handles non-map yaml content', () async {
      // Create non-map YAML config
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('''
- item1
- item2
''');

      final config = await service.loadRepositoryConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['repositories'], isA<Map<String, dynamic>>());
      expect((config['repositories'] as Map).isEmpty, isTrue);
    });

    test('getRepositories returns repository info from config', () async {
      // Create config with repositories
      final configFile = File('.fpx_repositories.yaml');
      await configFile.writeAsString('''
repositories:
  repo1:
    url: https://github.com/repo1/repo.git
    path: bricks
  repo2:
    url: https://github.com/repo2/repo.git
    path: components
''');

      final repositories = await service.getRepositories();
      
      expect(repositories.length, equals(2));
      expect(repositories.containsKey('repo1'), isTrue);
      expect(repositories.containsKey('repo2'), isTrue);
      
      final repo1 = repositories['repo1']!;
      expect(repo1.name, equals('repo1'));
      expect(repo1.url, equals('https://github.com/repo1/repo.git'));
      expect(repo1.path, equals('bricks'));
      
      final repo2 = repositories['repo2']!;
      expect(repo2.name, equals('repo2'));
      expect(repo2.url, equals('https://github.com/repo2/repo.git'));
      expect(repo2.path, equals('components'));
    });

    test('getRepositories returns empty map when no repositories configured', () async {
      final repositories = await service.getRepositories();
      expect(repositories.isEmpty, isTrue);
    });

    test('saveRepositoryConfig writes config to default file', () async {
      final config = {
        'repositories': {
          'new-repo': {
            'url': 'https://github.com/new/repo.git',
            'path': 'widgets',
          },
        },
      };

      await service.saveRepositoryConfig(config);

      final configFile = File('.fpx_repositories.yaml');
      expect(await configFile.exists(), isTrue);
      
      final content = await configFile.readAsString();
      expect(content.contains('new-repo'), isTrue);
      expect(content.contains('https://github.com/new/repo.git'), isTrue);
      expect(content.contains('widgets'), isTrue);
    });

    test('isRepositoryCloned returns false for non-existent repository', () async {
      final result = await service.isRepositoryCloned('non-existent-repo');
      expect(result, isFalse);
    });

    test('isRepositoryCloned returns true for existing repository', () async {
      // Create a fake repository directory
      final repoDir = Directory('.fpx_repositories/test-repo');
      await repoDir.create(recursive: true);

      final result = await service.isRepositoryCloned('test-repo');
      expect(result, isTrue);
    });

    test('getRepositoryPath returns correct path', () {
      final result = service.getRepositoryPath('test-repo');
      expect(result, equals('.fpx_repositories/test-repo'));
    });

    test('readFpxConfig returns null for non-existent repository', () async {
      final config = await service.readFpxConfig('non-existent-repo');
      expect(config, isNull);
    });

    test('readFpxConfig returns null for repository without fpx.yaml', () async {
      // Create repository directory without fpx.yaml
      final repoDir = Directory('.fpx_repositories/test-repo');
      await repoDir.create(recursive: true);

      final config = await service.readFpxConfig('test-repo');
      expect(config, isNull);
    });

    test('readFpxConfig returns config when fpx.yaml exists', () async {
      // Create repository directory with fpx.yaml
      final repoDir = Directory('.fpx_repositories/test-repo');
      await repoDir.create(recursive: true);
      
      final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
      await fpxFile.writeAsString('''
components:
  button:
    path: lib/src/components
variables:
  foundation:
    color:
      path: lib/src/foundation/ui_colors.dart
''');

      final config = await service.readFpxConfig('test-repo');
      expect(config, isNotNull);
      expect(config!['components'], isA<Map<dynamic, dynamic>>());
      expect(config['variables'], isA<Map<dynamic, dynamic>>());
    });

    test('initializeDefaultRepositories can be called', () async {
      // Just test that the method exists and can be called
      await service.initializeDefaultRepositories();
      // Test passes if no exception is thrown
    });

    test('findBrick returns empty list when no repositories configured', () async {
      final results = await service.findBrick('test-brick');
      expect(results.isEmpty, isTrue);
    });

    test('detectComponents returns empty list for non-existent repository', () async {
      final components = await service.detectComponents('non-existent-repo');
      expect(components.isEmpty, isTrue);
    });
  });

  group('RepositoryInfo', () {
    test('can be created with required parameters', () {
      const info = RepositoryInfo(
        name: 'test-repo',
        url: 'https://github.com/test/repo.git',
        path: 'bricks',
      );

      expect(info.name, equals('test-repo'));
      expect(info.url, equals('https://github.com/test/repo.git'));
      expect(info.path, equals('bricks'));
    });
  });
}
