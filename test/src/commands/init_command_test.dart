import 'dart:io';

import 'package:fpx/src/commands/init_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('InitCommand', () {
    late Logger logger;
    late InitCommand command;
    late Directory testDir;
    late Directory originalDir;

    setUp(() async {
      logger = _MockLogger();
      command = InitCommand(logger: logger);

      // Save original directory
      originalDir = Directory.current;

      // Create a temporary test directory
      testDir = await Directory.systemTemp.createTemp('fpx_init_test_');
      Directory.current = testDir;

      // Ensure clean state
      final masonYamlFile = File('mason.yaml');
      if (await masonYamlFile.exists()) {
        await masonYamlFile.delete();
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

    test('initializes fpx repositories configuration', () async {
      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('🚀 fpx initialized successfully!')).called(1);
      verify(() => logger.info('� Add repositories with: fpx repository add --url <url>')).called(1);
      verify(() => logger.info('   Then use: fpx add <component-name> to add components')).called(1);
      verify(() => logger.info('   Run "fpx repository list" to see available repositories')).called(1);
    });

    test('has correct name and description', () {
      expect(command.name, equals('init'));
      expect(command.description, equals('Initialize fpx repositories configuration'));
    });
  });
}
