import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// {@template init_command}
/// A [Command] to initialize a new mason.yaml file.
/// {@endtemplate}
class InitCommand extends Command<int> {
  /// {@macro init_command}
  InitCommand({
    required Logger logger,
  }) : _logger = logger;

  @override
  String get description => 'Initialize a new mason.yaml file';

  @override
  String get name => 'init';

  final Logger _logger;

  @override
  Future<int> run() async {
    final masonYamlFile = File('mason.yaml');

    if (await masonYamlFile.exists()) {
      _logger.warn('⚠️  mason.yaml already exists');
      return ExitCode.success.code;
    }

    await _ensureMasonYamlExists();
    _logger.info('📝 Add your bricks to mason.yaml and run "fpx add <brick-name>"');
    return ExitCode.success.code;
  }

  Future<void> _ensureMasonYamlExists() async {
    final masonYamlFile = File('mason.yaml');

    if (!await masonYamlFile.exists()) {
      _logger.info('📦 Creating mason.yaml with default settings...');

      const defaultMasonYaml = '''
bricks:
  # Add your bricks here
  # Example:
  # button:
  #   git:
  #     url: https://github.com/felangel/mason.git
  #     path: bricks/button
  # 
  # widget:
  #   path: ./bricks/widget
''';

      await masonYamlFile.writeAsString(defaultMasonYaml);
      _logger.success('✅ Created mason.yaml with default configuration');
    }
  }
}
