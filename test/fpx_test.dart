import 'dart:io';

import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('fpx main', () {
    tearDown(() {
      Directory.current = cwd;
    });

    test(
      '--help shows correct help information',
      overridePrint(() async {
        final result = await Process.run(
          'dart',
          ['run', 'bin/fpx.dart', '--help'],
          workingDirectory: cwd.path,
        );
        
        expect(result.exitCode, equals(0));
        final output = result.stdout as String;
        expect(output, contains('fpx - Flutter eXports CLI'));
        expect(output, contains('Usage:'));
        expect(output, contains('fpx init'));
        expect(output, contains('fpx add <component>'));
        expect(output, contains('fpx list'));
        expect(output, contains('Options for \'add\':'));
        expect(output, contains('--name=<name>'));
        expect(output, contains('--variant=<variant>'));
        expect(output, contains('--path=<path>'));
        expect(output, contains('--source=<url>'));
        expect(output, contains('Examples:'));
      }),
    );

    test(
      '-h shows correct help information',
      overridePrint(() async {
        final result = await Process.run(
          'dart',
          ['run', 'bin/fpx.dart', '-h'],
          workingDirectory: cwd.path,
        );
        
        expect(result.exitCode, equals(0));
        final output = result.stdout as String;
        expect(output, contains('fpx - Flutter eXports CLI'));
      }),
    );

    test(
      'no arguments shows help information',
      overridePrint(() async {
        final result = await Process.run(
          'dart',
          ['run', 'bin/fpx.dart'],
          workingDirectory: cwd.path,
        );
        
        expect(result.exitCode, equals(0));
        final output = result.stdout as String;
        expect(output, contains('fpx - Flutter eXports CLI'));
      }),
    );

    test('exits with code 1 when unknown command is provided', () async {
      final result = await Process.run(
        'dart',
        ['run', 'bin/fpx.dart', 'unknown-command'],
        workingDirectory: cwd.path,
      );
      
      expect(result.exitCode, equals(1));
      final stderr = result.stderr as String;
      expect(stderr, contains('Unknown command "unknown-command"'));
    });
  });
}
