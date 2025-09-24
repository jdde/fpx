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

  /// Directory name where repositories are cloned locally.
  static const String repositoriesDir = '.fpx_repositories';

  final Logger _logger;
  late final RepositoryPostCloneService _postCloneService = 
      RepositoryPostCloneService(logger: _logger);

  /// Get list of available repositories by reading .fpx_repositories directory
  Future<List<String>> _getAvailableRepositories() async {
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

  /// Load repository configuration from file.
  Future<Map<String, dynamic>> loadRepositoryConfig() async {
    // This method is kept for backward compatibility but now returns empty config
    // since we're using directory-based repository discovery
    return <String, dynamic>{'repositories': <String, dynamic>{}};
  }

  /// Find a brick by name, optionally with repository namespace.
  ///
  /// Supports formats:
  /// - `brick_name` - searches all repositories
  /// - `@repo/brick_name` - searches specific repository
  /// - `@repo/path/brick_name` - searches specific repository with path
  Future<List<BrickSearchResult>> findBrick(String brickIdentifier) async {
    final repositories = await _getAvailableRepositories();

    if (repositories.isEmpty) {
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

        if (repositories.contains(repoName)) {
        try {
          // Ensure repository is cloned before searching
          if (!await isRepositoryCloned(repoName)) {
            _logger.warn('Repository "$repoName" is not cloned locally'); // coverage:ignore-line
            return results;
          }
            final brick = await _createBrickFromRepository(
              repoName,
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
            _logger.detail('Failed to access repository $repoName: $e'); // coverage:ignore-line
            // Continue without adding results for this repository
          }
        }
      }
    } else {
      // Search all repositories for the brick name
      for (final repoName in repositories) {
        try {
          // Only search in cloned repositories
          if (!await isRepositoryCloned(repoName)) {
            continue;
          }
          
          // Check if component exists in auto-detected components
          final detectedComponents = await scanForBricks(repoName);

          if (detectedComponents.contains(brickIdentifier)) {
            final brick = await _createBrickFromRepository(
              repoName,
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
          _logger.detail('Failed to access repository $repoName: $e'); // coverage:ignore-line
          // Continue searching other repositories
        }
      }
    }

    return results;
  }

  /// Create a brick from repository directory structure.
  Future<Brick?> _createBrickFromRepository(
    String repoName,
    String brickPath,
  ) async {
    try {
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
        // Default to 'bricks' as the base path
        const basePath = 'bricks';
        final fullBrickPath = '$basePath/$brickPath';
        final localPath = path.join(repoPath, fullBrickPath);
        
        if (await Directory(localPath).exists() || await File(path.join(localPath, 'brick.yaml')).exists()) {
          _logger.detail('Found brick at standard path: $localPath');
          return Brick.path(localPath);
        }
        
        _logger.detail('No brick found for $brickPath in repository $repoName');
        return null;
      }
      
      _logger.err('Repository $repoName is not cloned locally'); // coverage:ignore-line
      return null;
    } catch (e) {
      _logger.detail('Error creating brick from repository: $e'); // coverage:ignore-line
      return null; // coverage:ignore-line
    }
  }

  /// Get all configured repositories.
  Future<Map<String, RepositoryInfo>> getRepositories() async {
    final repositories = await _getAvailableRepositories();
    final result = <String, RepositoryInfo>{};
    
    for (final repoName in repositories) {
      // Since we're only reading from directory structure, we provide basic info
      // The actual URL is not available unless stored elsewhere
      result[repoName] = RepositoryInfo(
        name: repoName,
        url: '', // URL not available from directory structure
        path: 'bricks', // Default path
      );
    }

    return result;
  }

  /// Initialize default repositories.
  Future<void> initializeDefaultRepositories() async {
    final repositories = await _getAvailableRepositories();

    // Check if any repositories exist
    if (repositories.isEmpty) {
      // No repositories available from directory structure
      // Note: Repositories are now managed by directory structure only
    }
  }


  /// Clone a repository locally for processing.
  Future<Directory> cloneRepository(String name, String url) async {
    final repoDir = Directory(path.join(repositoriesDir, name));
    
    // Remove existing directory if it exists
    if (await repoDir.exists()) {
      await repoDir.delete(recursive: true);
    }
    
    // Create repositories directory
    await Directory(repositoriesDir).create(recursive: true);
    
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
    await _postCloneService.processClonedRepository( // coverage:ignore-line
      repositoryName: name, // coverage:ignore-line
      repositoryPath: repoDir.path, // coverage:ignore-line
      repositoryUrl: url, // coverage:ignore-line
    ); // coverage:ignore-line
    
    return repoDir;
  }

  /// Update an existing cloned repository.
  Future<void> updateRepository(String name, {bool pullAgain = true}) async {
    final repoDir = Directory(path.join(repositoriesDir, name));
    
    if (!await repoDir.exists()) {
      throw Exception('Repository "$name" not found locally');
    }
    
    // Pull latest changes
    if (pullAgain) {
      final result = await Process.run( // coverage:ignore-line
        'git',
        ['pull'],
        workingDirectory: repoDir.path,
      );

      if (result.exitCode != 0) { // coverage:ignore-line
        throw Exception('Failed to update repository: ${result.stderr}'); // coverage:ignore-line
      }
    }

    _logger.info('Repository directory exists; will reprocess Cloned repository'); // coverage:ignore-line
    // re-execute post processing, which will have the same outcome but in compatibility action
    // it will process the manually moved component library to be usable.
    // since clone via url will fail in github action
    await _postCloneService.processClonedRepository( // coverage:ignore-line
      repositoryName: name, // coverage:ignore-line
      repositoryPath: repoDir.path, // coverage:ignore-line
      repositoryUrl: '', // URL not available during update
    ); // coverage:ignore-line
  }

  /// Get the local directory path for a cloned repository.
  String getRepositoryPath(String name) {
    return path.join(repositoriesDir, name);
  }

  /// Check if a repository is cloned locally.
  Future<bool> isRepositoryCloned(String name) async {
    final repoDir = Directory(path.join(repositoriesDir, name));
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


  /// Get all available components from all configured repositories.
  Future<Map<String, List<String>>> getAllAvailableComponents() async {
    final repositories = await _getAvailableRepositories();
    final allComponents = <String, List<String>>{};

    if (repositories.isEmpty) {
      return allComponents;
    }

    for (final repoName in repositories) {
      try {
        // Only scan cloned repositories
        if (await isRepositoryCloned(repoName)) {
          // Detect components in this repository
          final components = await scanForBricks(repoName);
          if (components.isNotEmpty) {
            allComponents[repoName] = components;
          }
        }
      } catch (e) {
        _logger.detail('Failed to detect components in repository $repoName: $e'); // coverage:ignore-line
        // Continue with other repositories
      }
    }

    return allComponents;
  }

  /// Scan repository directory for brick.yaml files.
  Future<List<String>> scanForBricks(String repositoryName) async {
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
