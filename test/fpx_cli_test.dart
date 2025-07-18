import 'dart:io';
import 'package:test/test.dart';
import 'package:fpx_cli/fpx_cli.dart';
import 'package:mason/mason.dart';

import 'helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('FpxCli', () {
    late FpxCli cli;
    late Logger mockLogger;

    setUp(() {
      mockLogger = Logger();
      cli = FpxCli(logger: mockLogger);
    });

    tearDown(() {
      Directory.current = cwd;
    });

    test('shows help when no arguments provided', () async {
      final exitCode = await cli.run([]);
      expect(exitCode, equals(0));
    });

    test('shows help when --help flag provided', () async {
      final exitCode = await cli.run(['--help']);
      expect(exitCode, equals(0));
    });

    test('shows help when -h flag provided', () async {
      final exitCode = await cli.run(['-h']);
      expect(exitCode, equals(0));
    });

    test('returns 1 for unknown command', () async {
      final exitCode = await cli.run(['unknown']);
      expect(exitCode, equals(1));
    });

    test('handles init command', () async {
      setUpTestingEnvironment(cwd, suffix: 'init_test');
      
      final exitCode = await cli.run(['init']);
      expect(exitCode, equals(0));

      final masonYamlFile = File('mason.yaml');
      expect(await masonYamlFile.exists(), isTrue);
    });

    test('handles list command with no bricks', () async {
      setUpTestingEnvironment(cwd, suffix: 'list_test');
      
      final exitCode = await cli.run(['list']);
      expect(exitCode, equals(0));
    });

    test('handles add command with missing component name', () async {
      setUpTestingEnvironment(cwd, suffix: 'add_missing_test');
      
      final exitCode = await cli.run(['add']);
      expect(exitCode, equals(1));
    });

    test('handles add command with non-existent brick', () async {
      setUpTestingEnvironment(cwd, suffix: 'add_nonexistent_test');
      
      // Create a simple mason.yaml with test brick
      final masonYamlFile = File('mason.yaml');
      await masonYamlFile.writeAsString('''
bricks:
  test_brick:
    path: ./non-existent
''');

      try {
        final exitCode = await cli.run(['add', 'test_brick']);
        // Expect failure due to non-existent brick path
        expect(exitCode, equals(1));
      } catch (e) {
        // Expected to throw due to non-existent path
        expect(e, isA<Exception>());
      }
    });
  });
}
