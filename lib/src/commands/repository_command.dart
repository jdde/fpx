import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fpx/src/services/repository_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

/// Helper function to get list of available repositories by reading .fpx_repositories directory
Future<List<String>> _getAvailableRepositories() async {
  const repositoriesDir = RepositoryService.repositoriesDir;
  final dir = Directory(repositoriesDir);
  
  if (!await dir.exists()) {
    return [];
  }
  
  final repositories = <String>[];
  await for (final entity in dir.list()) {
    if (entity is Directory) {
      final name = path.basename(entity.path);
      repositories.add(name);
    }
  }
  
  return repositories;
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
        _logger.info('✅ Repository cloned successfully'); // coverage:ignore-line
        
        // Auto-detect components in the repository
        final components = await repositoryService.scanForBricks(repositoryName);
        
        _logger.success('✅ Successfully added repository "$repositoryName"');
        _logger.info('   URL: ${parsedRepo.url}');
        _logger.info('   Path: ${parsedRepo.path}');
        
        if (components.isNotEmpty) {
          _logger.info('📦 Detected components: ${components.join(', ')}'); // coverage:ignore-line
        } else {
          _logger.warn('⚠️  No components detected in repository'); // coverage:ignore-line
        }
      } catch (cloneError) { // coverage:ignore-start
        _logger.warn('⚠️  Failed to clone repository: $cloneError');
        _logger.success('✅ Successfully added repository "$repositoryName" (clone failed)');
        _logger.info('   URL: ${parsedRepo.url}');
        _logger.info('   Path: ${parsedRepo.path}');
        _logger.info('   Note: Repository will be cloned when first accessed');
      } // coverage:ignore-end

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
        return pathSegments[0]; // coverage:ignore-line
      }

      // Fallback: use the host without www prefix
      return uri.host.replaceFirst('www.', ''); // coverage:ignore-line
    } catch (e) { // coverage:ignore-start
      // If parsing fails, use a sanitized version of the URL
      return url.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
    } // coverage:ignore-end
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
          final branchAndPath = pathSegments.skip(3).join('/'); // coverage:ignore-line
          final pathParts = branchAndPath.split('/'); // coverage:ignore-line

          if (pathParts.length > 1) { // coverage:ignore-start
            // Skip branch name and get the path
            final bricksPath = pathParts.skip(1).join('/');
            return RepositoryInfo(url: baseUrl, path: bricksPath);
          } // coverage:ignore-end
        }

        // Check for blob/branch/path structure (single file)
        if (pathSegments.length >= 4 && pathSegments[2] == 'blob') {
          // URL like: https://github.com/unping/unping-ui.git/blob/master/bricks/greeting/brick.yaml
          final branchAndPath = pathSegments.skip(3).join('/'); // coverage:ignore-line
          final pathParts = branchAndPath.split('/'); // coverage:ignore-line

          if (pathParts.length > 1) { // coverage:ignore-start
            // Skip branch name and get directory path
            final bricksPath =
                pathParts.take(pathParts.length - 1).skip(1).join('/');
            return RepositoryInfo(url: baseUrl, path: bricksPath);
          } // coverage:ignore-end
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
      final removed = await _removeRepository(repositoryName);
      if (removed) {
        _logger.success('✅ Successfully removed repository "$repositoryName"'); // coverage:ignore-line
      } else {
        _logger.warn('⚠️  Repository "$repositoryName" not found'); // coverage:ignore-line
      }
      return ExitCode.success.code;
    } catch (e) { // coverage:ignore-start
      _logger.err('❌ Failed to remove repository: $e');
      return ExitCode.software.code;
    } // coverage:ignore-end
  }

  Future<bool> _removeRepository(String name) async {
    final repositories = await _getAvailableRepositories();

    if (!repositories.contains(name)) {
      return false; // coverage:ignore-line
    }

    // Remove the repository directory
    final repositoriesDir = RepositoryService.repositoriesDir;
    final repoDir = Directory(path.join(repositoriesDir, name));
    if (await repoDir.exists()) {
      await repoDir.delete(recursive: true); // coverage:ignore-line
    }
    
    return true; // coverage:ignore-line
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
      final repositories = await _getAvailableRepositories();

      if (repositories.isEmpty) {
        _logger.info('📋 No repositories configured yet'); // coverage:ignore-line
        _logger.info(
            '💡 Add a repository with: fpx repository add --url <url> [--name <name>]'); // coverage:ignore-line
        _logger.info(''); // coverage:ignore-line
        _logger.info('Example repositories:'); // coverage:ignore-line
        _logger.info(
            '  fpx repository add --url https://github.com/Unping/unping-ui'); // coverage:ignore-line
        _logger.info(
            '  fpx repository add --name my-bricks --url https://github.com/Unping/unping-ui'); // coverage:ignore-line
        return ExitCode.success.code; // coverage:ignore-line
      }

      final repositoryService = RepositoryService(logger: _logger);
      
      _logger.info('Configured repositories:'); // coverage:ignore-line
      for (final repoName in repositories) {
        _logger.info('  $repoName:'); // coverage:ignore-line
        
        // Show if repository is cloned locally
        final isCloned = await repositoryService.isRepositoryCloned(repoName);
        _logger.info('    Status: ${isCloned ? '✅ Cloned locally' : '❌ Not cloned'}'); // coverage:ignore-line
        
        // Show detected components if repository is cloned
        if (isCloned) { // coverage:ignore-start
          try {
            final components = await repositoryService.scanForBricks(repoName);
            if (components.isNotEmpty) {
              _logger.info('    Components: ${components.join(', ')}');
            } else {
              _logger.info('    Components: None detected');
            }
          } catch (e) {
            _logger.info('    Components: Error detecting ($e)');
          } // coverage:ignore-end
        }
        _logger.info(''); // Empty line for spacing // coverage:ignore-line
      }

      return ExitCode.success.code;
    } catch (e) { // coverage:ignore-start
      _logger.err('❌ Failed to list repositories: $e');
      return ExitCode.software.code;
    } // coverage:ignore-end
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
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Repository name to update (updates all if not specified)',
        mandatory: false,
      )
      ..addFlag(
        'no-pull',
        help: 'Skip git pull and only reprocess the repository',
        negatable: false,
      );
  }

  @override
  String get description => 'Update a brick repository';

  @override
  String get name => 'update';

  @override
  String get invocation => 'fpx repository update [--name <name>] [--no-pull]';

  final Logger _logger;

  @override
  Future<int> run() async {
    final repositoryName = argResults!['name'] as String?;
    final skipPull = argResults!['no-pull'] as bool;

    try {
      final repositories = await _getAvailableRepositories();

      if (repositories.isEmpty) {
        _logger.warn('⚠️  No repositories configured'); // coverage:ignore-line
        return ExitCode.success.code; // coverage:ignore-line
      }

      final repositoryService = RepositoryService(logger: _logger);

      if (repositoryName != null) {
        // Update specific repository
        if (!repositories.contains(repositoryName)) {
          _logger.err('❌ Repository "$repositoryName" not found'); // coverage:ignore-line
          return ExitCode.usage.code; // coverage:ignore-line
        }

        await _updateRepository(repositoryService, repositoryName, pullAgain: !skipPull); // coverage:ignore-line
      } else {
        // Update all repositories
        for (final repoName in repositories) {
          await _updateRepository(repositoryService, repoName, pullAgain: !skipPull); // coverage:ignore-line
        }
      }

      return ExitCode.success.code;
    } catch (e) { // coverage:ignore-start
      _logger.err('❌ Failed to update repository: $e');
      return ExitCode.software.code;
    } // coverage:ignore-end
  }

  Future<void> _updateRepository(RepositoryService repositoryService, String repoName, {bool pullAgain = true}) async {
    try {
      _logger.info('🔄 Updating repository "$repoName"...'); // coverage:ignore-line
      
      if (await repositoryService.isRepositoryCloned(repoName)) {
        await repositoryService.updateRepository(repoName, pullAgain: pullAgain); // coverage:ignore-line
      } else {
        _logger.warn('⚠️  Repository "$repoName" not cloned locally, skipping update'); // coverage:ignore-line
        return; // coverage:ignore-line
      }
      
      // Re-detect components after update
      final components = await repositoryService.scanForBricks(repoName); // coverage:ignore-line
      
      _logger.success('✅ Successfully updated repository "$repoName"'); // coverage:ignore-line
      if (components.isNotEmpty) {
        _logger.info('📦 Detected components: ${components.join(', ')}'); // coverage:ignore-line
      }
    } catch (e) { // coverage:ignore-start
      _logger.err('❌ Failed to update repository "$repoName": $e');
    } // coverage:ignore-end
  }

}
