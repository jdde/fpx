import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';

/// Utility function to convert YamlMap to Map<String, dynamic>
dynamic _convertYamlToMap(dynamic yamlData) {
  if (yamlData is Map) {
    final result = <String, dynamic>{};
    for (final entry in yamlData.entries) {
      result[entry.key.toString()] = _convertYamlToMap(entry.value);
    }
    return result;
  } else if (yamlData is List) {
    return yamlData.map((item) => _convertYamlToMap(item)).toList();
  } else {
    return yamlData;
  }
}

/// {@template repository_command}
/// A [Command] to manage brick repositories.
/// {@endtemplate}
class RepositoryCommand extends Command<int> {
  /// {@macro repository_command}
  RepositoryCommand({
    required Logger logger,
  }) : _logger = logger {
    addSubcommand(RepositoryAddCommand(logger: _logger));
    addSubcommand(RepositoryRemoveCommand(logger: _logger));
    addSubcommand(RepositoryListCommand(logger: _logger));
    addSubcommand(RepositoryUpdateCommand(logger: _logger));
  }

  @override
  String get description => 'Manage brick repositories';

  @override
  String get name => 'repository';

  @override
  List<String> get aliases => ['repo'];

  final Logger _logger;
}

/// {@template repository_add_command}
/// A [Command] to add a brick repository.
/// {@endtemplate}
class RepositoryAddCommand extends Command<int> {
  /// {@macro repository_add_command}
  RepositoryAddCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Repository name/alias (auto-generated from URL if not provided)',
        mandatory: false,
      )
      ..addOption(
        'url',
        abbr: 'u',
        help: 'Repository URL (GitHub URLs will auto-detect path)',
        mandatory: true,
      );
  }

  @override
  String get description => 'Add a brick repository';

  @override
  String get name => 'add';

  @override
  String get invocation => 'fpx repository add [--name <name>] --url <url>';

  final Logger _logger;

  @override
  Future<int> run() async {
    final repositoryUrl = argResults!['url'] as String;
    final providedName = argResults!['name'] as String?;

    // Parse repository name from URL if not provided
    final repositoryName = providedName ?? _parseRepositoryName(repositoryUrl);

    try {
      final parsedRepo = _parseRepositoryUrl(repositoryUrl);

      // Clone the repository locally for processing
      _logger.info('🔄 Cloning repository "$repositoryName"...');
      final repositoryService = RepositoryService(logger: _logger);
      
      try {
        await repositoryService.cloneRepository(repositoryName, parsedRepo.url);
        _logger.info('✅ Repository cloned successfully');
        
        // Auto-detect components in the repository
        final components = await repositoryService.detectComponents(repositoryName);
        
        _logger.success('✅ Successfully added repository "$repositoryName"');
        _logger.info('   URL: ${parsedRepo.url}');
        _logger.info('   Path: ${parsedRepo.path}');
        
        if (components.isNotEmpty) {
          _logger.info('📦 Detected components: ${components.join(', ')}');
        } else {
          _logger.warn('⚠️  No components detected in repository');
        }
      } catch (cloneError) {
        _logger.err('❌ Failed to clone repository: $cloneError');
        return ExitCode.software.code;
      }

      return ExitCode.success.code;
    } catch (e) {
      _logger.err('❌ Failed to add repository: $e');
      return ExitCode.software.code;
    }
  }

  /// Parses a repository name from the URL (first part after top level domain)
  String _parseRepositoryName(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      if (pathSegments.isNotEmpty) {
        // Get the first path segment (repository owner/organization)
        return pathSegments[0];
      }

      // Fallback: use the host without www prefix
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      // If parsing fails, use a sanitized version of the URL
      return url.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
    }
  }

  /// Parses a repository URL and extracts the base URL and path to bricks
  RepositoryInfo _parseRepositoryUrl(String url) {
    final uri = Uri.parse(url);

    // Handle GitHub URLs with tree/branch/path structure
    if (uri.host == 'github.com') {
      final pathSegments = uri.pathSegments;

      if (pathSegments.length >= 2) {
        final owner = pathSegments[0];
        final repo = pathSegments[1];

        // Base repository URL
        final baseUrl = 'https://github.com/$owner/$repo.git';

        // Check for tree/branch/path structure
        if (pathSegments.length >= 4 && pathSegments[2] == 'tree') {
          // URL like: https://github.com/unping/unping-ui/tree/master/bricks
          final branchAndPath = pathSegments.skip(3).join('/');
          final pathParts = branchAndPath.split('/');

          if (pathParts.length > 1) {
            // Skip branch name and get the path
            final bricksPath = pathParts.skip(1).join('/');
            return RepositoryInfo(url: baseUrl, path: bricksPath);
          }
        }

        // Check for blob/branch/path structure (single file)
        if (pathSegments.length >= 4 && pathSegments[2] == 'blob') {
          // URL like: https://github.com/unping/unping-ui.git/blob/master/bricks/greeting/brick.yaml
          final branchAndPath = pathSegments.skip(3).join('/');
          final pathParts = branchAndPath.split('/');

          if (pathParts.length > 1) {
            // Skip branch name and get directory path
            final bricksPath =
                pathParts.take(pathParts.length - 1).skip(1).join('/');
            return RepositoryInfo(url: baseUrl, path: bricksPath);
          }
        }

        // Default fallback
        return RepositoryInfo(url: baseUrl, path: 'bricks');
      }
    }

    // For non-GitHub URLs or malformed GitHub URLs, use as-is with default path
    return RepositoryInfo(url: url, path: 'bricks');
  }

}

