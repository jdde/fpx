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

  /// Load repository configuration from file.
  Future<Map<String, dynamic>> loadRepositoryConfig() async {
    final defaultConfig = await _loadDefaultRepositoryConfig();
    final userConfig = await _loadUserRepositoryConfig();

    // Merge configurations (user overrides default)
    final merged = <String, dynamic>{};
    if (defaultConfig['repositories'] is Map) {
      final reposMap = defaultConfig['repositories'] as Map;
      merged['repositories'] = _convertYamlMapToMap(reposMap);
    } else {
      merged['repositories'] = <String, dynamic>{};
    }

    if (userConfig['repositories'] is Map) {
      final userRepos = userConfig['repositories'] as Map<String, dynamic>;
      final mergedRepos = merged['repositories'] as Map<String, dynamic>;
      mergedRepos.addAll(userRepos);
    }

    return merged;
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
        }
      }
    } else {
      // Search all repositories for the brick name
      for (final entry in repositories.entries) {
        final repoName = entry.key;
        final repoConfig = _convertYamlMapToMap(entry.value as Map);

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
      _logger.detail('Error creating brick from repository: $e');
      return null;
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
    final config = await loadRepositoryConfig();

    // Add default repository if none exist
    if (config['repositories'] == null ||
        (config['repositories'] as Map).isEmpty) {
      // Default repositories will be loaded from .fpx_repositories.yaml
      // No need to create them programmatically
    }
  }

  /// Load default repository configuration.
  Future<Map<String, dynamic>> _loadDefaultRepositoryConfig() async {
    final defaultConfigFile = File(configFileName);
    if (!await defaultConfigFile.exists()) {
      return <String, dynamic>{};
    }

    try {
      final content = await defaultConfigFile.readAsString();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map) {
        return _convertYamlMapToMap(yamlMap);
      }
      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }

  /// Load user-specific repository configuration.
  Future<Map<String, dynamic>> _loadUserRepositoryConfig() async {
    final userConfigFile = File(_userConfigFileName);
    if (!await userConfigFile.exists()) {
      return <String, dynamic>{};
    }

    try {
      final content = await userConfigFile.readAsString();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map) {
        return _convertYamlMapToMap(yamlMap);
      }
      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }

  /// Save repository configuration to file.
  Future<void> saveRepositoryConfig(Map<String, dynamic> config) async {
    final configFile = File(configFileName);

    const header = '''# fpx repository configuration
# This file manages remote repositories for Mason bricks
# 
# Format:
# repositories:
#   <name>:
#     url: <git_url>
#     path: <path_to_bricks_in_repo>

''';

    final yamlContent = _mapToYaml(config);
    await configFile.writeAsString(header + yamlContent);
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
    
    // Clone the repository
    final result = await Process.run(
      'git',
      ['clone', url, repoDir.path],
      workingDirectory: Directory.current.path,
    );
    
    if (result.exitCode != 0) {
      throw Exception('Failed to clone repository: ${result.stderr}');
    }
    
    // Apply post-clone processing
    await _postCloneService.processClonedRepository(
      repositoryName: name,
      repositoryPath: repoDir.path,
      repositoryUrl: url,
    );
    
    return repoDir;
  }

  /// Update an existing cloned repository.
  Future<void> updateRepository(String name) async {
    final repoDir = Directory(path.join(_repositoriesDir, name));
    
    if (!await repoDir.exists()) {
      throw Exception('Repository "$name" not found locally');
    }
    
    // Pull latest changes
    final result = await Process.run(
      'git',
      ['pull'],
      workingDirectory: repoDir.path,
    );
    
    if (result.exitCode != 0) {
      throw Exception('Failed to update repository: ${result.stderr}');
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
      // Handle YAML parsing errors
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
      components.addAll(bricksConfig.keys.cast<String>());
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

  String _mapToYaml(Map<String, dynamic> map, [int indent = 0]) {
    final buffer = StringBuffer();
    final spaces = '  ' * indent;

    for (final entry in map.entries) {
      if (entry.value is Map) {
        buffer.writeln('${spaces}${entry.key}:');
        buffer
            .write(_mapToYaml(entry.value as Map<String, dynamic>, indent + 1));
      } else {
        buffer.writeln('${spaces}${entry.key}: ${entry.value}');
      }
    }

    return buffer.toString();
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
