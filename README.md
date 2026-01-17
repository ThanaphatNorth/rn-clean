# 🧹 React Native Clean Script

A robust cleanup script for React Native projects.  
Removes caches, Pods, Gradle builds, and reinstalls dependencies with one command.

Designed for safety, automation, and convenience for developers who often struggle with “weird build issues”.

---

## ✨ Features

- Cleans:
  - `node_modules`, lockfiles, npm/yarn/pnpm/bun caches
  - iOS: `Pods`, `Podfile.lock`, `DerivedData`, `ios/build`
  - Android: `.gradle`, `build/`, `.cxx`, global Gradle caches/daemons
- Stops Gradle daemons gracefully
- Clears **Watchman** watches
- Auto-detects package manager (`npm`, `yarn`, `pnpm`, `bun`)
- Reinstalls dependencies
- Links assets with `react-native-asset`
- Runs `pod install` (with retry `--repo-update` if needed)
- Runs `gradlew clean` after cleanup
- Optional `react-native-clean-project` integration
- Shows task list preview before execution
- Detailed log file in `/tmp/rn-clean.log`
- Colorful, developer-friendly output
- Safe retry on permission errors (`chown` fix)
- Cross-platform (macOS/Linux)

---

## 🚀 Quick Start

### Run once inside a project

```bash
# Download
curl -O https://raw.githubusercontent.com/ThanaphatNorth/rn-clean/main/rn-clean.sh

# Make executable
chmod +x rn-clean.sh

# Run
./rn-clean.sh
```

Logs are stored in `/tmp/rn-clean.log`.

---

## 🌍 Global Installation

Install once, then run `rn-clean` globally in any React Native project.

## Install globally (macOS/Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/ThanaphatNorth/rn-clean/main/install.sh | bash
```

This installs `rn-clean` to `/usr/local/bin` (or `~/.local/bin` if `/usr/local/bin` is not writable).

If `~/.local/bin` is used, ensure it’s on your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ThanaphatNorth/rn-clean/main/uninstall.sh | bash
```

---

## ⚙️ Options

| Flag                 | Description                                          |
| -------------------- | ---------------------------------------------------- |
| `--yes` / `-y`       | Skip confirmation prompt                             |
| `--dry-run`          | Show actions without executing                       |
| `--no-ios`           | Skip iOS cleanup                                     |
| `--no-android`       | Skip Android cleanup                                 |
| `--no-install`       | Skip reinstalling JS dependencies                    |
| `--no-pods`          | Skip CocoaPods install                               |
| `--no-clean-project` | Skip `react-native-clean-project` step               |
| `--pm <tool>`        | Force package manager (`npm`, `yarn`, `pnpm`, `bun`) |
| `--legacy-peer-deps` | Use `npm install --legacy-peer-deps`                 |
| `--npm-ci`           | Use `npm ci` instead of `npm install`                |
| `-h` / `--help`      | Show help message                                    |

---

## 📋 Examples

```bash
# Default cleanup
rn-clean

# Clean without reinstalling deps
rn-clean --no-install

# Dry-run to preview actions
rn-clean --dry-run

# Force Yarn as package manager
rn-clean --pm yarn
```

---

## 🔒 Safety Notes

- Deletes only common build/cache directories — never source code.
- Always prompts before destructive actions (unless `--yes`).
- Logs everything to `/tmp/rn-clean.log`.

---

## 🤝 Contributing

PRs and issues welcome!  
Feel free to fork and adjust for your team’s workflow.

---

## 📄 License

MIT — use freely, at your own risk.
