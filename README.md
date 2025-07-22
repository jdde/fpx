## fpx - Flutter Paste [x || button || table || badge || datepicker]

![coverage][coverage_badge]
[![License: MIT][license_badge]][license_link]
[![Powered by Mason](https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge)](https://github.com/felangel/mason)



CLI template by the [Very Good CLI][very_good_cli_link] 🤖

Lightweight Widget paste CLI with support for remote brick repositories.

### Features

- 🧱 **Mason Brick Management**: Paste Mason bricks locally
- 📦 **Repository Support**: Add and manage remote brick repositories  
- 🔄 **Auto-detection**: Automatically parses GitHub repository structures
- ⚡ **Fast Setup**: Quick initialization and brick listing
- 🎯 **Widget Focused**: Single-Command Widget pasting

---

## Getting Started 🚀

Install FPX globally via pub.dev:

```sh
dart pub global activate fpx
```

Or install from source:

```sh
git clone https://github.com/jdde/fpx.git
cd fpx
dart pub global activate --source=path .
```

## Quick Start ⚡

Get started in 2 simple steps:

```sh
# 1. Add the unping-ui repository (contains pre-built Flutter widgets)
$ fpx repository add --url https://github.com/unping/unping-ui --name unping-ui

# 2. Add a button widget to your project (mason.yaml will be created automatically)
$ fpx add button --name my_awesome_button
```

That's it! FPX automatically creates the necessary configuration files and you now have a button widget ready to use in your Flutter project.

## Usage

```sh
# Add a component (requires mason.yaml configuration)
$ fpx add button --name my_button

# Initialize mason.yaml file
$ fpx init

# List available bricks
$ fpx list

# Update bricks from repositories
$ fpx update

# Repository Management
$ fpx repository add --url <git_url> [--name <alias>]
$ fpx repository list
$ fpx repository remove --name <alias>

# Show CLI version
$ fpx --version

# Show usage help
$ fpx --help
```

## Repository Management 📦

FPX supports managing remote brick repositories to access a wider variety of Mason bricks beyond your local configuration.

### Adding Repositories

Add a repository using its Git URL:

```sh
# Add with auto-generated name
$ fpx repository add --url https://github.com/unping/unping-ui

# Add with custom name
$ fpx repository add --url https://github.com/unping/unping-ui --name unping-ui
```

The CLI automatically detects GitHub repository structures and extracts the appropriate path to bricks. For GitHub URLs, it will:
- Parse tree/branch paths (e.g., `https://github.com/owner/repo/tree/main/bricks`)
- Extract the correct Git URL and bricks path
- Default to `bricks/` folder if no specific path is detected

### Listing Repositories

View all configured repositories:

```sh
$ fpx repository list
```

This shows each repository's name, Git URL, and the path to bricks within the repository.

### Removing Repositories

Remove a repository by its name/alias:

```sh
$ fpx repository remove --name mason-bricks
```

### Configuration

Repository configurations are stored in `fpx_repositories.yaml` in your current directory. This file is automatically created and managed by the CLI. Example structure:

```yaml
# fpx repository configuration
# This file manages remote repositories for unping-UI
repositories:
  unping-ui:
    url: https://github.com/unping/unping-ui.git
    path: bricks
  my-widgets:
    url: https://github.com/username/flutter-widgets.git
    path: mason_bricks
```

## Contributing 🤝

We welcome contributions! For development setup, testing, and contribution guidelines, see [README_local_development.md](README_local_development.md).

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

[coverage_badge]: coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_cli_link]: https://github.com/VeryGoodOpenSource/very_good_cli