import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';

import '../services/repository_service.dart';

/// {@template list_command}
/// A [Command] to list available bricks.
/// {@endtemplate}
class ListCommand extends Command<int> {
  /// {@macro list_command}
  ListCommand({
    required Logger logger,
    RepositoryService? repositoryService,
  })  : _logger = logger,
        _repositoryService = repositoryService ?? RepositoryService();

  @override
  String get description => 'List available bricks';

  @override
  String get name => 'list';

  final Logger _logger;
  final RepositoryService _repositoryService;

  @override
  Future<int> run() async {
    // Auto-initialize if mason.yaml doesn't exist
    await _ensureMasonYamlExists();

    final masonYaml = await _loadMasonYaml();
    final repositories = await _repositoryService.getRepositories();

    // Show local mason.yaml bricks
    final bricksNode = masonYaml?['bricks'];
    if (bricksNode != null && bricksNode is Map && bricksNode.isNotEmpty) {
      _logger.info('Local bricks (mason.yaml):');
      for (final brickName in bricksNode.keys) {
        _logger.info('  $brickName');
      }
      _logger.info('');
    }

    // Show configured repositories
    if (repositories.isNotEmpty) {
      _logger.info('Configured repositories:');
      for (final repo in repositories.values) {
        _logger.info('  ${repo.name}: ${repo.url}');
      }
      _logger.info('');
      _logger.info('💡 Use "fpx add <brick-name>" to search all repositories');
      _logger
          .info('   Or "fpx add @repo/<brick-name>" for a specific repository');
    }

    // Show help if nothing is configured
    if ((bricksNode == null || (bricksNode is Map && bricksNode.isEmpty)) &&
        repositories.isEmpty) {
      _logger.info('📋 No bricks or repositories configured yet');
      _logger.info('💡 Add bricks to mason.yaml or configure repositories:');
      _logger.info('   fpx repository add --name <name> --url <url>');
      _logger
          .info('   fpx init  # to create mason.yaml and default repositories');
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
      _logger.info(
          '📦 No mason.yaml found, creating one with default settings...');

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
