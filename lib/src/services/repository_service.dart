import 'dart:io';

import 'package:mason/mason.dart';
import 'package:yaml/yaml.dart';

/// Service for managing and searching brick repositories.
class RepositoryService {
  static const String configFileName = '.fpx_repositories.yaml';
  static const String _userConfigFileName = '.fpx_repositories.local.yaml';

  /// Load repository configuration from file.
  Future<Map<String, dynamic>> loadRepositoryConfig() async {
    final defaultConfig = await _loadDefaultRepositoryConfig();
    final userConfig = await _loadUserRepositoryConfig();
    
    // Merge configurations (user overrides default)
    final merged = <String, dynamic>{};
    if (defaultConfig['repositories'] is Map) {
      merged['repositories'] = Map<String, dynamic>.from(defaultConfig['repositories'] as Map);
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
          final repoConfig = repositories[repoName] as Map<String, dynamic>;
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
        final repoConfig = entry.value as Map<String, dynamic>;
        
        // Try to find brick in this repository
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
    
    return results;
  }

  /// Create a brick from repository configuration.
  Future<Brick?> _createBrickFromRepository(
    String repoName,
    Map<String, dynamic> repoConfig,
    String brickPath,
  ) async {
    final url = repoConfig['url'] as String;
    final basePath = repoConfig['path'] as String;
    
    try {
      // Construct the full path to the brick
      final fullBrickPath = '$basePath/$brickPath';
      final gitPath = GitPath(url, path: fullBrickPath);
      return Brick.git(gitPath);
    } catch (e) {
      // Brick might not exist in this repository
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
      final repoConfig = entry.value as Map<String, dynamic>;
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
        return Map<String, dynamic>.from(yamlMap);
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
        return Map<String, dynamic>.from(yamlMap);
      }
      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }

  /// Save repository configuration to file.
  Future<void> _saveRepositoryConfig(Map<String, dynamic> config) async {
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

  String _mapToYaml(Map<String, dynamic> map, [int indent = 0]) {
    final buffer = StringBuffer();
    final spaces = '  ' * indent;
    
    for (final entry in map.entries) {
      if (entry.value is Map) {
        buffer.writeln('${spaces}${entry.key}:');
        buffer.write(_mapToYaml(entry.value as Map<String, dynamic>, indent + 1));
      } else {
        buffer.writeln('${spaces}${entry.key}: ${entry.value}');
      }
    }
    
    return buffer.toString();
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
