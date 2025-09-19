import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

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
        _repositoryService = repositoryService ?? RepositoryService(logger: logger);

  @override
  String get description => 'List available bricks';

  @override
  String get name => 'list';

  final Logger _logger;
  final RepositoryService _repositoryService;

  @override
  Future<int> run() async {
    final repositories = await _repositoryService.getRepositories();
    final allComponents = await _repositoryService.getAllAvailableComponents();

    // Show configured repositories
    if (repositories.isNotEmpty) {
      _logger.info('Configured repositories:');
      for (final repo in repositories.values) {
        _logger.info('  ${repo.name}: ${repo.url}');
      }
      _logger.info('');
    }

    // Show available components from repositories
    if (allComponents.isNotEmpty) {
      _logger.info('Available components:');
      for (final entry in allComponents.entries) {
        final repoName = entry.key;
        final components = entry.value;
        
        if (components.isNotEmpty) {
          _logger.info('  From repository "$repoName":');
          for (final component in components) {
            _logger.info('    $component');
          }
        }
      }
      _logger.info('');
      _logger.info('💡 Use "fpx add <component-name>" to add a component');
      _logger.info('   Or "fpx add @repo/<component-name>" for a specific repository');
    }

    // Show help if nothing is configured
    if (repositories.isEmpty) {
      _logger.info('📋 No repositories configured yet');
      _logger.info('💡 Add repositories with:');
      _logger.info('   fpx repository add --name <name> --url <url>');
      _logger.info('   fpx init  # to create default repositories');
    } else if (allComponents.isEmpty) {
      _logger.info('📋 No components found in configured repositories');
      _logger.info('💡 Make sure your repositories contain valid fpx.yaml files');
      _logger.info('   or __brick__ directories with brick.yaml files');
    }

    return ExitCode.success.code;
  }
}
