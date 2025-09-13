import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../models/models.dart';

/// Service for manipulating cloned repositories after they are cloned.
/// 
/// This service adds custom logic to process repositories immediately
/// after they are cloned, such as adding __brick__ directories or
/// other custom modifications.
class RepositoryPostCloneService {
  /// Constructor
  const RepositoryPostCloneService({
    required Logger logger,
  }) : _logger = logger;

  final Logger _logger;

  /// Process a cloned repository by applying custom manipulations.
  /// 
  /// This method is called after a repository is successfully cloned
  /// and applies various transformations to the cloned repository.
  /// 
  /// [repositoryName] - The name of the repository
  /// [repositoryPath] - The local path where the repository was cloned
  /// [repositoryUrl] - The original URL of the repository
  /// [fpxConfig] - The fpx configuration object. If null, uses default config.
  Future<void> processClonedRepository({
    required String repositoryName,
    required String repositoryPath,
    required String repositoryUrl,
    FpxConfig? fpxConfig,
  }) async {
    _logger.info('🔧 Processing cloned repository "$repositoryName"...');

    // Use provided config or default config
    final config = fpxConfig ?? FpxConfig.defaultConfig();

    try {
      // Add __brick__ to the repository
      await _addBricksToRepository(repositoryPath, config);
      
      // Future: Add other custom manipulations here
      // await _addCustomConfigurations(repositoryPath, config);
      // await _setupCustomStructure(repositoryPath, config);
      
      _logger.success('✅ Repository processing completed successfully');
    } catch (e) {
      _logger.warn('⚠️  Failed to process repository: $e');
      // Don't throw - repository is still usable even if processing fails
    }
  }

  /// Add __brick__ to the cloned repository.
  /// 
  /// This method creates a __brick__ directory structure beside each widget
  /// with brick.yaml metadata files and copies the widget files.
  /// 
  /// [repositoryPath] - The path to the cloned repository
  /// [config] - The fpx configuration object
  Future<void> _addBricksToRepository(String repositoryPath, FpxConfig config) async {
    try {
      // Find all available widgets in the configured bricks path
      final availableWidgets = await _findAvailableWidgets(repositoryPath, config);
      
      _logger.info('🔍 Found ${availableWidgets.length} widget(s):');
      
      for (final widget in availableWidgets) {
        _logger.info('  • ${widget.name} (${widget.files.length} file(s))');
        
        // Create __brick__ directory beside the widget
        final widgetBricksDir = Directory(path.join(widget.path, '__brick__'));
        await widgetBricksDir.create(recursive: true);
        
        // Create brick.yaml file
        await _createBrickYaml(repositoryPath, widget.path, widget.name);
        
        // Copy widget files into __brick__ folder
        await _copyWidgetFiles(widget, widgetBricksDir.path);
        
        // Preprocess widget files to replace foundation constants with actual values
        await _preprocessWidgetFiles(repositoryPath, widgetBricksDir.path, config);
        
        _logger.detail('    Created __brick__ for ${widget.name}');
      }
      
      _logger.success('✅ Created __brick__ structures for all widgets');
    } catch (e) {
      _logger.warn('Failed to process widgets: $e');
      rethrow;
    }
  }

  /// Find all available widgets in the configured bricks path.
  /// 
  /// This method scans the bricks directory to identify widget folders
  /// and their associated files.
  /// 
  /// [repositoryPath] - The path to the cloned repository
  /// [config] - The fpx configuration object
  /// 
  /// Returns a list of [WidgetInfo] objects representing found widgets.
  Future<List<WidgetInfo>> _findAvailableWidgets(String repositoryPath, FpxConfig config) async {
    final bricksPath = path.join(repositoryPath, config.bricks.path);
    final bricksDir = Directory(bricksPath);
    
    if (!await bricksDir.exists()) {
      _logger.warn('Bricks directory not found: ${bricksDir.path}');
      return [];
    }
    
    final widgets = <WidgetInfo>[];
    
    try {
      // List all directories in the bricks path
      final entities = await bricksDir.list(followLinks: false).toList();
      
      for (final entity in entities) {
        if (entity is Directory) {
          final widgetName = path.basename(entity.path);
          final widgetFiles = await _getWidgetFiles(entity.path);
          
          if (widgetFiles.isNotEmpty) {
            widgets.add(WidgetInfo(
              name: widgetName,
              path: entity.path,
              files: widgetFiles,
            ));
          }
        }
      }
      
      // Sort widgets by name for consistent output
      widgets.sort((a, b) => a.name.compareTo(b.name));
      
    } catch (e) {
      _logger.warn('Error scanning widgets directory: $e');
    }
    
    return widgets;
  }

