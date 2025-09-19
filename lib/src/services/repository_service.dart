import 'dart:io';

import 'package:mason/mason.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'repository_post_clone_service.dart';

/// Service for managing and searching brick repositories.
class RepositoryService {
  /// Constructor
  RepositoryService({
    Logger? logger,
  }) : _logger = logger ?? Logger();

  static const String configFileName = '.fpx_repositories.yaml';
  static const String _userConfigFileName = '.fpx_repositories.local.yaml';
  static const String _repositoriesDir = '.fpx_repositories';

  final Logger _logger;
  late final RepositoryPostCloneService _postCloneService = 
      RepositoryPostCloneService(logger: _logger);

  /// Load repository configuration from the actual cloned repositories.
  Future<Map<String, dynamic>> loadRepositoryConfig() async {
    final repositoriesDir = Directory(_repositoriesDir);
    if (!await repositoriesDir.exists()) {
      return {'repositories': <String, dynamic>{}};
    }

    final repositories = <String, dynamic>{};
    
    // Scan the .fpx_repositories directory for cloned repositories
    await for (final entity in repositoriesDir.list()) {
      if (entity is Directory) {
        final repoName = path.basename(entity.path);
        
        // Try to get repository URL and path from git remote and fpx.yaml
        String? repoUrl;
        String? repoPath;
        
        try {
          final result = await Process.run(
            'git',
            ['remote', 'get-url', 'origin'],
            workingDirectory: entity.path,
          );
          if (result.exitCode == 0) {
            repoUrl = result.stdout.toString().trim();
          }
        } catch (e) {
          // If we can't get git remote, that's okay, we'll use a default
        }
        
        // Read the path from fpx.yaml
        try {
          final fpxConfig = await readFpxConfig(repoName);
          if (fpxConfig != null && fpxConfig['bricks'] is Map) {
            final bricksConfig = fpxConfig['bricks'] as Map;
            repoPath = bricksConfig['path'] as String?;
          }
        } catch (e) {
          // If we can't read fpx.yaml, we'll skip this repository
          _logger.detail('Failed to read fpx.yaml for repository $repoName: $e');
          continue;
        }
        
        // Skip repositories that don't have a valid bricks path configured
        if (repoPath == null) {
          _logger.detail('Repository $repoName does not have a valid bricks.path in fpx.yaml, skipping');
          continue;
        }
        
        repositories[repoName] = {
          'url': repoUrl ?? 'unknown',
          'path': repoPath,
        };
      }
    }

    return {'repositories': repositories};
  }

  /// Find a brick by name, optionally with repository namespace.
  ///
  /// Supports formats:
  /// - `brick_name` - searches all repositories
  /// - `@repo/brick_name` - searches specific repository
  /// - `@repo/path/brick_name` - searches specific repository with path
  Future<List<BrickSearchResult>> findBrick(String brickIdentifier) async {
    final config = await loadRepositoryConfig();
    final repositories = config['repositories'] as Map<String, dynamic>?;

    if (repositories == null || repositories.isEmpty) {
      return [];
    }

    final results = <BrickSearchResult>[];

    // Parse brick identifier
    if (brickIdentifier.startsWith('@')) {
      // Specific repository format: @repo/brick or @repo/path/brick
      final parts = brickIdentifier.substring(1).split('/');
      if (parts.length >= 2) {
        final repoName = parts[0];
        final brickPath = parts.sublist(1).join('/');

        if (repositories.containsKey(repoName)) {
          final repoConfig = _convertYamlMapToMap(repositories[repoName] as Map);
          
          try {
            // Ensure repository is cloned before searching
            await _ensureRepositoryCloned(repoName, repoConfig);
            
            final brick = await _createBrickFromRepository(
              repoName,
              repoConfig,
              brickPath,
            );
            if (brick != null) {
              results.add(BrickSearchResult(
                brickName: brickPath.split('/').last,
                repositoryName: repoName,
                brick: brick,
                fullPath: brickPath,
              ));
            }
          } catch (e) {
            _logger.detail('Failed to access repository $repoName: $e');
            // Continue without adding results for this repository
          }
        }
      }
    } else {
      // Search all repositories for the brick name
      for (final entry in repositories.entries) {
        final repoName = entry.key;
        final repoConfig = _convertYamlMapToMap(entry.value as Map);

        try {
          // Ensure repository is cloned before searching
          await _ensureRepositoryCloned(repoName, repoConfig);
          
          // Check if component exists in auto-detected components
          final detectedComponents = await detectComponents(repoName);
          if (detectedComponents.contains(brickIdentifier)) {
            final brick = await _createBrickFromRepository(
              repoName,
              repoConfig,
              brickIdentifier,
            );

            if (brick != null) {
              results.add(BrickSearchResult(
                brickName: brickIdentifier,
                repositoryName: repoName,
                brick: brick,
                fullPath: brickIdentifier,
              ));
            }
          }
        } catch (e) {
          _logger.detail('Failed to access repository $repoName: $e');
          // Continue searching other repositories
        }
      }
    }

    return results;
  }

