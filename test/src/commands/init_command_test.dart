import 'package:fpx/src/commands/init_command.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  group('InitCommand', () {
    late Logger logger;
    late RepositoryService repositoryService;
    late InitCommand command;

    setUp(() {
      logger = _MockLogger();
      repositoryService = _MockRepositoryService();
      command = InitCommand(
        logger: logger,
        repositoryService: repositoryService,
      );
    });

    test('initializes default repositories and shows info messages', () async {
      // Arrange
      when(() => repositoryService.initializeDefaultRepositories())
          .thenAnswer((_) async {});

      // Act
      final result = await command.run();

      // Assert
      expect(result, equals(ExitCode.success.code));

      // Verify repository service was called
      verify(() => repositoryService.initializeDefaultRepositories()).called(1);

      // Verify logger info messages
      verify(() => logger.info(
              '📝 Add your bricks to mason.yaml and run "fpx add <brick-name>"'))
          .called(1);
      verify(() => logger.info(
              '💡 Or use "fpx add <brick-name>" to search configured repositories'))
          .called(1);
      verify(() => logger
              .info('   Run "fpx repository list" to see available repositories'))
          .called(1);
    });

    test('has correct name and description', () {
      expect(command.name, equals('init'));
      expect(command.description, equals('Initialize default repositories'));
    });
  });
}