/// {@template repository_remove_command}
/// A [Command] to remove a brick repository.
/// {@endtemplate}
class RepositoryRemoveCommand extends Command<int> {
  /// {@macro repository_remove_command}
  RepositoryRemoveCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Repository name to remove',
      mandatory: true,
    );
  }

  @override
  String get description => 'Remove a brick repository';

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => ['rm'];

  @override
  String get invocation => 'fpx repository remove --name <name>';

  final Logger _logger;

  @override
  Future<int> run() async {
    final repositoryName = argResults!['name'] as String;

    try {
      final repositoryService = RepositoryService(logger: _logger);
      final removed = await _removeRepository(repositoryName, repositoryService);
      if (removed) {
        _logger.success('✅ Successfully removed repository "$repositoryName"');
      } else {
        _logger.warn('⚠️  Repository "$repositoryName" not found');
      }
      return ExitCode.success.code;
    } catch (e) {
      _logger.err('❌ Failed to remove repository: $e');
      return ExitCode.software.code;
    }
  }

  Future<bool> _removeRepository(String name, RepositoryService repositoryService) async {
    // Check if repository exists
    if (!await repositoryService.isRepositoryCloned(name)) {
      return false;
    }

    // Remove the repository directory
    final repositoryPath = repositoryService.getRepositoryPath(name);
    final repoDir = Directory(repositoryPath);
    await repoDir.delete(recursive: true);
    
    _logger.info('🗑️  Removed repository directory: $repositoryPath');
    return true;
  }
}

/// {@template repository_list_command}
/// A [Command] to list configured brick repositories.
/// {@endtemplate}
class RepositoryListCommand extends Command<int> {
  /// {@macro repository_list_command}
  RepositoryListCommand({
    required Logger logger,
  }) : _logger = logger;

  @override
  String get description => 'List configured brick repositories';

  @override
  String get name => 'list';

  @override
  List<String> get aliases => ['ls'];

  final Logger _logger;