  /// Get all Dart files in a widget directory.
  /// 
  /// [widgetPath] - The path to the widget directory
  /// 
  /// Returns a list of relative file paths within the widget directory.
  Future<List<String>> _getWidgetFiles(String widgetPath) async {
    final widgetDir = Directory(widgetPath);
    final files = <String>[];
    
    try {
      final entities = await widgetDir.list(recursive: true, followLinks: false).toList();
      
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Get relative path from widget directory
          final relativePath = path.relative(entity.path, from: widgetPath);
          files.add(relativePath);
        }
      }
      
      // Sort files for consistent output
      files.sort();
    } catch (e) {
      _logger.warn('Error reading widget files in $widgetPath: $e');
    }
    
    return files;
  }

  /// Create a brick.yaml file for a widget.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [widgetPath] - The path to the widget directory
  /// [widgetName] - The name of the widget
  Future<void> _createBrickYaml(String repositoryPath, String widgetPath, String widgetName) async {
    final brickYamlFile = File(path.join(widgetPath, 'brick.yaml'));
    
    // Read version from repository's pubspec.yaml
    final version = await _getRepositoryVersion(repositoryPath);
    
    final brickYamlContent = '''name: $widgetName
description: A $widgetName widget component
version: $version

vars:
  name:
    type: string
    description: The name for this component
    default: $widgetName
    prompt: What is the name of this component?
''';

    await brickYamlFile.writeAsString(brickYamlContent);
    _logger.detail('Created brick.yaml for $widgetName');
  }

  /// Get the version from the repository's pubspec.yaml file.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// 
  /// Returns the version string from pubspec.yaml, or a default version if not found.
  Future<String> _getRepositoryVersion(String repositoryPath) async {
    final pubspecFile = File(path.join(repositoryPath, 'pubspec.yaml'));
    
    if (!await pubspecFile.exists()) {
      _logger.warn('pubspec.yaml not found, using default version');
      return '0.1.0+1';
    }
    
    try {
      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('version:')) {
          final version = trimmedLine.substring(8).trim();
          _logger.detail('Found repository version: $version');
          return version;
        }
      }
      
      _logger.warn('Version not found in pubspec.yaml, using default');
      return '0.1.0+1';
    } catch (e) {
      _logger.warn('Error reading pubspec.yaml: $e, using default version');
      return '0.1.0+1';
    }
  }

  /// Copy widget files into the __brick__ directory.
  /// 
  /// [widget] - The widget information object
  /// [bricksPath] - The path to the __brick__ directory
  Future<void> _copyWidgetFiles(WidgetInfo widget, String bricksPath) async {
    for (final file in widget.files) {
      final sourceFile = File(path.join(widget.path, file));
      final targetFile = File(path.join(bricksPath, file));
      
      // Ensure target directory exists
      await targetFile.parent.create(recursive: true);
      
      // Copy the file
      await sourceFile.copy(targetFile.path);
      _logger.detail('    Copied $file to __brick__');
    }
  }

  /// Preprocess widget files to replace foundation constants with actual values.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [bricksPath] - The path to the __brick__ directory containing copied files
  /// [config] - The fpx configuration object
  Future<void> _preprocessWidgetFiles(String repositoryPath, String bricksPath, FpxConfig config) async {
    _logger.detail('🔧 Preprocessing widget files...');
    
    // Parse foundation files to extract constants
    final foundationConstants = await _parseFoundationFiles(repositoryPath, config);
    
    if (foundationConstants.isEmpty) {
      _logger.warn('No foundation constants found to replace');
      return;
    }
    
    _logger.detail('Found ${foundationConstants.length} foundation constants');
    
    // Get foundation file paths for import removal
    final foundationPaths = config.variables.foundation.paths;
    
    // Track third-party dependencies across all files
    final thirdPartyDependencies = <String>{};
    
    // Process all Dart files in the __brick__ directory
    final bricksDir = Directory(bricksPath);
    final dartFiles = await bricksDir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .cast<File>()
        .toList();
    
    for (final file in dartFiles) {
      await _replaceFoundationConstants(file, foundationConstants, foundationPaths, thirdPartyDependencies);
    }
    
    // Create README.md if there are third-party dependencies
    if (thirdPartyDependencies.isNotEmpty) {
      await _createDependenciesReadme(bricksPath, thirdPartyDependencies);
    }
    
    _logger.detail('✅ Preprocessing completed');
  }

  /// Parse foundation files to extract constant definitions.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [config] - The fpx configuration object
  /// 
  /// Returns a map of constant names to their values.
  Future<Map<String, String>> _parseFoundationFiles(String repositoryPath, FpxConfig config) async {
    final constants = <String, String>{};
    
    try {
      // Parse all foundation files dynamically
      for (final entry in config.variables.foundation.entries) {
        final foundationKey = entry.key;
        final foundationItem = entry.value;
        final foundationFile = File(path.join(repositoryPath, foundationItem.path));
        
        if (await foundationFile.exists()) {
          final className = await _extractClassName(foundationFile);
          if (className != null) {
            final foundationConstants = await _parseConstantsFromFile(foundationFile, className);
            constants.addAll(foundationConstants);
            _logger.detail('Processed $foundationKey: ${foundationConstants.length} constants from $className');
          }
        } else {
          _logger.warn('Foundation file not found: ${foundationItem.path}');
        }
      }
    } catch (e) {
      _logger.warn('Error parsing foundation files: $e');
    }
    
    return constants;
  }

  /// Extract the main class name from a foundation file.
  /// 
  /// [file] - The foundation file to analyze
  /// 
  /// Returns the class name if found, null otherwise.
  Future<String?> _extractClassName(File file) async {
    try {
      final content = await file.readAsString();
      
      // Look for class declarations - handle various patterns
      final classPatterns = [
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{'),           // class ClassName {
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends'),      // class ClassName extends
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+implements'),   // class ClassName implements
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+with'),         // class ClassName with
      ];
      
      for (final pattern in classPatterns) {
        final match = pattern.firstMatch(content);
        if (match != null) {
          final className = match.group(1)!;
          _logger.detail('Found class: $className in ${path.basename(file.path)}');
          return className;
        }
      }
      
      _logger.warn('No class found in ${path.basename(file.path)}');
      return null;
    } catch (e) {
      _logger.warn('Error extracting class name from ${file.path}: $e');
      return null;
    }
  }

  /// Parse constants from a single foundation file.
  /// 
  /// [file] - The foundation file to parse
  /// [className] - The name of the class containing constants
  /// 
  /// Returns a map of constant names to their values with const prefix when needed.
  Future<Map<String, String>> _parseConstantsFromFile(File file, String className) async {
    final constants = <String, String>{};
    
    try {
      final content = await file.readAsString();
      
      // More comprehensive regex to match all static const and static final declarations
      // Matches: static const/final [Type] [name] = [value];
      // Handles multi-word types, numbers, underscores in names, and multiline values
      // Now captures the declaration type (const or final)
      final constRegex = RegExp(
        r'static\s+(const|final)\s+(\w+(?:\<[\w\s,<>]+\>)?)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*([^;]+);',
        multiLine: true,
        dotAll: true,
      );
      
      final matches = constRegex.allMatches(content);
      
      for (final match in matches) {
        final declarationType = match.group(1)!.trim(); // 'const' or 'final'
        final constantType = match.group(2)!.trim(); // Type like TextStyle, Color, etc.
        final constantName = match.group(3)!.trim();
        final constantValue = match.group(4)!.trim();
        
        // Clean up the value - remove extra whitespace and newlines
        final cleanValue = constantValue.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Check if this is a complex object that should be handled specially
        final replacementValue = _processConstantValue(
          declarationType, 
          constantType, 
          constantName, 
          cleanValue,
        );
        
        if (replacementValue != null) {
          // Store with full class prefix for replacement
          constants['$className.$constantName'] = replacementValue;
          _logger.detail('Found $declarationType: $className.$constantName = $replacementValue');
        } else {
          _logger.warn('Skipped complex constant: $className.$constantName (requires manual handling)');
        }
      }
      
      _logger.detail('Parsed ${constants.length} constants from $className');
    } catch (e) {
      _logger.warn('Error parsing constants from ${file.path}: $e');
    }
    
    return constants;
  }

  /// Process a constant value to determine the best replacement strategy.
  /// 
  /// [declarationType] - Whether the constant was declared as 'const' or 'final'
  /// [constantType] - The type of the constant (e.g., 'TextStyle', 'Color', etc.)
  /// [constantName] - The name of the constant
  /// [constantValue] - The raw value string from the source code
  /// 
  /// Returns the processed replacement value, or null if the constant should be skipped.
  String? _processConstantValue(
    String declarationType, 
    String constantType, 
    String constantName, 
    String constantValue,
  ) {
    // Handle simple primitive types and direct constructors
    if (_isSimpleConstant(constantType, constantValue)) {
      // For primitive values, never add const keyword
      if (_isPrimitiveValue(constantValue)) {
        return constantValue;
      }
      
      // For constructor calls and complex objects, preserve const if original was const
      if (_needsConstKeyword(constantValue)) {
        return declarationType == 'const' ? 'const $constantValue' : constantValue;
      }
      
      // For simple references (like FontWeight.w400), don't add const
      return constantValue;
    }

    // Handle TextStyle specifically - convert complex TextStyle to simpler equivalent
    if (constantType == 'TextStyle' && _isComplexTextStyle(constantValue)) {
      final simpleTextStyle = _convertToSimpleTextStyle(constantValue);
      if (simpleTextStyle != null) {
        return declarationType == 'const' ? 'const $simpleTextStyle' : simpleTextStyle;
      }
    }

    // Handle Color types - try to extract simple color values
    if (constantType == 'Color' && _isComplexColor(constantValue)) {
      final simpleColor = _convertToSimpleColor(constantValue);
      if (simpleColor != null) {
        return declarationType == 'const' ? 'const $simpleColor' : simpleColor;
      }
    }

    // For other complex objects, skip replacement and let user handle manually
    _logger.warn('Skipping complex $constantType constant: $constantName');
    return null;
  }

  /// Check if a value is a primitive type that doesn't need const keyword.
  bool _isPrimitiveValue(String constantValue) {
    final trimmedValue = constantValue.trim();
    
    final primitivePatterns = [
      RegExp(r'^\d+$'), // Plain integers: 42
      RegExp(r'^\d+\.\d+$'), // Plain decimals: 4.0, 8.5
      RegExp(r'^true|false$'), // Booleans: true, false
      RegExp(r'^"[^"]*"$'), // String literals: "hello"
      RegExp(r"^'[^']*'$"), // String literals: 'hello'
      RegExp(r'^null$'), // null value
    ];
    
    return primitivePatterns.any((pattern) => pattern.hasMatch(trimmedValue));
  }

  /// Check if a value needs the const keyword (constructor calls, etc.).
  bool _needsConstKeyword(String constantValue) {
    final trimmedValue = constantValue.trim();
    
    final constRequiredPatterns = [
      RegExp(r'^\w+\('), // Constructor calls: Color(0xFF123456), EdgeInsets.all(8)
      RegExp(r'^\w+\.\w+\('), // Named constructor calls: EdgeInsets.symmetric(...)
    ];
    
    return constRequiredPatterns.any((pattern) => pattern.hasMatch(trimmedValue));
  }

  /// Check if a constant value is simple enough to be replaced directly.
  bool _isSimpleConstant(String constantType, String constantValue) {
    // Handle primitive types and simple constructors
    final simplePatterns = [
      RegExp(r'^\d+$'), // Plain numbers
      RegExp(r'^\d+\.\d+$'), // Decimal numbers
      RegExp(r'^true|false$'), // Booleans
      RegExp(r'^"[^"]*"$'), // String literals
      RegExp(r"^'[^']*'$"), // String literals with single quotes
      RegExp(r'^FontWeight\.w\d+$'), // FontWeight constants
      RegExp(r'^EdgeInsets\.(all|symmetric|only)\([^)]+\)$'), // Simple EdgeInsets
      RegExp(r'^BorderRadius\.(all|circular)\([^)]+\)$'), // Simple BorderRadius
      RegExp(r'^Duration\([^)]+\)$'), // Duration constructors
      RegExp(r'^Color\(0x[A-Fa-f0-9]{8}\)$'), // Simple Color constructors
    ];

    return simplePatterns.any((pattern) => pattern.hasMatch(constantValue.trim()));
  }

  /// Check if a TextStyle uses complex external functions.
  bool _isComplexTextStyle(String constantValue) {
    return constantValue.contains('GoogleFonts.') || 
           constantValue.contains('_outfitTextStyle') ||
           constantValue.contains('_') || // Any private method call
           constantValue.contains('Theme.of(') ||
           constantValue.contains('context.');
  }

  /// Convert a complex TextStyle to a simpler equivalent.
  String? _convertToSimpleTextStyle(String constantValue) {
    try {
      // Extract basic properties from GoogleFonts or custom TextStyle calls
      final Map<String, String> properties = {};
      
      // Look for fontSize: pattern
      final fontSizeMatch = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (fontSizeMatch != null) {
        properties['fontSize'] = fontSizeMatch.group(1)!;
      }
      
      // Look for fontWeight: pattern
      final fontWeightMatch = RegExp(r'fontWeight:\s*(FontWeight\.\w+|\w+)').firstMatch(constantValue);
      if (fontWeightMatch != null) {
        var weight = fontWeightMatch.group(1)!;
        // Convert simple references to FontWeight constants
        if (!weight.startsWith('FontWeight.')) {
          // Map common weight names to FontWeight constants
          switch (weight) {
            case 'regular': weight = 'FontWeight.w400'; break;
            case 'medium': weight = 'FontWeight.w500'; break;
            case 'semiBold': weight = 'FontWeight.w600'; break;
            case 'bold': weight = 'FontWeight.w700'; break;
            default: weight = 'FontWeight.w400'; break;
          }
        }
        properties['fontWeight'] = weight;
      }
      
      // Look for height: pattern (line height ratio)
      final heightMatch = RegExp(r'height:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (heightMatch != null) {
        properties['height'] = heightMatch.group(1)!;
      }
      
      // Look for letterSpacing: pattern
      final letterSpacingMatch = RegExp(r'letterSpacing:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (letterSpacingMatch != null) {
        properties['letterSpacing'] = letterSpacingMatch.group(1)!;
      }
      
      // Look for decoration: pattern
      final decorationMatch = RegExp(r'decoration:\s*(TextDecoration\.\w+)').firstMatch(constantValue);
      if (decorationMatch != null) {
        properties['decoration'] = decorationMatch.group(1)!;
      }
      
      // Build a simple TextStyle constructor
      if (properties.isNotEmpty) {
        final propertyStrings = properties.entries.map((e) => '${e.key}: ${e.value}').toList();
        return 'TextStyle(${propertyStrings.join(', ')})';
      }
    } catch (e) {
      _logger.warn('Failed to convert TextStyle: $e');
    }
    
    return null;
  }

  /// Check if a Color uses complex external functions.
  bool _isComplexColor(String constantValue) {
    return constantValue.contains('Color.fromRGBO') ||
           constantValue.contains('Color.fromARGB') ||
           constantValue.contains('HSLColor.') ||
           constantValue.contains('HSVColor.') ||
           constantValue.contains('Theme.of(') ||
           constantValue.contains('context.');
  }

  /// Convert a complex Color to a simpler equivalent.
  String? _convertToSimpleColor(String constantValue) {
    try {
      // Handle Color.fromRGBO(r, g, b, opacity)
      final rgboMatch = RegExp(r'Color\.fromRGBO\((\d+),\s*(\d+),\s*(\d+),\s*([0-9.]+)\)').firstMatch(constantValue);
      if (rgboMatch != null) {
        final r = int.parse(rgboMatch.group(1)!);
        final g = int.parse(rgboMatch.group(2)!);
        final b = int.parse(rgboMatch.group(3)!);
        final opacity = double.parse(rgboMatch.group(4)!);
        
        // Convert to hex if opacity is 1.0, otherwise keep RGBA
        if (opacity == 1.0) {
          final hex = ((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0').toUpperCase();
          return 'Color(0xFF$hex)';
        } else {
          final alpha = (opacity * 255).round();
          final hex = ((alpha << 24) | (r << 16) | (g << 8) | b).toRadixString(16).padLeft(8, '0').toUpperCase();
          return 'Color(0x$hex)';
        }
      }
      
      // Handle Color.fromARGB(a, r, g, b)
      final argbMatch = RegExp(r'Color\.fromARGB\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)').firstMatch(constantValue);
      if (argbMatch != null) {
        final a = int.parse(argbMatch.group(1)!);
        final r = int.parse(argbMatch.group(2)!);
        final g = int.parse(argbMatch.group(3)!);
        final b = int.parse(argbMatch.group(4)!);
        
        final hex = ((a << 24) | (r << 16) | (g << 8) | b).toRadixString(16).padLeft(8, '0').toUpperCase();
        return 'Color(0x$hex)';
      }
    } catch (e) {
      _logger.warn('Failed to convert Color: $e');
    }
    
    return null;
  }

  /// Replace foundation constants in a widget file with their actual values.
  /// 
  /// [file] - The widget file to process
  /// [constants] - Map of constant names to their values
  /// [foundationPaths] - List of foundation file paths for import removal
  /// [thirdPartyDependencies] - Set to collect third-party dependencies found
  Future<void> _replaceFoundationConstants(
    File file, 
    Map<String, String> constants, 
    List<String> foundationPaths,
    Set<String> thirdPartyDependencies,
  ) async {
    try {
      String content = await file.readAsString();
      bool wasModified = false;
      
      // Sort constants by length (longest first) to avoid partial replacements
      final sortedConstants = constants.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      
      // Replace each constant with its value using word boundaries
      for (final entry in sortedConstants) {
        final constantName = entry.key;
        final constantValue = entry.value;
        
        // Use word boundary regex to ensure we're replacing complete identifiers
        final escapedConstantName = RegExp.escape(constantName);
        final constantRegex = RegExp(r'\b' + escapedConstantName + r'\b');
        
        if (constantRegex.hasMatch(content)) {
          content = content.replaceAll(constantRegex, constantValue);
          wasModified = true;
          _logger.detail('    Replaced $constantName with $constantValue');
        }
      }
      
      // Remove foundation imports and collect third-party dependencies
      if (wasModified) {
        content = _removeFoundationImports(content, foundationPaths, thirdPartyDependencies);
        await file.writeAsString(content);
        _logger.detail('    Preprocessed ${path.basename(file.path)}');
      }
    } catch (e) {
      _logger.warn('Error processing ${file.path}: $e');
    }
  }

  /// Remove import statements that reference foundation files.
  /// 
  /// [content] - The file content to process
  /// [foundationPaths] - List of foundation file paths to match against
  /// [thirdPartyDependencies] - Set to collect third-party dependencies found
  /// 
  /// Returns the content with foundation imports removed.
  String _removeFoundationImports(String content, List<String> foundationPaths, Set<String> thirdPartyDependencies) {
    final lines = content.split('\n');
    final filteredLines = <String>[];
    
    // Extract just the filenames from foundation paths for matching
    final foundationFileNames = foundationPaths
        .map((p) => path.basename(p))
        .toSet();
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.startsWith('import ')) {
        bool shouldRemove = false;
        
        // PRESERVE Flutter, Dart, and other standard imports
        if (_isStandardImport(trimmedLine)) {
          _logger.detail('    Preserved standard import: $trimmedLine');
          filteredLines.add(line);
          continue;
        }
        
        // Check if import contains any specific foundation file names
        for (final fileName in foundationFileNames) {
          if (trimmedLine.contains(fileName)) {
            shouldRemove = true;
            break;
          }
        }
        
        // Check for foundation directory patterns
        if (!shouldRemove && (
            trimmedLine.contains('/foundation/') || 
            trimmedLine.contains('/src/foundation/'))) {
          shouldRemove = true;
        }
        
        // Check if it's a main package import (like the entire design system)
        if (!shouldRemove && _isMainPackageImport(trimmedLine, foundationPaths)) {
          shouldRemove = true;
        }
        
        if (shouldRemove) {
          _logger.detail('    Removed import: $trimmedLine');
          continue;
        }
        
        // If we reach here, it's a third-party import that should be kept
        // but we need to track it for the README
        if (trimmedLine.contains('package:') && !_isStandardImport(trimmedLine)) {
          final packageMatch = RegExp(r'package:([^/\s]+)').firstMatch(trimmedLine);
          if (packageMatch != null) {
            final packageName = packageMatch.group(1)!;
            thirdPartyDependencies.add(packageName);
            _logger.detail('    Tracked third-party dependency: $packageName');
          }
        }
      }
      
      filteredLines.add(line);
    }
    
    return filteredLines.join('\n');
  }

  /// Check if an import is a standard Flutter/Dart import that should be preserved.
  bool _isStandardImport(String importLine) {
    return importLine.contains('dart:') ||
           importLine.contains('package:flutter/') ||
           importLine.contains('package:material/') ||
           importLine.contains('package:cupertino/') ||
           importLine.contains('package:widgets/') ||
           importLine.contains('package:meta/');
  }

  /// Create a README.md file in the __brick__ directory with dependency information.
  /// 
  /// [bricksPath] - The path to the __brick__ directory
  /// [dependencies] - Set of third-party package names that need to be installed
  Future<void> _createDependenciesReadme(String bricksPath, Set<String> dependencies) async {
    final readmeFile = File(path.join(bricksPath, 'README.md'));
    
    final sortedDependencies = dependencies.toList()..sort();
    final dependencyList = sortedDependencies.map((dep) => '- $dep').join('\n');
    
    final readmeContent = '''# Dependencies

This widget requires the following packages to be installed before use:

$dependencyList

## Installation

Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
${sortedDependencies.map((dep) => '  $dep: ^latest_version').join('\n')}
```

Then run:

```bash
flutter pub get
```

## Note

Please check the latest versions of these packages on [pub.dev](https://pub.dev) and update the version numbers accordingly.
''';

    await readmeFile.writeAsString(readmeContent);
    _logger.info('📄 Created README.md with ${dependencies.length} dependencies');
  }

  /// Check if an import is the main package import (entire design system).
  bool _isMainPackageImport(String importLine, List<String> foundationPaths) {
    // If the import is a package import and any foundation path starts with
    // the same base path, it's likely the main package
    if (!importLine.contains('package:')) return false;
    
    // Extract the package name
    final packageMatch = RegExp(r'package:([^/\s]+)').firstMatch(importLine);
    if (packageMatch != null) {
      final packageName = packageMatch.group(1)!;
      
      // Heuristic: if the import is something like package:my_ui/my_ui.dart
      // or just contains the package name as the main barrel file
      if (importLine.contains('$packageName/$packageName.dart') ||
          importLine.contains('$packageName.dart')) {
        _logger.detail('    Identified main package import: $packageName');
        return true;
      }
      
      // Additional check: if foundation paths suggest this is the current project
      // and the import references the same package structure
      for (final foundationPath in foundationPaths) {
        if (foundationPath.contains('lib/') && 
            importLine.contains('package:$packageName/')) {
          // This is likely importing from the same project
          _logger.detail('    Identified project import: $packageName');
          return true;
        }
      }
    }
    
    return false;
  }
}

/// Information about a discovered widget.
/// 
/// Contains metadata about a widget found in the bricks directory,
/// including its name, location, and associated files.
class WidgetInfo {
  /// Constructor
  const WidgetInfo({
    required this.name,
    required this.path,
    required this.files,
  });

  /// The name of the widget (directory name)
  final String name;

  /// The full path to the widget directory
  final String path;

  /// List of Dart files in the widget directory (relative paths)
  final List<String> files;

  @override
  String toString() {
    return 'WidgetInfo(name: $name, path: $path, files: $files)';
  }
}