  /// Ensure a repository is cloned locally, clone it if it's not.
  Future<void> _ensureRepositoryCloned(String repoName, Map<String, dynamic> repoConfig) async {
    if (!await isRepositoryCloned(repoName)) {
      final url = repoConfig['url'] as String;
      await cloneRepository(repoName, url);
    }
  }

  /// Create a brick from repository configuration.
  Future<Brick?> _createBrickFromRepository(
    String repoName,
    Map<String, dynamic> repoConfig,
    String brickPath,
  ) async {
    try {
      // Always ensure repository is cloned
      await _ensureRepositoryCloned(repoName, repoConfig);
      
      // Check if repository is cloned locally
      if (await isRepositoryCloned(repoName)) {
        final repoPath = getRepositoryPath(repoName);
        
        // First, try to find the component directory structure
        // Look for: lib/src/components/{brickPath}/brick.yaml (with __brick__ subdirectory)
        final componentPath = path.join(repoPath, 'lib', 'src', 'components', brickPath);
        final componentBrickYaml = path.join(componentPath, 'brick.yaml');
        final componentBrickDir = path.join(componentPath, '__brick__');
        
        if (await File(componentBrickYaml).exists() && await Directory(componentBrickDir).exists()) {
          _logger.detail('Found brick at component path: $componentPath');
          return Brick.path(componentPath);
        }
        
        // Get component configuration from fpx.yaml
        final componentConfig = await getComponentConfig(repoName, brickPath);
        
        if (componentConfig != null) {
          // Use fpx.yaml configuration to determine brick path
          final configuredPath = componentConfig['path'] as String?;
          if (configuredPath != null) {
            final localPath = path.join(repoPath, configuredPath);
            if (await Directory(localPath).exists()) {
              _logger.detail('Found brick at configured path: $localPath');
              return Brick.path(localPath);
            }
          }
        }
        
        // Fallback: try standard brick location in cloned repo
        final basePath = repoConfig['path'] as String;
        final fullBrickPath = '$basePath/$brickPath';
        final localPath = path.join(repoPath, fullBrickPath);
        
        if (await Directory(localPath).exists() || await File(path.join(localPath, 'brick.yaml')).exists()) {
          _logger.detail('Found brick at standard path: $localPath');
          return Brick.path(localPath);
        }
        
        _logger.detail('No brick found for $brickPath in repository $repoName');
        return null;
      }
      
      _logger.err('Repository $repoName is not cloned locally');
      return null;
    } catch (e) {
      _logger.detail('Error creating brick from repository: $e'); // coverage:ignore-line
      return null; // coverage:ignore-line
    }
  }

  /// Get all configured repositories.
  Future<Map<String, RepositoryInfo>> getRepositories() async {
    final config = await loadRepositoryConfig();
    final repositories = config['repositories'] as Map<String, dynamic>?;

    if (repositories == null) {
      return {};
    }

    final result = <String, RepositoryInfo>{};
    for (final entry in repositories.entries) {
      final repoConfig = _convertYamlMapToMap(entry.value as Map);
      result[entry.key] = RepositoryInfo(
        name: entry.key,
        url: repoConfig['url'] as String,
        path: repoConfig['path'] as String,
      );
    }

    return result;
  }

  /// Initialize default repositories.
  Future<void> initializeDefaultRepositories() async {
    // No longer needed since we load from actual cloned directories
  }

  /// Clone a repository locally for processing.
  Future<Directory> cloneRepository(String name, String url) async {
    final repoDir = Directory(path.join(_repositoriesDir, name));
    
    // Remove existing directory if it exists
    if (await repoDir.exists()) {
      await repoDir.delete(recursive: true);
    }
    
    // Create repositories directory
    await Directory(_repositoriesDir).create(recursive: true);
    
    // Ensure .fpx_repositories is in .gitignore
    await _ensureGitignoreEntry();
    
    // Clone the repository
    final result = await Process.run( // coverage:ignore-line
      'git',
      ['clone', url, repoDir.path],
      workingDirectory: Directory.current.path,
    );
    
    if (result.exitCode != 0) { // coverage:ignore-line
      throw Exception('Failed to clone repository: ${result.stderr}'); // coverage:ignore-line
    }
    
    // Apply post-clone processing
    await _postCloneService.processClonedRepository(
      repositoryName: name,
      repositoryPath: repoDir.path,
      repositoryUrl: url,
    );
    
    // Validate that the repository has a valid fpx.yaml with bricks.path
    await _validateRepositoryStructure(name);
    
    return repoDir;
  }