  @override
  Future<int> run() async {
    try {
      final config = await _loadRepositoryConfig();
      final repositories = config['repositories'] as Map<String, dynamic>?;

      if (repositories == null || repositories.isEmpty) {
        _logger.info('📋 No repositories configured yet');
        _logger.info(
            '💡 Add a repository with: fpx repository add --url <url> [--name <name>]');
        _logger.info('');
        _logger.info('Example repositories:');
        _logger.info(
            '  fpx repository add --url https://github.com/Unping/unping-ui');
        _logger.info(
            '  fpx repository add --name my-bricks --url https://github.com/Unping/unping-ui');
        return ExitCode.success.code;
      }

      final repositoryService = RepositoryService(logger: _logger);
      
      _logger.info('Configured repositories:');
      for (final entry in repositories.entries) {
        final repoName = entry.key;
        final repoConfig = entry.value as Map<String, dynamic>;
        final url = repoConfig['url'] as String;
        final path = repoConfig['path'] as String;

        _logger.info('  $repoName:');
        _logger.info('    URL: $url');
        _logger.info('    Path: $path');
        
        // Show if repository is cloned locally
        final isCloned = await repositoryService.isRepositoryCloned(repoName);
        _logger.info('    Status: ${isCloned ? '✅ Cloned locally' : '❌ Not cloned'}');
        
        // Show detected components if repository is cloned
        if (isCloned) {
          try {
            final components = await repositoryService.detectComponents(repoName);
            if (components.isNotEmpty) {
              _logger.info('    Components: ${components.join(', ')}');
            } else {
              _logger.info('    Components: None detected');
            }
          } catch (e) {
            _logger.info('    Components: Error detecting ($e)');
          }
        }
        _logger.info(''); // Empty line for spacing
      }

      return ExitCode.success.code;
    } catch (e) {
      _logger.err('❌ Failed to list repositories: $e');
      return ExitCode.software.code;
    }
  }

  Future<Map<String, dynamic>> _loadRepositoryConfig() async {
    final configFile = File(RepositoryService.configFileName);
    if (!await configFile.exists()) {
      return <String, dynamic>{};
    }

    try {
      final content = await configFile.readAsString();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map) {
        return _convertYamlToMap(yamlMap) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }
}

/// Repository information parsed from URL
class RepositoryInfo {
  const RepositoryInfo({
    required this.url,
    required this.path,
  });

  final String url;
  final String path;
}

/// {@template repository_update_command}
/// A [Command] to update a brick repository.
/// {@endtemplate}
class RepositoryUpdateCommand extends Command<int> {
  /// {@macro repository_update_command}
  RepositoryUpdateCommand({
    required Logger logger,
  }) : _logger = logger {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Repository name to update (updates all if not specified)',
      mandatory: false,
    );
  }

  @override
  String get description => 'Update a brick repository';

  @override
  String get name => 'update';

  @override
  String get invocation => 'fpx repository update [--name <name>]';

  final Logger _logger;

  @override
  Future<int> run() async {
    final repositoryName = argResults!['name'] as String?;

    try {
      final config = await _loadRepositoryConfig();
      final repositories = config['repositories'] as Map<String, dynamic>?;

      if (repositories == null || repositories.isEmpty) {
        _logger.warn('⚠️  No repositories configured');
        return ExitCode.success.code;
      }

      final repositoryService = RepositoryService(logger: _logger);

      if (repositoryName != null) {
        // Update specific repository
        if (!repositories.containsKey(repositoryName)) {
          _logger.err('❌ Repository "$repositoryName" not found');
          return ExitCode.usage.code;
        }

        await _updateRepository(repositoryService, repositoryName);
      } else {
        // Update all repositories
        for (final repoName in repositories.keys) {
          await _updateRepository(repositoryService, repoName);
        }
      }

      return ExitCode.success.code;
    } catch (e) {
      _logger.err('❌ Failed to update repository: $e');
      return ExitCode.software.code;
    }
  }

  Future<void> _updateRepository(RepositoryService repositoryService, String repoName) async {
    try {
      _logger.info('🔄 Updating repository "$repoName"...');
      
      if (await repositoryService.isRepositoryCloned(repoName)) {
        await repositoryService.updateRepository(repoName);
      } else {
        _logger.warn('⚠️  Repository "$repoName" not cloned locally, skipping update');
        return;
      }
      
      // Re-detect components after update
      final components = await repositoryService.detectComponents(repoName);
      
      _logger.success('✅ Successfully updated repository "$repoName"');
      if (components.isNotEmpty) {
        _logger.info('📦 Detected components: ${components.join(', ')}');
      }
    } catch (e) {
      _logger.err('❌ Failed to update repository "$repoName": $e');
    }
  }

  Future<Map<String, dynamic>> _loadRepositoryConfig() async {
    final configFile = File(RepositoryService.configFileName);
    if (!await configFile.exists()) {
      return <String, dynamic>{};
    }

    try {
      final content = await configFile.readAsString();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map) {
        return _convertYamlToMap(yamlMap) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }
}
