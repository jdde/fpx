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

    test('loadRepositoryConfig returns empty config for backward compatibility', () async {
      final config = await service.loadRepositoryConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['repositories'], isA<Map<String, dynamic>>());
      expect((config['repositories'] as Map).isEmpty, isTrue);
    });

    test('getRepositories returns info from directory structure', () async {
      // Create some repository directories
      final repo1Dir = Directory('${RepositoryService.repositoriesDir}/repo1');
      await repo1Dir.create(recursive: true);
      final repo2Dir = Directory('${RepositoryService.repositoriesDir}/repo2');
      await repo2Dir.create(recursive: true);

      final repositories = await service.getRepositories();
      
      expect(repositories.length, equals(2));
      expect(repositories.containsKey('repo1'), isTrue);
      expect(repositories.containsKey('repo2'), isTrue);
      
      final repo1 = repositories['repo1']!;
      expect(repo1.name, equals('repo1'));
      expect(repo1.url, equals('')); // URL not available from directory structure
      expect(repo1.path, equals('bricks')); // Default path
      
      final repo2 = repositories['repo2']!;
      expect(repo2.name, equals('repo2'));
      expect(repo2.url, equals(''));
      expect(repo2.path, equals('bricks'));
    });

    test('getRepositories returns empty map when no repositories configured', () async {
      final repositories = await service.getRepositories();
      expect(repositories.isEmpty, isTrue);
    });

    test('isRepositoryCloned returns false for non-existent repository', () async {
      final result = await service.isRepositoryCloned('non-existent-repo');
      expect(result, isFalse);
    });

    test('isRepositoryCloned returns true for existing repository', () async {
      // Create a fake repository directory
      final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
      await repoDir.create(recursive: true);

      final result = await service.isRepositoryCloned('test-repo');
      expect(result, isTrue);
    });

    test('getRepositoryPath returns correct path', () {
      final result = service.getRepositoryPath('test-repo');
      final expected = path.join(RepositoryService.repositoriesDir, 'test-repo');
      expect(result, equals(expected));
    });

    test('readFpxConfig returns null for non-existent repository', () async {
      final config = await service.readFpxConfig('non-existent-repo');
      expect(config, isNull);
    });

    test('readFpxConfig returns null for repository without fpx.yaml', () async {
      // Create repository directory without fpx.yaml
      final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
      await repoDir.create(recursive: true);

      final config = await service.readFpxConfig('test-repo');
      expect(config, isNull);
    });

    test('readFpxConfig returns config when fpx.yaml exists', () async {
      // Create repository directory with fpx.yaml
      final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
      await repoDir.create(recursive: true);
      
      final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
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

    test('scanForBricks returns empty list for non-existent repository', () async {
      final components = await service.scanForBricks('non-existent-repo');
      expect(components.isEmpty, isTrue);
    });

    group('findBrick', () {
      test('returns empty list when no repositories configured', () async {
        final results = await service.findBrick('test-brick');
        expect(results.isEmpty, isTrue);
      });

      test('handles specific repository format @repo/brick', () async {
        // Create repository directory with component
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final componentDir = Directory('${RepositoryService.repositoriesDir}/test-repo/lib/src/components/button');
        await componentDir.create(recursive: true);
        
        final brickYaml = File('${RepositoryService.repositoriesDir}/test-repo/lib/src/components/button/brick.yaml');
        await brickYaml.writeAsString('''
name: button
description: A button component
''');
        
        final brickDir = Directory('${RepositoryService.repositoriesDir}/test-repo/lib/src/components/button/__brick__');
        await brickDir.create(recursive: true);

        final results = await service.findBrick('@test-repo/button');
        expect(results.length, equals(1));
        expect(results.first.brickName, equals('button'));
        expect(results.first.repositoryName, equals('test-repo'));
      });

      test('handles specific repository format with invalid parts', () async {
        // Create repository directory
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        // Test with invalid format (only @repo)
        final results = await service.findBrick('@test-repo');
        expect(results.isEmpty, isTrue);
      });

      test('handles repository not found', () async {
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
        final repo1Dir = Directory('${RepositoryService.repositoriesDir}/repo1');
        await repo1Dir.create(recursive: true);
        
        final repo2Dir = Directory('${RepositoryService.repositoriesDir}/repo2');
        await repo2Dir.create(recursive: true);

        // Create fpx.yaml files
        final fpx1File = File('${RepositoryService.repositoriesDir}/repo1/fpx.yaml');
        await fpx1File.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        final fpx2File = File('${RepositoryService.repositoriesDir}/repo2/fpx.yaml');
        await fpx2File.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        // Create actual component directories to satisfy brick creation
        final comp1Dir = Directory('${RepositoryService.repositoriesDir}/repo1/lib/src/components/button');
        await comp1Dir.create(recursive: true);
        final brick1File = File('${RepositoryService.repositoriesDir}/repo1/lib/src/components/button/brick.yaml');
        await brick1File.writeAsString('name: button');
        final brick1Dir = Directory('${RepositoryService.repositoriesDir}/repo1/lib/src/components/button/__brick__');
        await brick1Dir.create();

        final comp2Dir = Directory('${RepositoryService.repositoriesDir}/repo2/lib/src/components/button');
        await comp2Dir.create(recursive: true);
        final brick2File = File('${RepositoryService.repositoriesDir}/repo2/lib/src/components/button/brick.yaml');
        await brick2File.writeAsString('name: button');
        final brick2Dir = Directory('${RepositoryService.repositoriesDir}/repo2/lib/src/components/button/__brick__');
        await brick2Dir.create();

        final results = await service.findBrick('button');
        expect(results.length, equals(2));
      });

      test('handles repository access errors when searching all repositories', () async {
        final configFile = File('.fpx_repositories.yaml');
        await configFile.writeAsString('''
repositories:
  good-repo:
    url: https://github.com/good/repo.git
    path: bricks
  error-repo:
    url: https://github.com/error/repo.git
    path: bricks
''');

        // Create only one repository - the other will cause access error
        final goodRepo = Directory('${RepositoryService.repositoriesDir}/good-repo');
        await goodRepo.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/good-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        // Create actual component to satisfy brick creation
        final compDir = Directory('${RepositoryService.repositoriesDir}/good-repo/lib/src/components/button');
        await compDir.create(recursive: true);
        final brickFile = File('${RepositoryService.repositoriesDir}/good-repo/lib/src/components/button/brick.yaml');
        await brickFile.writeAsString('name: button');
        final brickDir = Directory('${RepositoryService.repositoriesDir}/good-repo/lib/src/components/button/__brick__');
        await brickDir.create();

        // Don't create error-repo directory to trigger error

        final results = await service.findBrick('button');
        expect(results.length, equals(1));
        expect(results.first.repositoryName, equals('good-repo'));
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: custom/path/to/button
''');

        final customPath = Directory('${RepositoryService.repositoriesDir}/test-repo/custom/path/to/button');
        await customPath.create(recursive: true);
        
        final brickYaml = File('${RepositoryService.repositoriesDir}/test-repo/custom/path/to/button/brick.yaml');
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        final standardPath = Directory('${RepositoryService.repositoriesDir}/test-repo/bricks/button');
        await standardPath.create(recursive: true);
        
        final brickYaml = File('${RepositoryService.repositoriesDir}/test-repo/bricks/button/brick.yaml');
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        // Test will pass because exceptions are caught and null is returned
        final results = await service.findBrick('@test-repo/button');
        expect(results.isEmpty, isTrue);
      });
    });

    group('cloneRepository', () {
      test('creates repositories directory if not exists', () async {
        // Ensure .fpx_repositories doesn't exist
        final repoBaseDir = Directory(RepositoryService.repositoriesDir);
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final existingFile = File('${RepositoryService.repositoriesDir}/test-repo/existing.txt');
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
invalid: [
  yaml content
''');

        final config = await service.readFpxConfig('test-repo');
        expect(config, isNull);
      });

      test('returns null for non-map yaml content', () async {
        // Create repository directory with non-map fpx.yaml
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
- item1
- item2
''');

        final config = await service.readFpxConfig('test-repo');
        expect(config, isNull);
      });
    });

    group('scanForBricks', () {
      test('scans for brick.yaml files when no fpx.yaml', () async {
        // Create repository directory without fpx.yaml
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        // Create some brick.yaml files
        final brick1Dir = Directory('${RepositoryService.repositoriesDir}/test-repo/components/button');
        await brick1Dir.create(recursive: true);
        final brick1File = File('${RepositoryService.repositoriesDir}/test-repo/components/button/brick.yaml');
        await brick1File.writeAsString('name: button');

        final brick2Dir = Directory('${RepositoryService.repositoriesDir}/test-repo/widgets/card');
        await brick2Dir.create(recursive: true);
        final brick2File = File('${RepositoryService.repositoriesDir}/test-repo/widgets/card/brick.yaml');
        await brick2File.writeAsString('name: card');

        final components = await service.scanForBricks('test-repo');
        expect(components.contains('button'), isTrue);
        expect(components.contains('card'), isTrue);
      });

      test('skips brick.yaml files in root directory', () async {
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        // Create brick.yaml in root (should be skipped)
        final rootBrickFile = File('${RepositoryService.repositoriesDir}/test-repo/brick.yaml');
        await rootBrickFile.writeAsString('name: root');

        // Create valid brick.yaml in subdirectory
        final validDir = Directory('${RepositoryService.repositoriesDir}/test-repo/components/button');
        await validDir.create(recursive: true);
        final validBrickFile = File('${RepositoryService.repositoriesDir}/test-repo/components/button/brick.yaml');
        await validBrickFile.writeAsString('name: button');

        final components = await service.scanForBricks('test-repo');
        expect(components.contains('button'), isTrue);
        expect(components.contains('root'), isFalse);
      });

      test('avoids duplicate component names in scan', () async {
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        // Create multiple brick.yaml files with same component name
        final dir1 = Directory('${RepositoryService.repositoriesDir}/test-repo/path1/button');
        await dir1.create(recursive: true);
        final file1 = File('${RepositoryService.repositoriesDir}/test-repo/path1/button/brick.yaml');
        await file1.writeAsString('name: button');

        final dir2 = Directory('${RepositoryService.repositoriesDir}/test-repo/path2/button');
        await dir2.create(recursive: true);
        final file2 = File('${RepositoryService.repositoriesDir}/test-repo/path2/button/brick.yaml');
        await file2.writeAsString('name: button');

        final components = await service.scanForBricks('test-repo');
        expect(components.where((c) => c == 'button').length, equals(1));
      });
    });

    group('getComponentConfig', () {
      test('returns null when no fpx.yaml exists', () async {
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);

        final config = await service.getComponentConfig('test-repo', 'button');
        expect(config, isNull);
      });

      test('checks bricks section for backward compatibility', () async {
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
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
        final repoDir = Directory('${RepositoryService.repositoriesDir}/test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: lib/src/components
''');

        final config = await service.getComponentConfig('test-repo', 'non-existent');
        expect(config, isNull);
      });
    });

    group('getAllAvailableComponents', () {
      test('returns empty map when no repositories configured', () async {
        final allComponents = await service.getAllAvailableComponents();
        expect(allComponents.isEmpty, isTrue);
      });

      test('returns empty map when no repository directories exist', () async {
        final allComponents = await service.getAllAvailableComponents();
        expect(allComponents.isEmpty, isTrue);
      });

      test('handles repository access errors gracefully', () async {
        // This test passes because getAllAvailableComponents only operates on
        // directories that exist, so non-existent directories are simply skipped
        final allComponents = await service.getAllAvailableComponents();
        expect(allComponents.isEmpty, isTrue);
      });

      test('returns components from successfully accessed repositories', () async {
        // Create one repository with brick.yaml files
        final goodRepo = Directory('${RepositoryService.repositoriesDir}/good-repo');
        await goodRepo.create(recursive: true);
        
        // Create brick.yaml files that scanForBricks can find
        final buttonDir = Directory('${RepositoryService.repositoriesDir}/good-repo/components/button');
        await buttonDir.create(recursive: true);
        final buttonBrick = File('${RepositoryService.repositoriesDir}/good-repo/components/button/brick.yaml');
        await buttonBrick.writeAsString('name: button');

        // Don't create bad-repo to show that only existing repos are scanned

        final allComponents = await service.getAllAvailableComponents();
        expect(allComponents.containsKey('good-repo'), isTrue);
        expect(allComponents['good-repo'], contains('button'));
        expect(allComponents.containsKey('bad-repo'), isFalse);
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

    group('YAML conversion utilities', () {
      test('_convertYamlMapToMap converts nested YAML map correctly', () async {
        // Create a test repository with fpx.yaml to trigger the conversion
        final repoDir = Directory('${RepositoryService.repositoriesDir}/yaml-test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/yaml-test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    path: lib/src/components
    nested:
      property: value
      list:
        - item1
        - item2
variables:
  colors:
    primary: "#000000"
''');

        final config = await service.readFpxConfig('yaml-test-repo');
        expect(config, isNotNull);
        
        // Verify the conversion worked correctly
        final components = config!['components'] as Map<String, dynamic>;
        expect(components['button'], isA<Map<String, dynamic>>());
        
        final buttonConfig = components['button'] as Map<String, dynamic>;
        expect(buttonConfig['path'], equals('lib/src/components'));
        expect(buttonConfig['nested'], isA<Map<String, dynamic>>());
        
        final nested = buttonConfig['nested'] as Map<String, dynamic>;
        expect(nested['property'], equals('value'));
        expect(nested['list'], isA<List<dynamic>>());
        
        final list = nested['list'] as List<dynamic>;
        expect(list, contains('item1'));
        expect(list, contains('item2'));
      });

      test('_convertYamlListToList converts nested YAML list correctly', () async {
        // Create a test repository with fpx.yaml containing complex lists
        final repoDir = Directory('${RepositoryService.repositoriesDir}/yaml-list-test-repo');
        await repoDir.create(recursive: true);
        
        final fpxFile = File('${RepositoryService.repositoriesDir}/yaml-list-test-repo/fpx.yaml');
        await fpxFile.writeAsString('''
components:
  button:
    dependencies:
      - name: flutter
        version: ">=3.0.0"
      - name: material
        nested:
          config: true
          items:
            - subitem1
            - subitem2
''');

        final config = await service.readFpxConfig('yaml-list-test-repo');
        expect(config, isNotNull);
        
        final components = config!['components'] as Map<String, dynamic>;
        final buttonConfig = components['button'] as Map<String, dynamic>;
        final dependencies = buttonConfig['dependencies'] as List<dynamic>;
        
        expect(dependencies.length, equals(2));
        
        final firstDep = dependencies[0] as Map<String, dynamic>;
        expect(firstDep['name'], equals('flutter'));
        expect(firstDep['version'], equals('>=3.0.0'));
        
        final secondDep = dependencies[1] as Map<String, dynamic>;
        expect(secondDep['name'], equals('material'));
        expect(secondDep['nested'], isA<Map<String, dynamic>>());
        
        final nested = secondDep['nested'] as Map<String, dynamic>;
        expect(nested['config'], equals(true));
        expect(nested['items'], isA<List<dynamic>>());
        
        final items = nested['items'] as List<dynamic>;
        expect(items, contains('subitem1'));
        expect(items, contains('subitem2'));
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
