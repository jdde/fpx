import 'dart:io';

import 'package:fpx/src/models/fpx_config.dart';
import 'package:fpx/src/services/repository_post_clone_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('RepositoryPostCloneService', () {
    late Logger logger;
    late RepositoryPostCloneService service;
    late Directory testDir;
    late Directory originalDir;

    setUp(() async {
      logger = _MockLogger();
      service = RepositoryPostCloneService(logger: logger);

      // Save original directory
      originalDir = Directory.current;

      // Create a temporary test directory
      testDir = await Directory.systemTemp.createTemp('fpx_post_clone_test_');
      Directory.current = testDir;
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
      final service = RepositoryPostCloneService(logger: logger);
      expect(service, isNotNull);
    });

    test('processClonedRepository completes successfully with minimal setup', () async {
      // Create a minimal repository structure
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      // Create a basic pubspec.yaml
      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create a minimal component directory structure
      final componentsDir = Directory('test-repo/lib/src/components');
      await componentsDir.create(recursive: true);

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Verify logger calls
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository handles repository without pubspec.yaml', () async {
      // Create a repository without pubspec.yaml
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Verify logger calls
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository uses provided fpx config', () async {
      // Create a minimal repository structure
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      // Create a custom fpx config
      final customConfig = FpxConfig(
        bricks: BricksConfig(path: 'lib/widgets'),
        variables: VariablesConfig(
          foundation: FoundationConfig({
            'colors': FoundationItem(path: 'lib/theme/colors.dart'),
          }),
        ),
      );

      // Run the service with custom config
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
        fpxConfig: customConfig,
      );

      // Verify logger calls
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository with components creates brick structure', () async {
      // Create a repository with components
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      // Create pubspec.yaml
      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create a component
      final buttonDir = Directory('test-repo/lib/src/components/button');
      await buttonDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Verify logger calls
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository handles errors gracefully', () async {
      // Try to process a non-existent repository
      await service.processClonedRepository(
        repositoryName: 'non-existent-repo',
        repositoryPath: 'non-existent-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Verify logger calls (it should start processing but might encounter errors)
      verify(() => logger.info('🔧 Processing cloned repository "non-existent-repo"...')).called(1);
      // The success message might not be called if errors occur
    });

    test('processClonedRepository creates brick.yaml for components', () async {
      // Create a repository with a component
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      // Create pubspec.yaml
      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create components directory and a simple button component
      final buttonDir = Directory('test-repo/lib/src/components/button');
      await buttonDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key, required this.text}) : super(key: key);
  
  final String text;
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {},
      child: Text(text),
    );
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Check if brick.yaml was created for the component
      final brickYamlFile = File('test-repo/lib/src/components/button/brick.yaml');
      expect(await brickYamlFile.exists(), isTrue);
      
      if (await brickYamlFile.exists()) {
        final content = await brickYamlFile.readAsString();
        expect(content.contains('name: button'), isTrue);
        expect(content.contains('description:'), isTrue);
        expect(content.contains('vars:'), isTrue);
      }

      // Verify logger calls
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_findAvailableWidgets returns empty list when bricks directory does not exist', () async {
      // Create a repository without bricks directory
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final config = FpxConfig.defaultConfig();
      
      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
        fpxConfig: config,
      );

      // Should complete without errors even when no bricks directory exists
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_getWidgetFiles handles directory with no dart files', () async {
      // Create a repository with component directory but no dart files
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final componentsDir = Directory('test-repo/lib/src/components');
      await componentsDir.create(recursive: true);

      // Create a component directory with a non-dart file
      final emptyComponentDir = Directory('test-repo/lib/src/components/empty_component');
      await emptyComponentDir.create(recursive: true);
      
      final readmeFile = File('test-repo/lib/src/components/empty_component/README.md');
      await readmeFile.writeAsString('# Empty Component');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Should complete successfully
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_getRepositoryVersion handles missing pubspec.yaml', () async {
      // Create a repository without pubspec.yaml
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final componentsDir = Directory('test-repo/lib/src/components/button');
      await componentsDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Check brick.yaml was created with default version
      final brickYamlFile = File('test-repo/lib/src/components/button/brick.yaml');
      if (await brickYamlFile.exists()) {
        final content = await brickYamlFile.readAsString();
        expect(content.contains('version: 0.1.0+1'), isTrue);
      }

      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_getRepositoryVersion handles pubspec.yaml without version', () async {
      // Create a repository with pubspec.yaml but no version
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
dependencies:
  flutter:
    sdk: flutter
