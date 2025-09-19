import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as path;

import '../services/repository_service.dart';

/// {@template add_command}
/// A [Command] to add a component using Mason bricks.
/// {@endtemplate}
class AddCommand extends Command<int> {
  /// {@macro add_command}
  AddCommand({
    required Logger logger,
    RepositoryService? repositoryService,
  })  : _logger = logger,
        _repositoryService = repositoryService ?? RepositoryService(logger: logger) {
    argParser
      ..addOption(
        'name',
        help: 'Component name',
      )
      ..addOption(
        'variant',
        help: 'Component variant',
      )
      ..addOption(
        'path',
        help: 'Target path',
        defaultsTo: '.',
      )
      ..addOption(
        'source',
        help: 'Brick source URL',
      )
      ..addOption(
        'repository',
        help: 'Specific repository to use (when multiple repositories have the same component)',
      );
  }

  @override
  String get description => 'Add a component using Mason bricks';

  @override
  String get name => 'add';

  @override
  String get invocation => 'fpx add <component> [options]';

  final Logger _logger;
  final RepositoryService _repositoryService;

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      _logger.err('❌ Missing component name. Usage: fpx add <component>');
      return ExitCode.usage.code;
    }

    final component = argResults!.rest.first;
    final specificRepository = argResults!['repository'] as String?;

    try {
      // Search for the component in repositories
      final searchResults = await _findComponentInRepositories(component, specificRepository);
      
      if (searchResults.isEmpty) {
        final repositories = await _repositoryService.getRepositories();
        if (repositories.isEmpty) {
          _logger.err(
            '❌ Component "$component" not found. No repositories configured.\n'
            'Add a repository with: fpx repository add --name <name> --url <url>',
          );
        } else {
          final repoList = repositories.keys.join(', ');
          _logger.err(
            '❌ Component "$component" not found in configured repositories: $repoList\n'
            'Try using --repository option to specify a specific repository.',
          );
        }
        return ExitCode.usage.code;
      }

      // If multiple results and no specific repository chosen, let user select
      BrickSearchResult selectedResult;
      if (searchResults.length > 1 && specificRepository == null) {
        _logger.warn('Multiple components found with name "$component":');
        for (var i = 0; i < searchResults.length; i++) {
          final result = searchResults[i];
          _logger.info('  ${i + 1}. ${result.repositoryName}/${result.fullPath}');
        }
        _logger.info('  0. Cancel');

        selectedResult = await _promptUserSelection(searchResults);
        _logger.info('Using: ${selectedResult.repositoryName}/${selectedResult.fullPath}');
      } else {
        selectedResult = searchResults.first;
        _logger.info(
            'Using component "${selectedResult.brickName}" from repository "${selectedResult.repositoryName}"');
      }

      // Get target directory
      final targetPath = argResults!['path'] as String;
      final targetDirectory = Directory(path.isAbsolute(targetPath)
          ? targetPath
          : path.join(Directory.current.path, targetPath));

      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      // Create generator from brick
      final generator = await MasonGenerator.fromBrick(selectedResult.brick);

      // Create variables map from parsed arguments
      final vars = <String, dynamic>{};
      if (argResults!['name'] != null) vars['name'] = argResults!['name'];
      if (argResults!['variant'] != null)
        vars['variant'] = argResults!['variant'];

      // Add component name as default variable
      vars['component'] = component;

      // Prompt for any missing required variables
      await _promptForMissingVars(generator, vars);

      // Generate the component
      final target = DirectoryGeneratorTarget(targetDirectory);
      final files =
          await generator.generate(target, vars: vars, logger: _logger);

      _logger.success('✅ Successfully generated $component component!');
      _logger.info('Generated ${files.length} file(s):');
      for (final file in files) {
        _logger.detail('  ${file.path}');
      }

      return ExitCode.success.code;
    } catch (e, stackTrace) {
      _logger.err('❌ Failed to generate component: $e');
      _logger.detail('Stack trace: $stackTrace');
      return ExitCode.software.code;
    }
  }

  /// Find component in repositories, optionally filtering by specific repository.
  Future<List<BrickSearchResult>> _findComponentInRepositories(
    String component,
    String? specificRepository,
  ) async {
    // If source is provided, handle it separately (legacy behavior)
    final source = argResults!['source'] as String?;
    if (source != null) {
      if (source.startsWith('http') || source.contains('github.com')) {
        // Handle remote Git repository
        _logger.info('Fetching brick from remote source: $source');
        final brick = Brick.git(GitPath(source));
        return [
          BrickSearchResult(
            brickName: component,
            repositoryName: 'remote',
            brick: brick,
            fullPath: component,
          )
        ];
      } else if (await Directory(source).exists()) {
        // Handle local path
        final brick = Brick.path(source);
        return [
          BrickSearchResult(
            brickName: component,
            repositoryName: 'local',
            brick: brick,
            fullPath: component,
          )
        ];
      }
    }

    // Search in configured repositories
    List<BrickSearchResult> searchResults;
    if (specificRepository != null) {
      // Search only in the specific repository
      searchResults = await _repositoryService.findBrick('@$specificRepository/$component');
    } else {
      // Search in all repositories
      searchResults = await _repositoryService.findBrick(component);
    }

    return searchResults;
  }

  Future<void> _promptForMissingVars(
    MasonGenerator generator,
    Map<String, dynamic> vars,
  ) async {
    // Get brick variables from the generator
    try {
      // For Mason generators, we can't easily access brick variables at runtime
      // So we'll just warn about common missing variables
      final commonVars = ['name', 'description', 'component'];

      for (final varName in commonVars) {
        if (!vars.containsKey(varName)) {
          _logger.detail(
              'Variable $varName not provided, using defaults if available');
        }
      }
    } catch (e) {
      // If we can't read brick variables, continue with provided vars
      _logger.detail('Could not read brick variables: $e');
    }
  }

  Future<BrickSearchResult> _promptUserSelection(
      List<BrickSearchResult> searchResults) async {
    while (true) {
      stdout.write(
          '\nPlease select a component (1-${searchResults.length}, or 0 to cancel): ');
      final input = stdin.readLineSync();

      if (input == null || input.trim().isEmpty) {
        _logger.err('Please enter a valid selection.');
        continue;
      }

      final selection = int.tryParse(input.trim());
      if (selection == null) {
        _logger.err('Invalid input. Please enter a number.');
        continue;
      }

      if (selection == 0) {
        _logger.info('Operation cancelled.');
        throw Exception('User cancelled component selection');
      }

      if (selection < 1 || selection > searchResults.length) {
        _logger.err(
            'Invalid selection. Please enter a number between 1 and ${searchResults.length}, or 0 to cancel.');
        continue;
      }

      return searchResults[selection - 1];
    }
  }
}
