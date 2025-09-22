import 'package:args/command_runner.dart';
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
    late CommandRunner<int> commandRunner;

    setUp(() {
      logger = _MockLogger();
      repositoryService = _MockRepositoryService();
      command = ListCommand(
        logger: logger,
        repositoryService: repositoryService,
      );

      commandRunner = CommandRunner<int>('test', 'Test runner')
        ..addCommand(command);
    });

    test('has correct name and description', () {
      expect(command.name, equals('list'));
      expect(command.description, equals('List available bricks'));
    });

    test('can be instantiated without providing repository service', () {
      // Test the default constructor path where RepositoryService is created internally
      final commandWithDefaults = ListCommand(logger: logger);
      expect(commandWithDefaults.name, equals('list'));
      expect(commandWithDefaults.description, equals('List available bricks'));
    });

    test('lists configured repositories and components', () async {
      // Arrange
      const repo1 = RepositoryInfo(
        name: 'repo1',
        url: 'https://github.com/user/repo1',
        path: 'path1',
      );
      const repo2 = RepositoryInfo(
        name: 'repo2',
        url: 'https://github.com/user/repo2',
        path: 'path2',
      );

      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {
                'repo1': repo1,
                'repo2': repo2,
              });

      when(() => repositoryService.getAllAvailableComponents())
          .thenAnswer((_) async => {
                'repo1': ['button', 'card', 'input'],
                'repo2': ['dialog', 'dropdown'],
              });

      // Act
      final exitCode = await commandRunner.run(['list']);

      // Assert
      expect(exitCode, equals(ExitCode.success.code));

      // Verify repositories are shown
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  repo1: https://github.com/user/repo1')).called(1);
      verify(() => logger.info('  repo2: https://github.com/user/repo2')).called(1);

      // Verify components are shown
      verify(() => logger.info('Available components:')).called(1);
      verify(() => logger.info('  From repository "repo1":')).called(1);
      verify(() => logger.info('    button')).called(1);
      verify(() => logger.info('    card')).called(1);
      verify(() => logger.info('    input')).called(1);
      verify(() => logger.info('  From repository "repo2":')).called(1);
      verify(() => logger.info('    dialog')).called(1);
      verify(() => logger.info('    dropdown')).called(1);

      // Verify help messages
      verify(() => logger.info('💡 Use "fpx add <component-name>" to add a component')).called(1);
      verify(() => logger.info('   Or "fpx add @repo/<component-name>" for a specific repository')).called(1);
    });

    test('shows help when no repositories are configured', () async {
      // Arrange
      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => <String, RepositoryInfo>{});

      when(() => repositoryService.getAllAvailableComponents())
          .thenAnswer((_) async => <String, List<String>>{});

      // Act
      final exitCode = await commandRunner.run(['list']);

      // Assert
      expect(exitCode, equals(ExitCode.success.code));

      verify(() => logger.info('📋 No repositories configured yet')).called(1);
      verify(() => logger.info('💡 Add repositories with:')).called(1);
      verify(() => logger.info('   fpx repository add --name <name> --url <url>')).called(1);
    });

    test('shows message when repositories exist but no components found', () async {
      // Arrange
      const repo1 = RepositoryInfo(
        name: 'repo1',
        url: 'https://github.com/user/repo1',
        path: 'path1',
      );

      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {'repo1': repo1});

      when(() => repositoryService.getAllAvailableComponents())
          .thenAnswer((_) async => <String, List<String>>{});

      // Act
      final exitCode = await commandRunner.run(['list']);

      // Assert
      expect(exitCode, equals(ExitCode.success.code));

      // Verify repository is shown
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  repo1: https://github.com/user/repo1')).called(1);

      // Verify no components message
      verify(() => logger.info('📋 No components found in configured repositories')).called(1);
      verify(() => logger.info('💡 Make sure your repositories contain valid fpx.yaml files')).called(1);
      verify(() => logger.info('   or __brick__ directories with brick.yaml files')).called(1);
    });

    test('handles repositories with empty component lists', () async {
      // Arrange
      const repo1 = RepositoryInfo(
        name: 'repo1',
        url: 'https://github.com/user/repo1',
        path: 'path1',
      );
      const repo2 = RepositoryInfo(
        name: 'repo2',
        url: 'https://github.com/user/repo2',
        path: 'path2',
      );

      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {
                'repo1': repo1,
                'repo2': repo2,
              });

      when(() => repositoryService.getAllAvailableComponents())
          .thenAnswer((_) async => {
                'repo1': <String>[], // Empty list
                'repo2': ['button', 'card'], // Non-empty list
              });

      // Act
      final exitCode = await commandRunner.run(['list']);

      // Assert
      expect(exitCode, equals(ExitCode.success.code));

      // Verify repositories are shown
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  repo1: https://github.com/user/repo1')).called(1);
      verify(() => logger.info('  repo2: https://github.com/user/repo2')).called(1);

      // Verify components are shown
      verify(() => logger.info('Available components:')).called(1);
      
      // repo1 should not be shown since it has no components
      verifyNever(() => logger.info('  From repository "repo1":'));
      
      // repo2 should be shown with its components
      verify(() => logger.info('  From repository "repo2":')).called(1);
      verify(() => logger.info('    button')).called(1);
      verify(() => logger.info('    card')).called(1);

      // Verify help messages
      verify(() => logger.info('💡 Use "fpx add <component-name>" to add a component')).called(1);
      verify(() => logger.info('   Or "fpx add @repo/<component-name>" for a specific repository')).called(1);
    });

    test('handles single repository with single component', () async {
      // Arrange
      const repo1 = RepositoryInfo(
        name: 'my-repo',
        url: 'https://github.com/user/my-repo',
        path: 'components',
      );

      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {'my-repo': repo1});

      when(() => repositoryService.getAllAvailableComponents())
          .thenAnswer((_) async => {
                'my-repo': ['button'],
              });

      // Act
      final exitCode = await commandRunner.run(['list']);

      // Assert
      expect(exitCode, equals(ExitCode.success.code));

      // Verify repository is shown
      verify(() => logger.info('Configured repositories:')).called(1);
      verify(() => logger.info('  my-repo: https://github.com/user/my-repo')).called(1);

      // Verify component is shown
      verify(() => logger.info('Available components:')).called(1);
      verify(() => logger.info('  From repository "my-repo":')).called(1);
      verify(() => logger.info('    button')).called(1);

      // Verify help messages
      verify(() => logger.info('💡 Use "fpx add <component-name>" to add a component')).called(1);
      verify(() => logger.info('   Or "fpx add @repo/<component-name>" for a specific repository')).called(1);
    });

    test('handles exception from repository service gracefully', () async {
      // Arrange
      when(() => repositoryService.getRepositories())
          .thenThrow(Exception('Failed to load repositories'));

      // Act & Assert
      expect(
        () => commandRunner.run(['list']),
        throwsA(isA<Exception>()),
      );
    });

    test('handles exception from getAllAvailableComponents gracefully', () async {
      // Arrange
      const repo1 = RepositoryInfo(
        name: 'repo1',
        url: 'https://github.com/user/repo1',
        path: 'path1',
      );

      when(() => repositoryService.getRepositories())
          .thenAnswer((_) async => {'repo1': repo1});

      when(() => repositoryService.getAllAvailableComponents())
          .thenThrow(Exception('Failed to load components'));

      // Act & Assert
      expect(
        () => commandRunner.run(['list']),
        throwsA(isA<Exception>()),
      );
    });
  });
}