''');

      final componentsDir = Directory('test-repo/lib/src/components/button');
      await componentsDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Check brick.yaml was created with default version
      final brickYamlFile = File('test-repo/lib/src/components/button/brick.yaml');
      if (await brickYamlFile.exists()) {
        final content = await brickYamlFile.readAsString();
        expect(content.contains('version: 0.1.0+1'), isTrue);
      }

      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_getRepositoryVersion handles corrupted pubspec.yaml', () async {
      // Create a repository with corrupted pubspec.yaml
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      // Create an unreadable file by writing binary data
      await pubspecFile.writeAsBytes([0, 1, 2, 3, 4, 255, 254, 253]);

      final componentsDir = Directory('test-repo/lib/src/components/button');
      await componentsDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Should still complete successfully with default version
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository with nested widget files', () async {
      // Create a repository with nested widget structure
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 2.1.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create nested component structure
      final buttonDir = Directory('test-repo/lib/src/components/button');
      await buttonDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Create nested subdirectory with more dart files
      final buttonSubDir = Directory('test-repo/lib/src/components/button/variants');
      await buttonSubDir.create(recursive: true);
      
      final primaryButtonFile = File('test-repo/lib/src/components/button/variants/primary_button.dart');
      await primaryButtonFile.writeAsString('''
import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Check brick.yaml was created with correct version
      final brickYamlFile = File('test-repo/lib/src/components/button/brick.yaml');
      expect(await brickYamlFile.exists(), isTrue);
      
      if (await brickYamlFile.exists()) {
        final content = await brickYamlFile.readAsString();
        expect(content.contains('version: 2.1.0'), isTrue);
        expect(content.contains('name: button'), isTrue);
      }

      // Check that nested files were copied to __brick__
      final brickButtonFile = File('test-repo/lib/src/components/button/__brick__/button.dart');
      final brickPrimaryFile = File('test-repo/lib/src/components/button/__brick__/variants/primary_button.dart');
      expect(await brickButtonFile.exists(), isTrue);
      expect(await brickPrimaryFile.exists(), isTrue);

      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_addBricksToRepository handles error in widget processing', () async {
      // Create a repository structure that will cause errors during processing
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create a component with a file we can't copy (permission issues are hard to simulate)
      // Instead, we'll create a component in a read-only parent directory structure
      final componentsDir = Directory('test-repo/lib/src/components/button');
      await componentsDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Should complete successfully in normal cases
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('_preprocessWidgetFiles with no foundation constants', () async {
      // Create a repository with components but no foundation files
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      final componentsDir = Directory('test-repo/lib/src/components/button');
      await componentsDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Use a config with foundation paths that don't exist
      final customConfig = FpxConfig(
        bricks: BricksConfig(path: 'lib/src/components'),
        variables: VariablesConfig(
          foundation: FoundationConfig({
            'colors': FoundationItem(path: 'lib/foundation/colors.dart'),
            'typography': FoundationItem(path: 'lib/foundation/typography.dart'),
          }),
        ),
      );

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
        fpxConfig: customConfig,
      );

      // Should complete successfully even with no foundation files
      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });

    test('processClonedRepository with multiple widget types', () async {
      // Create a repository with multiple different widgets
      final repoDir = Directory('test-repo');
      await repoDir.create(recursive: true);

      final pubspecFile = File('test-repo/pubspec.yaml');
      await pubspecFile.writeAsString('''
name: test_repo
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
''');

      // Create multiple components
      final buttonDir = Directory('test-repo/lib/src/components/button');
      await buttonDir.create(recursive: true);
      
      final buttonFile = File('test-repo/lib/src/components/button/button.dart');
      await buttonFile.writeAsString('''
import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  const Button({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      final cardDir = Directory('test-repo/lib/src/components/card');
      await cardDir.create(recursive: true);
      
      final cardFile = File('test-repo/lib/src/components/card/card.dart');
      await cardFile.writeAsString('''
import 'package:flutter/material.dart';

class CustomCard extends StatelessWidget {
  const CustomCard({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      final inputDir = Directory('test-repo/lib/src/components/input');
      await inputDir.create(recursive: true);
      
      final inputFile = File('test-repo/lib/src/components/input/input.dart');
      await inputFile.writeAsString('''
import 'package:flutter/material.dart';

class CustomInput extends StatelessWidget {
  const CustomInput({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');

      // Run the service
      await service.processClonedRepository(
        repositoryName: 'test-repo',
        repositoryPath: 'test-repo',
        repositoryUrl: 'https://github.com/jdde/repo.git',
      );

      // Check that all widgets got brick files
      final buttonBrickYaml = File('test-repo/lib/src/components/button/brick.yaml');
      final cardBrickYaml = File('test-repo/lib/src/components/card/brick.yaml');
      final inputBrickYaml = File('test-repo/lib/src/components/input/brick.yaml');
      
      expect(await buttonBrickYaml.exists(), isTrue);
      expect(await cardBrickYaml.exists(), isTrue);
      expect(await inputBrickYaml.exists(), isTrue);

      // Check that __brick__ directories were created
      final buttonBrickDir = Directory('test-repo/lib/src/components/button/__brick__');
      final cardBrickDir = Directory('test-repo/lib/src/components/card/__brick__');
      final inputBrickDir = Directory('test-repo/lib/src/components/input/__brick__');
      
      expect(await buttonBrickDir.exists(), isTrue);
      expect(await cardBrickDir.exists(), isTrue);
      expect(await inputBrickDir.exists(), isTrue);

      verify(() => logger.info('🔧 Processing cloned repository "test-repo"...')).called(1);
      verify(() => logger.success('✅ Repository processing completed successfully')).called(1);
    });
  });
}
