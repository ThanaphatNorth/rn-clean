# 🧹 React Native Clean Script

A robust cleanup script for React Native projects.  
Removes caches, Pods, Gradle builds, and reinstall dependencies with one command.  

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
- Runs `pod install` (with retry `--repo-update` if needed)
- Optional `react-native-clean-project` integration
- Detailed log file in `/tmp/rn-clean.log`
- Colorful, developer-friendly output
- Safe retry on permission errors (`chown` fix)
- Cross-platform (macOS/Linux)

---

## 🚀 Quick Start

```bash
# Download
curl -O https://raw.githubusercontent.com/<your-username>/<your-repo>/main/rn-clean.sh

# Make executable
chmod +x rn-clean.sh

# Run
./rn-clean.sh
```

> Full logs available at `/tmp/rn-clean.log`

---

## ⚙️ Options

| Flag                  | Description |
|-----------------------|-------------|
| `--yes` / `-y`        | Skip confirmation prompt |
| `--dry-run`           | Show actions without executing |
| `--no-ios`            | Skip iOS cleanup |
| `--no-android`        | Skip Android cleanup |
| `--no-install`        | Skip reinstalling JS dependencies |
| `--no-pods`           | Skip CocoaPods install |
| `--no-clean-project`  | Skip `react-native-clean-project` step |
| `--pm <tool>`         | Force package manager (`npm`, `yarn`, `pnpm`, `bun`) |
| `--legacy-peer-deps`  | Use `npm install --legacy-peer-deps` |
| `--npm-ci`            | Use `npm ci` instead of `npm install` |

---

## 📋 Examples

```bash
# Default cleanup
./rn-clean.sh

# Clean without reinstalling deps
./rn-clean.sh --no-install

# Dry-run to preview actions
./rn-clean.sh --dry-run

# Force Yarn as package manager
./rn-clean.sh --pm yarn
```

---

## 🔒 Safety Notes
- Deletes common build/cache directories only—never source code.
- Always prompts before destructive actions (unless `--yes`).
- Logs everything to `/tmp/rn-clean.log`.

---

## 🤝 Contributing
PRs and issues welcome!  
Feel free to fork and adjust for your team’s workflow.

---

## 📄 License
MIT — use freely, at your own risk.
