import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

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
        _repositoryService = repositoryService ?? RepositoryService() {
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

    // Auto-initialize if mason.yaml doesn't exist
    await _ensureMasonYamlExists();

    final component = argResults!.rest.first;

    try {
      // Get target directory
      final targetPath = argResults!['path'] as String;
      final targetDirectory = Directory(path.isAbsolute(targetPath)
          ? targetPath
          : path.join(Directory.current.path, targetPath));

      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      // Find or create brick
      final brick =
          await _findBrick(component, argResults!['source'] as String?);

      // Create generator from brick
      final generator = await MasonGenerator.fromBrick(brick);

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

  Future<Brick> _findBrick(String component, String? source) async {
    // TODO: use fpx.yaml in repo for search
    // TODO: remote path cant work, since we need to manipulate the repo first based on fpx configuration
    // If source is provided, try to use it as a Git URL or path
    if (source != null) {
      if (source.startsWith('http') || source.contains('github.com')) {
        // Handle remote Git repository
        _logger.info('Fetching brick from remote source: $source');
        return Brick.git(GitPath(source));
      } else if (await Directory(source).exists()) {
        // Handle local path
        return Brick.path(source);
      }
    }

    // Search in configured repositories first
    final searchResults = await _repositoryService.findBrick(component);

    if (searchResults.length == 1) {
      // Single match found
      final result = searchResults.first;
      _logger.info(
          'Using brick "${result.brickName}" from repository "${result.repositoryName}"');
      return result.brick;
    } else if (searchResults.length > 1) {
      // Multiple matches found, let user choose
      _logger.warn('Multiple bricks found with name "$component":');
      for (var i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
        _logger.info('  ${i + 1}. ${result.repositoryName}/${result.fullPath}');
      }
      _logger.info('  0. Cancel');

      // Prompt user to select which brick to use
      final selected = await _promptUserSelection(searchResults);
      _logger.info('Using: ${selected.repositoryName}/${selected.fullPath}');
      return selected.brick;
    }

    // Try to find brick in mason.yaml as fallback
    final masonYaml = await _loadMasonYaml();
    if (masonYaml != null) {
      final bricksNode = masonYaml['bricks'];
      if (bricksNode is Map && bricksNode.containsKey(component)) {
        final brickConfig = bricksNode[component];

        // Handle different brick source types
        if (brickConfig is Map && brickConfig.containsKey('git')) {
          final gitConfig = brickConfig['git'];
          if (gitConfig is Map) {
            final url = gitConfig['url'] as String;
            final gitPath = gitConfig.containsKey('path')
                ? GitPath(url, path: gitConfig['path'] as String)
                : GitPath(url);
            return Brick.git(gitPath);
          }
        } else if (brickConfig is Map && brickConfig.containsKey('path')) {
          final brickPath = brickConfig['path'] as String;
          return Brick.path(brickPath);
        }
      }
    }

    // No brick found anywhere
    final repositories = await _repositoryService.getRepositories();
    if (repositories.isEmpty) {
      throw Exception(
        'Brick "$component" not found. No repositories configured.\n'
        'Add a repository with: fpx repository add --name <name> --url <url>\n'
        'Or add the brick to mason.yaml, or use --source option.\n'
        'Run "fpx init" to create a mason.yaml file.',
      );
    } else {
      final repoList = repositories.keys.join(', ');
      throw Exception(
        'Brick "$component" not found in configured repositories: $repoList\n'
        'Try using a specific repository: fpx add @repo/$component\n'
        'Or add the brick to mason.yaml, or use --source option.\n'
        'Run "fpx repository list" to see available repositories.',
      );
    }
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
  #     url: https://github.com/unping/unping-ui.git
  #     path: bricks/button
  # 
  # widget:
  #   path: ./bricks/widget
''';

      await masonYamlFile.writeAsString(defaultMasonYaml);
      _logger.success('✅ Created mason.yaml with default configuration');
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

  Future<BrickSearchResult> _promptUserSelection(
      List<BrickSearchResult> searchResults) async {
    while (true) {
      stdout.write(
          '\nPlease select a brick (1-${searchResults.length}, or 0 to cancel): ');
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
        throw Exception('User cancelled brick selection');
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
