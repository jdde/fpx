import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';

/// {@template list_command}
/// A [Command] to list available bricks.
/// {@endtemplate}
class ListCommand extends Command<int> {
  /// {@macro list_command}
  ListCommand({
    required Logger logger,
  }) : _logger = logger;

  @override
  String get description => 'List available bricks';

  @override
  String get name => 'list';

  final Logger _logger;

  @override
  Future<int> run() async {
    // Auto-initialize if mason.yaml doesn't exist
    await _ensureMasonYamlExists();

    final masonYaml = await _loadMasonYaml();

    final bricksNode = masonYaml?['bricks'];
    if (bricksNode == null || (bricksNode is Map && bricksNode.isEmpty)) {
      _logger.info('📋 No bricks configured in mason.yaml yet');
      _logger.info('💡 Add bricks to mason.yaml or use --source option with fpx add');
      return ExitCode.success.code;
    }

    _logger.info('Available bricks:');
    if (bricksNode is Map) {
      for (final brickName in bricksNode.keys) {
        _logger.info('  $brickName');
      }
    }

    return ExitCode.success.code;
  }

  Future<Map<String, dynamic>?> _loadMasonYaml() async {
    final masonYamlFile = File('mason.yaml');
    if (!await masonYamlFile.exists()) {
      return null;
    }

    try {
      final content = await masonYamlFile.readAsString();
      final yamlMap = loadYaml(content);

      if (yamlMap is Map) {
        return Map<String, dynamic>.from(yamlMap);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _ensureMasonYamlExists() async {
    final masonYamlFile = File('mason.yaml');

    if (!await masonYamlFile.exists()) {
      _logger.info('📦 No mason.yaml found, creating one with default settings...');

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
