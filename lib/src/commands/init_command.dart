import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../services/repository_service.dart';

/// {@template init_command}
/// A [Command] to initialize fpx repositories.
/// {@endtemplate}
class InitCommand extends Command<int> {
  /// {@macro init_command}
  InitCommand({
    required Logger logger,
    RepositoryService? repositoryService,
  })  : _logger = logger,
        _repositoryService = repositoryService ?? RepositoryService(logger: logger);

  @override
  String get description => 'Initialize fpx repositories configuration';

  @override
  String get name => 'init';

  final Logger _logger;
  final RepositoryService _repositoryService;

  @override
  Future<int> run() async {
    await _repositoryService.initializeDefaultRepositories();
    
    _logger.info('🚀 fpx initialized successfully!');
    _logger.info('� Add repositories with: fpx repository add --url <url>');
    _logger.info('   Then use: fpx add <component-name> to add components');
    _logger.info('   Run "fpx repository list" to see available repositories');
    
    return ExitCode.success.code;
  }
}
