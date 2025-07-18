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

    setUp(() async {
      logger = _MockLogger();
      command = InitCommand(logger: logger);
      
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
      // Clean up temporary directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('creates mason.yaml when it does not exist', () async {
      // Ensure mason.yaml doesn't exist
      final masonYamlFile = File('mason.yaml');
      if (await masonYamlFile.exists()) {
        await masonYamlFile.delete();
      }
      expect(await masonYamlFile.exists(), isFalse);

      // Run the command
      final result = await command.run();

      // Verify the file was created
      expect(await masonYamlFile.exists(), isTrue);
      expect(result, equals(ExitCode.success.code));

      // Verify the content
      final content = await masonYamlFile.readAsString();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));

      // Verify logger calls
      verify(() => logger.info('📦 Creating mason.yaml with default settings...')).called(1);
      verify(() => logger.success('✅ Created mason.yaml with default configuration')).called(1);
      verify(() => logger.info('📝 Add your bricks to mason.yaml and run "fpx add <brick-name>"')).called(1);
    });

    test('warns when mason.yaml already exists', () async {
      // Create an existing mason.yaml file
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('existing content');

      // Run the command
      final result = await command.run();

      // Verify the result
      expect(result, equals(ExitCode.success.code));

      // Verify the content wasn't changed
      final content = await masonYamlFile.readAsString();
      expect(content, equals('existing content'));

      // Verify logger calls
      verify(() => logger.warn('⚠️  mason.yaml already exists')).called(1);
      verifyNever(() => logger.info('📦 Creating mason.yaml with default settings...'));
      verifyNever(() => logger.success('✅ Created mason.yaml with default configuration'));
    });

    test('has correct name and description', () {
      expect(command.name, equals('init'));
      expect(command.description, equals('Initialize a new mason.yaml file'));
    });
  });
}
