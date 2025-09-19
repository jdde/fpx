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
    if (repositories.isEmpty) {
      _logger.info('📋 No repositories configured yet');
      _logger.info('💡 Configure repositories:');
      _logger.info('   fpx repository add --name <name> --url <url>');
    }

    return ExitCode.success.code;
  }
}
