import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../services/repository_service.dart';

/// {@template init_command}
/// A [Command] to initialize default repositories.
/// {@endtemplate}
class InitCommand extends Command<int> {
  /// {@macro init_command}
  InitCommand({
    required Logger logger,
    RepositoryService? repositoryService,
  })  : _logger = logger,
        _repositoryService = repositoryService ?? RepositoryService(logger: logger);

  @override
  String get description => 'Initialize default repositories';

  @override
  String get name => 'init';

  final Logger _logger;
  final RepositoryService _repositoryService;

  @override
  Future<int> run() async {
    await _repositoryService.initializeDefaultRepositories();
    _logger.info(
        '💡 Or use "fpx add <brick-name>" to search configured repositories');
    _logger.info('   Run "fpx repository list" to see available repositories');
    return ExitCode.success.code;
  }
}
