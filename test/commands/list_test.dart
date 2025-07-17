import 'dart:io';

import 'package:test/test.dart';

import '../helpers/helpers.dart';

void main() {
  final cwd = Directory.current;

  group('fpx list', () {
    setUp(() {
      setUpTestingEnvironment(cwd, suffix: '.list');
    });

    tearDown(() {
      Directory.current = cwd;
    });

    test('lists empty bricks when mason.yaml does not exist', () async {
      expect(File('mason.yaml').existsSync(), isFalse);
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('No mason.yaml found, creating one'));
      expect(stdout, contains('No bricks configured in mason.yaml yet'));
      expect(stdout, contains('Add bricks to mason.yaml or use --source option'));
      
      // Should auto-create mason.yaml
      expect(File('mason.yaml').existsSync(), isTrue);
    });

    test('lists empty bricks when mason.yaml has no bricks', () async {
      File('mason.yaml').writeAsStringSync('bricks:\n');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('No bricks configured in mason.yaml yet'));
      expect(stdout, contains('Add bricks to mason.yaml or use --source option'));
    });

    test('lists available bricks when mason.yaml has bricks', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  button:
    git:
      url: https://github.com/felangel/mason.git
      path: bricks/button
  widget:
    path: ./bricks/widget
  card:
    git:
      url: https://github.com/my-org/ui-bricks.git
''');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('Available bricks:'));
      expect(stdout, contains('button'));
      expect(stdout, contains('widget'));
      expect(stdout, contains('card'));
    });

    test('handles malformed mason.yaml gracefully', () async {
      File('mason.yaml').writeAsStringSync('invalid yaml content: [}');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('No bricks configured in mason.yaml yet'));
    });

    test('auto-initializes when mason.yaml does not exist', () async {
      expect(File('mason.yaml').existsSync(), isFalse);
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      expect(File('mason.yaml').existsSync(), isTrue);
      
      final content = File('mason.yaml').readAsStringSync();
      expect(content, contains('bricks:'));
      expect(content, contains('# Add your bricks here'));
    });

    test('lists bricks from complex mason.yaml structure', () async {
      File('mason.yaml').writeAsStringSync('''
bricks:
  # UI Components
  button:
    git:
      url: https://github.com/felangel/mason.git
      path: bricks/button
      ref: main
  
  # Local bricks
  custom_widget:
    path: ./local_bricks/custom_widget
    
  # Simple registry brick
  simple_brick: ^1.0.0
''');
      
      final result = await Process.run(
        'dart',
        ['run', '../../../bin/fpx.dart', 'list'],
        workingDirectory: Directory.current.path,
      );
      
      expect(result.exitCode, equals(0));
      
      final stdout = result.stdout as String;
      expect(stdout, contains('Available bricks:'));
      expect(stdout, contains('button'));
      expect(stdout, contains('custom_widget'));
      expect(stdout, contains('simple_brick'));
    });
  });
}
