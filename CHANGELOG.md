# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-07-24

### Added
- Initial release of fpx CLI tool - Flutter Paste [x || button || table || badge || datepicker]
- `fpx init` command to initialize mason.yaml configuration
- `fpx list` command to list available bricks in mason.yaml
- `fpx add` command to add Flutter components using Mason bricks
- `fpx update` command to update bricks from repositories
- **Repository Management System**:
  - `fpx repository add` command to add remote brick repositories
  - `fpx repository list` command to view configured repositories
  - `fpx repository remove` command to remove repositories
- Support for local and remote Mason brick sources
- **GitHub Integration**:
  - Automatic parsing of GitHub repository structures
  - Auto-detection of tree/branch paths
  - Smart extraction of Git URLs and brick paths
  - Default to `bricks/` folder when no specific path detected
- **Configuration Management**:
  - `fpx_repositories.yaml` for repository configurations
  - Auto-creation and management of configuration files
- **Installation Options**:
  - pub.dev global activation via `dart pub global activate fpx`
  - Source installation support
- Comprehensive test coverage (34 passing tests)
- Cross-platform support (Ubuntu, macOS, Windows)
- CI/CD integration with GitHub Actions
- MIT License
- Detailed documentation and test coverage summary

### Features
- 🧱 **Mason Brick Management**: Paste Mason bricks locally
- 📦 **Repository Support**: Add and manage remote brick repositories
- 🔄 **Auto-detection**: Automatically parses GitHub repository structures
- ⚡ **Fast Setup**: Quick initialization and brick listing
- 🎯 **Widget Focused**: Single-Command Widget pasting
- Auto-initialization of mason.yaml when missing
- Flexible component scaffolding with customizable paths
- Support for component variants and custom naming
- Error handling for missing bricks and invalid configurations
- Integration with Mason CLI ecosystem
- Lightweight Widget paste CLI with support for remote brick repositories

## [0.1.1] - 2025-07-25

### Added
- CI/CD publishing for pub.dev package
\n## [0.1.2] - 2025-07-25


\n## [0.1.3] - 2025-07-25


\n## [0.1.4] - 2025-07-25


\n## [0.1.5] - 2025-07-26


\n## [0.1.6] - 2025-07-27


\n## [0.1.7] - 2025-07-27

