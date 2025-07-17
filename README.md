# 🧩 Flutter Paste eXpress - a fast way to clone compatible templated bricks into your flutter project

**fpx** is a lightweit developer-first CLI tool that helps you **install, scaffold, and customize Flutter components from any source** — instantly. Pull mason bricks from anywhere.
It works like `npx` for Flutter: you run a single command and get ready-to-edit code in your project.

> ✨ **fpx = Flutter Paste eXpress**  
> Drop-in Flutter components. Local, editable, and fast.

---

# 🚀 Developer Experience (User View)

As a **Flutter developer**, you can use `fpx` to scaffold buttons, cards, modals, layouts — from **open-source UI kits**, **internal design systems**, or **community bricks**.

### 🔧 Getting Started

```bash
dart pub global activate fpx
```

Then in your Flutter project:
```bash
fpx add button --name=LoginButton
```

Or use a specific component from GitHub:
```bash
fpx add card --source=github.com/my-org/ui-bricks
```


## ✅ What Happens?
- Downloads the template (from local, Git, or registry)
- Runs prompts or accepts flags (--name, --variant)
- Copies fully editable code into your project (e.g. lib/components/)
- Optionally hooks into your theme, design tokens, or folder structure

## 💡 Examples
```bash
fpx add modal --variant=fullscreen
fpx add form --fields=email,password --name=LoginForm
fpx list
fpx search card
```

# 🧱 Usage for Component Creators - Provide your components

You can publish your own components that developers can install using fpx.
Compatible with Mason templates under the hood.

## 🔧 Project Structure for fpx Compatibility

Create a Git repo like:
```
my-ui-kit/
├── bricks/
│   └── button/
│       ├── brick.yaml
│       └── __brick__/          # Mason template files
│           ├── button.dart
│           └── README.md
├── meta/
│   └── component_index.yaml    # fpx registry metadata (optional)
├── LICENSE
└── README.md
```

## 📝 brick.yaml Example
```yaml
name: button
description: A customizable button component
vars:
  name:
    type: string
    description: The name of the button widget
  variant:
    type: string
    description: Button style (primary, secondary, ghost)
```

## 🧩 Optional: component_index.yaml
Used by fpx list, fpx search, or hosted registries:

```yaml
components:
  - name: button
    description: A basic button with variant support
    tags: [button, ui, widget]
    source: ./bricks/button
  - name: card
    source: github.com/my-org/ui-bricks/card
```

## 🌐 Component Sources Supported
- ✅ Local paths
- ✅ Git repositories (public or private)
- 🧪 (Planned) Hosted registries
- 🧪 (Planned) Component preview sandbox (web)

## 🧰 CLI Reference

```bash
fpx add <component> [--name=...] [--variant=...]
fpx list                         # List available components
fpx search <term>                # Search compatible components
fpx config                       # View or edit config
fpx update                       # Pull latest bricks from source
```

## ✍️ Authoring & Publishing
Build Mason templates for each component

Follow the brick.yaml and folder conventions

Host them on GitHub or internal Git

(Optional) Submit to the fpx registry

## 📦 Coming soon: fpx publish to share your components with the community

🛠 Example Repos
example-ui-kit

internal-team/bricks

unping/unping-ui

❤️ Why fpx?
🧠 Local-first: no hidden magic, fully editable code

🧱 Component-driven: scaffold exactly what you need

⚙️ Mason-powered: works with existing Dart tools

🚀 Fast and flexible: from Git or from a growing ecosystem

📮 Feedback, Issues, Contributions
We’d love your help evolving the Flutter component ecosystem.

File issues or feature requests

Publish your own components

Contribute improvements to fpx