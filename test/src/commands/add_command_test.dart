import 'package:args/command_runner.dart';
import 'package:fpx/src/commands/add_command.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockRepositoryService extends Mock implements RepositoryService {}

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
      verify(() => logger.err(any(that: contains('Component "test_component" not found. No repositories configured'))))
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

      // Act
      final exitCode = await commandRunner.run(['add', 'nonexistent_component']);

      // Assert
      expect(exitCode, equals(ExitCode.usage.code));
      verify(() => logger.err(any(that: contains('Component "nonexistent_component" not found in configured repositories: repo1, repo2'))))
          .called(1);
    });

    test('has correct name and description', () {
      expect(command.name, equals('add'));
      expect(command.description, equals('Add a component using Mason bricks'));
    });

    test('has correct invocation format', () {
      expect(command.invocation, equals('fpx add <component> [options]'));
    });
  });
}
