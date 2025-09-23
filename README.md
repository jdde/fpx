## fpx - Flutter Paste [x || button || table || badge || datepicker]

![coverage][coverage_badge]
[![License: MIT][license_badge]][license_link]
[![Powered by Mason](https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge)](https://github.com/felangel/mason)



CLI template by the [Very Good CLI][very_good_cli_link] 🤖


**fpx** (Flutter Paste X) is a copy & paste component system inspired by shadcn/ui for Flutter. Unlike traditional packages, fpx copies individual components directly into your project, giving you full control to customize and modify them without being locked into a specific design system or dependency chain.

Copy & paste Flutter components from any compatible repository into your project. No package dependencies, full customization, automatic dependency resolution.

### Key Benefits

- 🎯 **Copy, don't install** - Components become part of your codebase
- �️ **Full customization** - Modify components to match your exact needs  
- 🔧 **Dependency-free** - No external package dependencies to manage
- � **Automatic resolution** - fpx handles component dependencies and foundation files automatically
- ⚡ **Fast Setup** - Quick initialization and component listing
- � **Widget Focused** - Optimized for Flutter component workflows

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
# 1. Add the unping-ui repository (contains pre-built Flutter components)
$ fpx repository add --url https://github.com/unping/unping-ui --name unping-ui

# 2. Add a component to your project 
$ fpx add base_button
```

That's it! fpx automatically copies the component and its dependencies directly into your project, ready to use and customize.

## Usage

```sh
# Add a component
$ fpx add base_button

# Add a component with variant
$ fpx add base_button --variant outlined

# List available components
$ fpx list

# Update components from repositories
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

fpx supports managing remote component repositories to access a wide variety of Flutter components beyond your local setup.

### Adding Repositories

Add a repository using its Git URL:

```sh
# Add with auto-generated name
$ fpx repository add --url https://github.com/unping/unping-ui

# Add with custom name
$ fpx repository add --url https://github.com/unping/unping-ui --name unping-ui
```

The CLI automatically detects GitHub repository structures and extracts the appropriate path to components. For GitHub URLs, it will:
- Parse tree/branch paths (e.g., `https://github.com/owner/repo/tree/main/lib/src/components`)
- Extract the correct Git URL and components path
- Default to `lib/src/components/` folder if no specific path is detected

### Listing Repositories

View all configured repositories:

```sh
$ fpx repository list
```

This shows each repository's name, Git URL, and the path to components within the repository.

### Removing Repositories

Remove a repository by its name/alias:

```sh
$ fpx repository remove --name unping-ui
```

### Configuration

Repository configurations are stored in `.fpx_repositories.yaml` in your current directory. This file is automatically created and managed by the CLI. Example structure:

```yaml
# fpx repository configuration
# This file manages remote repositories for Flutter components
repositories:
  unping-ui:
    url: https://github.com/unping/unping-ui.git
    path: lib/src/components
  my-widgets:
    url: https://github.com/username/flutter-widgets.git
    path: lib/src/components
```

## Creating Component Libraries 📚

Want to make your component library fpx-compatible? Here's how to set it up:

### 1. Create fpx.yaml Configuration

Add an `fpx.yaml` file to your repository root:

```yaml
components:
  path: lib/src/components
variables:
  foundation:
    color:
      path: lib/src/foundation/ui_colors.dart
    spacing:
      path: lib/src/foundation/ui_spacing.dart
    text_styles:
      path: lib/src/foundation/ui_text_styles.dart
    radius:
      path: lib/src/foundation/ui_radius.dart
```

This configuration tells fpx:
- Where to find your components (`components.path`)
- Where foundation files are located (`variables.foundation`)
- How to resolve dependencies between components

### 2. Example Folder structure for given yaml structure

This is an example structure! Just the paths in the fpx.yaml need to be correct.

```
lib/
  src/
    components/
      my_button/
        my_button.dart      # Main component file
      my_badge/
        my_badge.dart
    foundation/
      ui_colors.dart        # Color definitions
      ui_spacing.dart       # Spacing constants
      ui_text_styles.dart   # Typography styles
      ui_radius.dart        # Border radius values
```

### 3. Make Your Library Available

Users can then add your repository to fpx:

```sh
fpx repository add --url https://github.com/your-org/your-ui-lib --name your-ui-lib
fpx add my_button
```

The components will be copied directly into their project, ready to use and customize!

## Contributing 🤝

We welcome contributions! For development setup, testing, and contribution guidelines, see [README_local_development.md](README_local_development.md).

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

[coverage_badge]: coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT