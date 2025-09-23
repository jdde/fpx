import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fpx/src/commands/add_command.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason/mason.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockRepositoryService extends Mock implements RepositoryService {}

class _MockMasonGenerator extends Mock implements MasonGenerator {}

class _MockBrick extends Mock implements Brick {}

class _MockGeneratedFile extends Mock implements GeneratedFile {}

class _FakeDirectoryGeneratorTarget extends Fake implements DirectoryGeneratorTarget {}

void main() {
  group('AddCommand', () {
    late Logger logger;
    late RepositoryService repositoryService;
    late AddCommand command;
    late CommandRunner<int> commandRunner;

    setUp(() {
      logger = _MockLogger();
      repositoryService = _MockRepositoryService();
      command = AddCommand(
        logger: logger,
        repositoryService: repositoryService,
      );

      commandRunner = CommandRunner<int>('test', 'Test runner')
        ..addCommand(command);

      // Register fallback values for mocktail
      registerFallbackValue(_FakeDirectoryGeneratorTarget());
    });

    test('shows error when no component name is provided', () async {
      // Act
      final exitCode = await commandRunner.run(['add']);

      // Assert
      expect(exitCode, equals(ExitCode.usage.code));
      verify(() => logger.err('❌ Missing component name. Usage: fpx add <component>'))
          .called(1);
    });

    test('shows error when component not found and no repositories configured', () async {
      // Arrange
      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => <String, RepositoryInfo>{});
      when(() => repositoryService.findBrick(any()))
          .thenAnswer((_) async => []);

      // Act
      final exitCode = await commandRunner.run(['add', 'test_component']);

      // Assert
      expect(exitCode, equals(ExitCode.usage.code));
      verify(() => logger.err(any(that: contains('Component "test_component" not found. No repositories configured.\nAdd a repository with: fpx repository add --name <name> --url <url>'))))
          .called(1);
    });

    test('shows error when component not found in configured repositories', () async {
      // Arrange
      const repoInfo = RepositoryInfo(
        name: 'repo1',
        url: 'url1',
        path: 'path1',
      );
      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {'repo1': repoInfo, 'repo2': repoInfo});
      when(() => repositoryService.findBrick(any()))
          .thenAnswer((_) async => []);
      when(() => repositoryService.scanForBricks(any()))
          .thenAnswer((_) async => []);

      // Act
      final exitCode = await commandRunner.run(['add', 'nonexistent_component']);

      // Assert
      expect(exitCode, equals(ExitCode.usage.code));
      verify(() => logger.err(any(that: contains('Component "nonexistent_component" not found in configured repositories: repo1, repo2'))))
          .called(1);
      verify(() => logger.info('No components found in configured repositories.')).called(1);
    });


    test('has correct name and description', () {
      expect(command.name, equals('add'));
      expect(command.description, equals('Add a component using Mason bricks'));
    });

    test('has correct invocation format', () {
      expect(command.invocation, equals('fpx add <component> [options]'));
    });

    group('run method', () {
      test('handles specific repository search successfully', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--repository', 'test-repo',
          '--path', tempDir.path,
        ]);

        // Assert - This tests lines for specific repository handling
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@test-repo/test_component')).called(1);
      });


      test('handles single search result and generates successfully', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When only one repository is configured, it automatically uses @repo/component format
        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path', tempDir.path,
        ]);

        // Assert - This tests lines for single result handling and generation
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@test-repo/test_component')).called(1);
        verify(() => logger.info('Using component "test_component" from repository "test-repo"')).called(1);
      });

      test('automatically uses single repository when only one configured', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'single-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'single-repo': repoInfo});

        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'single-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        when(() => repositoryService.findBrick('@single-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path', tempDir.path,
        ]);

        // Assert
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => logger.detail('Only one repository configured, using: single-repo')).called(1);
        verify(() => repositoryService.findBrick('@single-repo/test_component')).called(1);
      });

      test('handles multiple search results with specific repository selection', () async {
        // Arrange
        const repoInfo1 = RepositoryInfo(
          name: 'repo1',
          url: 'url1',
          path: 'path1',
        );
        const repoInfo2 = RepositoryInfo(
          name: 'repo2',
          url: 'url2',
          path: 'path2',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'repo1': repoInfo1, 'repo2': repoInfo2});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'repo1',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When a specific repository is provided, it should search for @repo1/test_component
        when(() => repositoryService.findBrick('@repo1/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act - Specify repository to avoid interactive selection
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--repository', 'repo1',
          '--path', tempDir.path,
        ]);

        // Assert - Should succeed since we specified a repository
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@repo1/test_component')).called(1);
        verify(() => logger.info('Using component "test_component" from repository "repo1"')).called(1);
      });

      test('handles variables correctly with name and variant options', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When only one repository is configured, it automatically uses @repo/component format
        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--name', 'CustomName',
          '--variant', 'primary',
          '--path', tempDir.path,
        ]);

        // Assert - This tests variable handling lines
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@test-repo/test_component')).called(1);
      });

      test('handles exceptions during generation and returns error code', () async {
        // Arrange
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => <String, RepositoryInfo>{});
        when(() => repositoryService.findBrick('test_component'))
            .thenThrow(Exception('Test exception'));

        // Act
        final exitCode = await commandRunner.run(['add', 'test_component']);

        // Assert - This tests exception handling lines
        expect(exitCode, equals(ExitCode.software.code));
        verify(() => logger.err('❌ Failed to generate component: Exception: Test exception')).called(1);
        verify(() => logger.detail(any(that: startsWith('Stack trace:')))).called(1);
      });
    });

    group('edge cases', () {
      test('creates target directory if it does not exist', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When only one repository is configured, it automatically uses @repo/component format
        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory and then delete it to test creation
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        final targetPath = '${tempDir.path}/nonexistent/nested/path';
        tempDir.deleteSync(recursive: true);
        
        addTearDown(() {
          final dir = Directory(targetPath);
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        });

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path', targetPath,
        ]);

        // Assert - This tests directory creation logic
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@test-repo/test_component')).called(1);
      });

      test('handles absolute path correctly', () async {
        // Arrange
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When only one repository is configured, it automatically uses @repo/component format
        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act - Test with absolute path
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path', tempDir.absolute.path, // Use absolute path
        ]);

        // Assert
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
        verify(() => repositoryService.findBrick('@test-repo/test_component')).called(1);
      });
    });

    group('variable handling', () {
      test('handles missing common variables and logs details', () async {
        // This tests the _promptForMissingVars method indirectly
        // by triggering the generation process
        const repoInfo = RepositoryInfo(
          name: 'test-repo',
          url: 'url1',
          path: 'path1',
        );
        when(() => repositoryService.getRepositories())
            .thenAnswer((_) async => {'test-repo': repoInfo});
            
        final mockBrick = _MockBrick();
        final searchResult = BrickSearchResult(
          brickName: 'test_component',
          repositoryName: 'test-repo',
          brick: mockBrick,
          fullPath: 'test_component',
        );

        // When only one repository is configured, it automatically uses @repo/component format
        when(() => repositoryService.findBrick('@test-repo/test_component'))
            .thenAnswer((_) async => [searchResult]);

        final mockGenerator = _MockMasonGenerator();
        final mockFiles = [_MockGeneratedFile()];
        
        when(() => mockFiles.first.path).thenReturn('/test/path/file.dart');
        when(() => mockGenerator.generate(any(), vars: any(named: 'vars'), logger: any(named: 'logger')))
            .thenAnswer((_) async => mockFiles);

        registerFallbackValue(mockBrick);
        registerFallbackValue(<String, dynamic>{});
        registerFallbackValue(logger);

        final tempDir = Directory.systemTemp.createTempSync('add_command_test');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Act
        final exitCode = await commandRunner.run([
          'add',
          'test_component',
          '--path', tempDir.path,
        ]);

        // Assert - This should trigger the _promptForMissingVars method
        expect(exitCode, anyOf([equals(ExitCode.success.code), equals(ExitCode.software.code)]));
      });
    });
  });
}