  /// Validate that a cloned repository has the required fpx.yaml structure
  Future<void> _validateRepositoryStructure(String repositoryName) async {
    final fpxConfig = await readFpxConfig(repositoryName);
    
    if (fpxConfig == null) {
      throw Exception(
        'Repository "$repositoryName" does not contain fpx.yaml. '
        'This file is required to define the bricks configuration.',
      );
    }
    
    final bricksConfig = fpxConfig['bricks'];
    if (bricksConfig is! Map) {
      throw Exception(
        'Repository "$repositoryName" fpx.yaml does not contain a "bricks" section. '
        'This section is required to define repository configuration.',
      );
    }
    
    final bricksPath = bricksConfig['path'] as String?;
    if (bricksPath == null || bricksPath.isEmpty) {
      throw Exception(
        'Repository "$repositoryName" fpx.yaml does not specify "bricks.path". '
        'This field is required to define where components are located.',
      );
    }
    
    // Verify the bricks path actually exists in the repository
    final repoPath = getRepositoryPath(repositoryName);
    final bricksDir = Directory(path.join(repoPath, bricksPath));
    if (!await bricksDir.exists()) {
      throw Exception(
        'Repository "$repositoryName" specifies bricks.path "$bricksPath" '
        'but this directory does not exist in the repository.',
      );
    }
    
    _logger.detail('✅ Repository "$repositoryName" validation successful. Bricks path: $bricksPath');
  }

  /// Ensure .fpx_repositories is added to .gitignore
  Future<void> _ensureGitignoreEntry() async {
    final gitignoreFile = File('.gitignore');
    
    if (await gitignoreFile.exists()) {
      final content = await gitignoreFile.readAsString();
      if (!content.contains('.fpx_repositories')) {
        await gitignoreFile.writeAsString('$content\n# fpx repositories\n.fpx_repositories/\n');
        _logger.detail('Added .fpx_repositories/ to .gitignore');
      }
    } else {
      await gitignoreFile.writeAsString('# fpx repositories\n.fpx_repositories/\n');
      _logger.detail('Created .gitignore with .fpx_repositories/');
    }
  }

  /// Update an existing cloned repository.
  Future<void> updateRepository(String name) async {
    final repoDir = Directory(path.join(_repositoriesDir, name));
    
    if (!await repoDir.exists()) {
      throw Exception('Repository "$name" not found locally');
    }
    
    // Pull latest changes
    final result = await Process.run( // coverage:ignore-line
      'git',
      ['pull'],
      workingDirectory: repoDir.path,
    );
    
    if (result.exitCode != 0) { // coverage:ignore-line
      throw Exception('Failed to update repository: ${result.stderr}'); // coverage:ignore-line
    }
  }

  /// Get the local directory path for a cloned repository.
  String getRepositoryPath(String name) {
    return path.join(_repositoriesDir, name);
  }

  /// Check if a repository is cloned locally.
  Future<bool> isRepositoryCloned(String name) async {
    final repoDir = Directory(path.join(_repositoriesDir, name));
    return await repoDir.exists();
  }

  /// Read and parse fpx.yaml from a cloned repository.
  Future<Map<String, dynamic>?> readFpxConfig(String repositoryName) async {
    final repoPath = getRepositoryPath(repositoryName);
    final fpxConfigFile = File(path.join(repoPath, 'fpx.yaml'));
    
    if (!await fpxConfigFile.exists()) {
      return null;
    }
    
    try {
      final content = await fpxConfigFile.readAsString();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map) {
        return _convertYamlMapToMap(yamlMap);
      }
    } catch (e) {
      // Handle YAML parsing errors // coverage:ignore-line
    }
    
