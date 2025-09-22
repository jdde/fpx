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
    String? specificRepository = argResults!['repository'] as String?;
    
    // Get target directory early
    final targetPath = argResults!['path'] as String;
    
    // When there is only one repository configured, set parameter to that name
    final repositories = await _repositoryService.getRepositories();
    if (repositories.length == 1 && specificRepository == null) {
      specificRepository = repositories.keys.first;
      _logger.detail('Only one repository configured, using: $specificRepository');
    }
    

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
          return ExitCode.usage.code;
        } else {
          final repoList = repositories.keys.join(', ');
          _logger.err(
            '❌ Component "$component" not found in configured repositories: $repoList',
          );
          
          // Get all available components from all repositories
          final availableComponents = await _getAllAvailableComponents(specificRepository);
          
          if (availableComponents.isNotEmpty) {
            _logger.info('\n📋 Available components:');
            for (var i = 0; i < availableComponents.length; i++) {
              final componentInfo = availableComponents[i];
              _logger.info('  ${i + 1}. ${componentInfo.repositoryName}/${componentInfo.componentName}');
            }
            _logger.info('  0. Cancel');
            
            // Prompt user to select from available components
            final selectedComponent = await _promptUserSelectionFromAvailable(availableComponents);
            if (selectedComponent != null) {
              // Recursively call with the selected component
              _logger.info('Using selected component: ${selectedComponent.repositoryName}/${selectedComponent.componentName}');
              final selectedSearchResults = await _findComponentInRepositories(
                selectedComponent.componentName, 
                selectedComponent.repositoryName
              );
              if (selectedSearchResults.isNotEmpty) {
                final selectedResult = selectedSearchResults.first;
                return await _generateComponent(selectedResult, targetPath);
              }
            }
          } else {
            _logger.info('No components found in configured repositories.');
          }
          
          return ExitCode.usage.code;
        }
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

      return await _generateComponent(selectedResult, targetPath);
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

  /// Generate component from selected brick and target path
  Future<int> _generateComponent(BrickSearchResult selectedResult, String targetPath) async {
    // Import path for generating relative paths
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
    vars['component'] = selectedResult.brickName;

    // Prompt for any missing required variables
    await _promptForMissingVars(generator, vars);

    // Generate the component
    final target = DirectoryGeneratorTarget(targetDirectory);
    final files =
        await generator.generate(target, vars: vars, logger: _logger);

    _logger.success('✅ Successfully generated ${selectedResult.brickName} component!');
    _logger.info('Generated ${files.length} file(s):');
    for (final file in files) {
      _logger.detail('  ${file.path}');
    }

    return ExitCode.success.code;
  }

  /// Get all available components from repositories
  Future<List<ComponentInfo>> _getAllAvailableComponents(String? specificRepository) async {
    final repositories = await _repositoryService.getRepositories();
    final components = <ComponentInfo>[];

    for (final entry in repositories.entries) {
      final repoName = entry.key;
      
      // If specific repository is requested, filter by that
      if (specificRepository != null && repoName != specificRepository) {
        continue;
      }

      try {
        final availableComponents = await _repositoryService.scanForBricks(repoName);
        for (final componentName in availableComponents) {
          components.add(ComponentInfo(
            componentName: componentName,
            repositoryName: repoName,
          ));
        }
      } catch (e) {
        _logger.detail('Failed to scan repository $repoName: $e');
        // Continue with other repositories
      }
    }

    return components;
  }

  /// Prompt user to select from available components
  Future<ComponentInfo?> _promptUserSelectionFromAvailable(
      List<ComponentInfo> availableComponents) async {
    while (true) {
      stdout.write(
          '\nPlease select a component (1-${availableComponents.length}, or 0 to cancel): ');
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
        return null;
      }

      if (selection < 1 || selection > availableComponents.length) {
        _logger.err(
            'Invalid selection. Please enter a number between 1 and ${availableComponents.length}, or 0 to cancel.');
        continue;
      }

      return availableComponents[selection - 1];
    }
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
}

/// Information about an available component
class ComponentInfo {
  /// Component name
  final String componentName;
  
  /// Repository name where the component is located
  final String repositoryName;

  /// Constructor
  ComponentInfo({
    required this.componentName,
    required this.repositoryName,
  });
}
