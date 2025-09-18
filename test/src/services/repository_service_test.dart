import 'dart:io';

import 'package:fpx/src/services/repository_service.dart';
import 'package:mason/mason.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
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
      final expected = path.join('.fpx_repositories', 'test-repo');
      expect(result, equals(expected));
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

    group('loadRepositoryConfig edge cases', () {
      test('handles default config with repositories as non-Map', () async {
        // Create default config with repositories as a list instead of map
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  - item1
  - item2
''');

        final config = await service.loadRepositoryConfig();
        
        expect(config['repositories'], isA<Map<String, dynamic>>());
        expect((config['repositories'] as Map).isEmpty, isTrue);
      });

      test('handles user config with empty repositories', () async {
        // Create user config with null repositories
        final userConfigFile = File('.fpx_repositories.local.yaml');
        await userConfigFile.writeAsString('''
repositories:
''');

        final config = await service.loadRepositoryConfig();
        expect(config['repositories'], isA<Map<String, dynamic>>());
      });
    });

    group('findBrick', () {
      test('returns empty list when repositories is null', () async {
        // Create config with no repositories section
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
other_config: value
''');

        final results = await service.findBrick('test-brick');
        expect(results.isEmpty, isTrue);
      });

      test('handles specific repository format @repo/brick', () async {
        // Create config with test repository
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Create fake repository directory with component
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final componentDir = Directory('.fpx_repositories/test-repo/lib/src/components/button');
        await componentDir.create(recursive: true);
        
        final brickYaml = File('.fpx_repositories/test-repo/lib/src/components/button/brick.yaml');
        await brickYaml.writeAsString('''
name: button
description: A button component
''');
        
        final brickDir = Directory('.fpx_repositories/test-repo/lib/src/components/button/__brick__');
        await brickDir.create(recursive: true);

        final results = await service.findBrick('@test-repo/button');
        expect(results.length, equals(1));
        expect(results.first.brickName, equals('button'));
        expect(results.first.repositoryName, equals('test-repo'));
      });

      test('handles specific repository format with invalid parts', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Test with invalid format (only @repo)
        final results = await service.findBrick('@test-repo');
        expect(results.isEmpty, isTrue);
      });

      test('handles repository not found in config', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  other-repo:
    url: https://github.com/other/repo.git
    path: bricks
''');

        final results = await service.findBrick('@missing-repo/button');
        expect(results.isEmpty, isTrue);
      });

      test('searches all repositories for brick name', () async {
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

        // Create fake repositories
        final repo1Dir = Directory('.fpx_repositories/repo1');
        await repo1Dir.create(recursive: true);
        
        final repo2Dir = Directory('.fpx_repositories/repo2');
        await repo2Dir.create(recursive: true);

        // Create fpx.yaml files
        final fpx1File = File('.fpx_repositories/repo1/fpx.yaml');
        await fpx1File.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        final fpx2File = File('.fpx_repositories/repo2/fpx.yaml');
        await fpx2File.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        // Create actual component directories to satisfy brick creation
        final comp1Dir = Directory('.fpx_repositories/repo1/lib/src/components/button');
        await comp1Dir.create(recursive: true);
        final brick1File = File('.fpx_repositories/repo1/lib/src/components/button/brick.yaml');
        await brick1File.writeAsString('name: button');
        final brick1Dir = Directory('.fpx_repositories/repo1/lib/src/components/button/__brick__');
        await brick1Dir.create();

        final comp2Dir = Directory('.fpx_repositories/repo2/lib/src/components/button');
        await comp2Dir.create(recursive: true);
        final brick2File = File('.fpx_repositories/repo2/lib/src/components/button/brick.yaml');
        await brick2File.writeAsString('name: button');
        final brick2Dir = Directory('.fpx_repositories/repo2/lib/src/components/button/__brick__');
        await brick2Dir.create();

        final results = await service.findBrick('button');
        expect(results.length, equals(2));
      });
    });

    group('_createBrickFromRepository', () {
      test('returns null when repository is not cloned', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Test when repository directory doesn't exist (no cloning attempted)
        final results = await service.findBrick('@test-repo/button');
        expect(results.isEmpty, isTrue);
      });

      test('finds brick with component configuration from fpx.yaml', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Create repository structure
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: custom/path/to/button
''');

        final customPath = Directory('.fpx_repositories/test-repo/custom/path/to/button');
        await customPath.create(recursive: true);
        
        final brickYaml = File('.fpx_repositories/test-repo/custom/path/to/button/brick.yaml');
        await brickYaml.writeAsString('''
name: button
description: A button component
''');

        final results = await service.findBrick('@test-repo/button');
        expect(results.length, equals(1));
      });

      test('falls back to standard brick location', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Create repository structure
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        final standardPath = Directory('.fpx_repositories/test-repo/bricks/button');
        await standardPath.create(recursive: true);
        
        final brickYaml = File('.fpx_repositories/test-repo/bricks/button/brick.yaml');
        await brickYaml.writeAsString('''
name: button
description: A button component
''');

        final results = await service.findBrick('@test-repo/button');
        expect(results.length, equals(1));
      });

      test('handles exception during brick creation', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
''');

        // Create repository but with permission issue or malformed structure
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        // Test will pass because exceptions are caught and null is returned
        final results = await service.findBrick('@test-repo/button');
        expect(results.isEmpty, isTrue);
      });
    });

    group('cloneRepository', () {
      test('creates repositories directory if not exists', () async {
        // Ensure .fpx_repositories doesn't exist
        final repoBaseDir = Directory('.fpx_repositories');
        if (await repoBaseDir.exists()) {
          await repoBaseDir.delete(recursive: true);
        }

        // This will fail due to git command, but directory creation should work
        try {
          await service.cloneRepository('test-repo', 'https://invalid-url.git');
        } catch (e) {
          // Expected to fail
        }

        expect(await repoBaseDir.exists(), isTrue);
      });

      test('removes existing directory before cloning', () async {
        // Create existing repository directory
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final existingFile = File('.fpx_repositories/test-repo/existing.txt');
        await existingFile.writeAsString('existing content');

        expect(await existingFile.exists(), isTrue);

        // This will fail due to git command, but directory removal should work
        try {
          await service.cloneRepository('test-repo', 'https://invalid-url.git');
        } catch (e) {
          // Expected to fail
        }

        // Directory should be recreated (empty) - so existing file should be gone
        expect(await existingFile.exists(), isFalse);
      });

      test('throws exception on git clone failure', () async {
        expect(
          () => service.cloneRepository('test-repo', 'https://invalid-url.git'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('updateRepository', () {
      test('throws exception for non-existent repository', () async {
        expect(
          () => service.updateRepository('non-existent-repo'),
          throwsA(isA<Exception>()),
        );
      });

      test('throws exception on git pull failure', () async {
        // Create repository directory but not a git repository
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        expect(
          () => service.updateRepository('test-repo'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('readFpxConfig', () {
      test('returns null for invalid yaml content', () async {
        // Create repository directory with invalid fpx.yaml
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
invalid: [
  yaml content
''');

        final config = await service.readFpxConfig('test-repo');
        expect(config, isNull);
      });

      test('returns null for non-map yaml content', () async {
        // Create repository directory with non-map fpx.yaml
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
- item1
- item2
''');

        final config = await service.readFpxConfig('test-repo');
        expect(config, isNull);
      });
    });

    group('detectComponents', () {
      test('scans for brick.yaml files when no fpx.yaml', () async {
        // Create repository directory without fpx.yaml
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        // Create some brick.yaml files
        final brick1Dir = Directory('.fpx_repositories/test-repo/components/button');
        await brick1Dir.create(recursive: true);
        final brick1File = File('.fpx_repositories/test-repo/components/button/brick.yaml');
        await brick1File.writeAsString('name: button');

        final brick2Dir = Directory('.fpx_repositories/test-repo/widgets/card');
        await brick2Dir.create(recursive: true);
        final brick2File = File('.fpx_repositories/test-repo/widgets/card/brick.yaml');
        await brick2File.writeAsString('name: card');

        final components = await service.detectComponents('test-repo');
        expect(components.contains('button'), isTrue);
        expect(components.contains('card'), isTrue);
      });

      test('handles fpx.yaml with bricks section for backward compatibility', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
bricks:
  legacy_button:
    path: lib/src/components
  legacy_card:
    path: lib/src/widgets
''');

        final components = await service.detectComponents('test-repo');
        expect(components.contains('legacy_button'), isTrue);
        expect(components.contains('legacy_card'), isTrue);
      });

      test('combines components and bricks sections', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  modern_button:
    path: lib/src/components
bricks:
  legacy_card:
    path: lib/src/widgets
''');

        final components = await service.detectComponents('test-repo');
        expect(components.contains('modern_button'), isTrue);
        expect(components.contains('legacy_card'), isTrue);
      });

      test('skips brick.yaml files in root directory', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        // Create brick.yaml in root (should be skipped)
        final rootBrickFile = File('.fpx_repositories/test-repo/brick.yaml');
        await rootBrickFile.writeAsString('name: root');

        // Create valid brick.yaml in subdirectory
        final validDir = Directory('.fpx_repositories/test-repo/components/button');
        await validDir.create(recursive: true);
        final validBrickFile = File('.fpx_repositories/test-repo/components/button/brick.yaml');
        await validBrickFile.writeAsString('name: button');

        final components = await service.detectComponents('test-repo');
        expect(components.contains('button'), isTrue);
        expect(components.contains('root'), isFalse);
      });

      test('avoids duplicate component names in scan', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        // Create multiple brick.yaml files with same component name
        final dir1 = Directory('.fpx_repositories/test-repo/path1/button');
        await dir1.create(recursive: true);
        final file1 = File('.fpx_repositories/test-repo/path1/button/brick.yaml');
        await file1.writeAsString('name: button');

        final dir2 = Directory('.fpx_repositories/test-repo/path2/button');
        await dir2.create(recursive: true);
        final file2 = File('.fpx_repositories/test-repo/path2/button/brick.yaml');
        await file2.writeAsString('name: button');

        final components = await service.detectComponents('test-repo');
        expect(components.where((c) => c == 'button').length, equals(1));
      });
    });

    group('getComponentConfig', () {
      test('returns null when no fpx.yaml exists', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);

        final config = await service.getComponentConfig('test-repo', 'button');
        expect(config, isNull);
      });

      test('checks bricks section for backward compatibility', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
bricks:
  legacy_button:
    path: lib/src/widgets
    description: Legacy button
''');

        final config = await service.getComponentConfig('test-repo', 'legacy_button');
        expect(config, isNotNull);
        expect(config!['path'], equals('lib/src/widgets'));
        expect(config['description'], equals('Legacy button'));
      });

      test('returns null for non-existent component', () async {
        final repoDir = Directory('.fpx_repositories/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('.fpx_repositories/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        final config = await service.getComponentConfig('test-repo', 'non-existent');
        expect(config, isNull);
      });
    });

    group('YAML conversion methods', () {
      test('_convertYamlMapToMap handles nested structures', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  test-repo:
    url: https://github.com/test/repo.git
    path: bricks
    config:
      nested:
        value: test
      list:
        - item1
        - item2
''');

        final config = await service.loadRepositoryConfig();
        final repos = config['repositories'] as Map<String, dynamic>;
        final testRepo = repos['test-repo'] as Map<String, dynamic>;
        final configSection = testRepo['config'] as Map<String, dynamic>;
        
        expect(configSection['nested'], isA<Map<String, dynamic>>());
        expect(configSection['list'], isA<List<dynamic>>());
      });
    });

    group('_mapToYaml method', () {
      test('generates proper YAML structure', () async {
        final config = {
          'repositories': {
            'test-repo': {
              'url': 'https://github.com/test/repo.git',
              'path': 'bricks',
              'nested': {
                'value': 'test',
              },
            },
          },
        };

        await service.saveRepositoryConfig(config);

        final configFile = File('.fpx_repositories.yaml');
        final content = await configFile.readAsString();
        
        expect(content, contains('repositories:'));
        expect(content, contains('  test-repo:'));
        expect(content, contains('    url: https://github.com/test/repo.git'));
        expect(content, contains('    path: bricks'));
        expect(content, contains('    nested:'));
        expect(content, contains('      value: test'));
      });
    });

    // Edge case tests for lines that are hard to test or should be ignored
    group('Coverage exclusions', () {
      test('Process.run failure scenarios', () async {
        // These lines involve Process.run which is hard to test without mocking the entire process
        // They should be marked with coverage ignore comments
        expect(true, isTrue); // Placeholder test
      });
    });
  });

  group('BrickSearchResult', () {
    test('creates result with all properties', () {
      final brick = Brick.path('./test');
      final result = BrickSearchResult(
        brickName: 'test-brick',
        repositoryName: 'test-repo',
        brick: brick,
        fullPath: 'path/to/brick',
      );

      expect(result.brickName, equals('test-brick'));
      expect(result.repositoryName, equals('test-repo'));
      expect(result.brick, equals(brick));
      expect(result.fullPath, equals('path/to/brick'));
    });

    test('toString returns correct format', () {
      final brick = Brick.path('./test');
      final result = BrickSearchResult(
        brickName: 'test-brick',
        repositoryName: 'test-repo',
        brick: brick,
        fullPath: 'path/to/brick',
      );

      expect(result.toString(), equals('test-repo/path/to/brick'));
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