    return null;
  }

  /// Auto-detect components in a cloned repository based on fpx.yaml.
  Future<List<String>> detectComponents(String repositoryName) async {
    final fpxConfig = await readFpxConfig(repositoryName);
    final components = <String>[];
    
    if (fpxConfig == null) {
      // Fallback: scan for brick.yaml files in the repository
      return await _scanForBricks(repositoryName);
    }
    
    // Parse components from fpx.yaml
    final componentsConfig = fpxConfig['components'];
    if (componentsConfig is Map) {
      components.addAll(componentsConfig.keys.cast<String>());
    }
    
    // Also check for a 'bricks' section for backward compatibility
    final bricksConfig = fpxConfig['bricks'];
    if (bricksConfig is Map) {
      // Check if bricks contains component definitions or just configuration
      bool hasComponentDefinitions = false;
      for (final key in bricksConfig.keys) {
        if (key != 'path' && key != 'variables') {
          components.add(key as String);
          hasComponentDefinitions = true;
        }
      }
      
      // If bricks section only contains configuration (like 'path'), scan for actual components
      if (!hasComponentDefinitions && components.isEmpty) {
        return await _scanForBricks(repositoryName);
      }
    }
    
    // If no components found in fpx.yaml, fall back to scanning
    if (components.isEmpty) {
      return await _scanForBricks(repositoryName);
    }
    
    return components;
  }

  /// Scan repository directory for brick.yaml files.
  Future<List<String>> _scanForBricks(String repositoryName) async {
    final repoPath = getRepositoryPath(repositoryName);
    final repoDir = Directory(repoPath);
    final components = <String>[];
    
    if (!await repoDir.exists()) {
      return components;
    }
    
    // Look for brick.yaml files recursively
    await for (final entity in repoDir.list(recursive: true)) {
      if (entity is File && path.basename(entity.path) == 'brick.yaml') {
        // Extract component name from the directory structure
        final relativePath = path.relative(entity.path, from: repoPath);
        final dirPath = path.dirname(relativePath);
        
        // Skip if it's in the root or too nested
        final pathParts = path.split(dirPath);
        if (pathParts.length >= 1 && pathParts.first != '.') {
          final componentName = pathParts.last;
          if (!components.contains(componentName)) {
            components.add(componentName);
          }
        }
      }
    }
    
    return components;
  }

  /// Get component configuration from fpx.yaml.
  Future<Map<String, dynamic>?> getComponentConfig(
    String repositoryName,
    String componentName,
  ) async {
    final fpxConfig = await readFpxConfig(repositoryName);
    if (fpxConfig == null) return null;
    
    // Check components section first
    final componentsConfig = fpxConfig['components'];
    if (componentsConfig is Map && componentsConfig.containsKey(componentName)) {
      return Map<String, dynamic>.from(componentsConfig[componentName] as Map);
    }
    
    // Check bricks section for backward compatibility
    final bricksConfig = fpxConfig['bricks'];
    if (bricksConfig is Map && bricksConfig.containsKey(componentName)) {
      return Map<String, dynamic>.from(bricksConfig[componentName] as Map);
    }
    
    return null;
  }

  /// Recursively converts a YamlMap to a Map<String, dynamic>
  Map<String, dynamic> _convertYamlMapToMap(Map<dynamic, dynamic> yamlMap) {
    final result = <String, dynamic>{};
    yamlMap.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] = _convertYamlMapToMap(value);
      } else if (value is List) {
        result[key.toString()] = _convertYamlListToList(value);
      } else {
        result[key.toString()] = value;
      }
    });
    return result;
  }

  /// Recursively converts a YamlList to a List<dynamic>
  List<dynamic> _convertYamlListToList(List<dynamic> yamlList) {
    final result = <dynamic>[];
    for (final item in yamlList) {
      if (item is Map) {
        result.add(_convertYamlMapToMap(item));
      } else if (item is List) {
        result.add(_convertYamlListToList(item));
      } else {
        result.add(item);
      }
    }
    return result;
  }
}

/// Result of a brick search operation.
class BrickSearchResult {
  const BrickSearchResult({
    required this.brickName,
    required this.repositoryName,
    required this.brick,
    required this.fullPath,
  });

  /// The name of the brick.
  final String brickName;

  /// The name of the repository where the brick was found.
  final String repositoryName;

  /// The Mason brick instance.
  final Brick brick;

  /// The full path to the brick within the repository.
  final String fullPath;

  @override
  String toString() => '$repositoryName/$fullPath';
}

/// Information about a configured repository.
class RepositoryInfo {
  const RepositoryInfo({
    required this.name,
    required this.url,
    required this.path,
  });

  /// The repository name/alias.
  final String name;

  /// The repository URL.
  final String url;

  /// The path within the repository where bricks are located.
  final String path;
}
