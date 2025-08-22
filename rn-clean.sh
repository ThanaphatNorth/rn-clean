#!/bin/bash

LOG_FILE="/tmp/rn-clean.log"
FAILED_COMMANDS=0

# Function to check if last command failed due to permission denied
check_permission_denied() {
    if tail -n 20 "$LOG_FILE" | grep -q "Permission denied\|Operation not permitted"; then
        return 0
    fi
    return 1
}

# Function to run command with error handling and permission recovery
run_command() {
    local description="$1"
    shift
    echo "🔧 $description"

    if "$@" >> "$LOG_FILE" 2>&1; then
        echo "✅ $description - SUCCESS"
    else
        if check_permission_denied; then
            echo "🔐 Permission denied detected, fixing ownership with sudo chown..."
            if sudo chown -R $(whoami) . >> "$LOG_FILE" 2>&1; then
                echo "✅ Ownership fixed, retrying $description..."
                if "$@" >> "$LOG_FILE" 2>&1; then
                    echo "✅ $description - SUCCESS (after ownership fix)"
                else
                    echo "❌ $description - FAILED even after ownership fix (continuing...)"
                    echo "Error output:"
                    tail -n 10 "$LOG_FILE"
                    echo "---"
                    FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
                fi
            else
                echo "❌ Failed to fix ownership, $description - FAILED (continuing...)"
                echo "Error output:"
                tail -n 10 "$LOG_FILE"
                echo "---"
                FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
            fi
        else
            echo "❌ $description - FAILED (continuing...)"
            echo "Error output:"
            tail -n 10 "$LOG_FILE"
            echo "---"
            FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
        fi
    fi
}

# Initialize log file
echo "React Native Clean Script Log - $(date)" > "$LOG_FILE"
echo "🧹 Starting React Native project cleanup..."

# Run react-native-clean-project with automated responses
echo "🧽 Running npx react-native-clean-project..."
if command -v npx >/dev/null 2>&1; then
    echo -e "y\ny\ny\ny\nn\ny\ny\ny\nn" | npx react-native-clean-project >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ npx react-native-clean-project - SUCCESS"
    else
        echo "❌ npx react-native-clean-project - FAILED (continuing...)"
        echo "Error output:"
        tail -n 10 "$LOG_FILE"
        echo "---"
        FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
    fi
else
    echo "⚠️  npx not found, skipping react-native-clean-project..."
fi

# Remove node_modules
run_command "Removing node_modules" rm -rf node_modules
run_command "Removing package-lock.json" rm -rf package-lock.json

# Remove iOS Pods and builds
run_command "Cleaning iOS Pods" rm -rf ios/Pods
run_command "Removing Podfile.lock" rm -rf ios/Podfile.lock

# Remove Android builds and gradle (moved before gradlew clean)
run_command "Cleaning iOS build" rm -rf ios/build
run_command "Cleaning Android .gradle" rm -rf android/.gradle
run_command "Cleaning Android build" rm -rf android/build
run_command "Cleaning Android app build" rm -rf android/app/build
run_command "Cleaning Gradle caches" rm -rf ~/.gradle/caches/
run_command "Cleaning Gradle daemon" rm -rf ~/.gradle/daemon/
run_command "Cleaning Gradle native" rm -rf ~/.gradle/native/
run_command "Cleaning Gradle kotlin" rm -rf ~/.gradle/kotlin/
run_command "Cleaning local .gradle" rm -rf .gradle
run_command "Cleaning Android .cxx" rm -rf android/.cxx
run_command "Cleaning Android app .cxx" rm -rf android/app/.cxx

# Stop gradle daemon before clean
echo "⏹️  Stopping Gradle daemon..."
if [ -d "android" ]; then
    cd android
    if ./gradlew --stop >> "$LOG_FILE" 2>&1; then
        echo "✅ Stopping Gradle daemon - SUCCESS"
    else
        echo "❌ Stopping Gradle daemon - FAILED (continuing...)"
        echo "Error output:"
        tail -n 10 "$LOG_FILE"
        echo "---"
        FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
    fi
    cd ..
else
    echo "⚠️  Android directory not found, skipping Gradle daemon stop..."
fi

# Clean Xcode derived data
run_command "Cleaning Xcode DerivedData" rm -rf ~/Library/Developer/Xcode/DerivedData

# Clear watchman watches
echo "👀 Clearing Watchman watches..."
if command -v watchman >/dev/null 2>&1; then
    if watchman watch-del-all >> "$LOG_FILE" 2>&1; then
        echo "✅ Clearing Watchman watches - SUCCESS"
    else
        echo "❌ Clearing Watchman watches - FAILED (continuing...)"
        echo "Error output:"
        tail -n 10 "$LOG_FILE"
        echo "---"
        FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
    fi
else
    echo "⚠️  Watchman not found, skipping..."
fi


# Clean npm cache
run_command "Cleaning npm cache" npm cache clean --force

# Install npm dependencies
echo "⬇️  Installing npm dependencies..."
if npm install --legacy-peer-deps >> "$LOG_FILE" 2>&1; then
    echo "✅ Installing npm dependencies - SUCCESS"
else
    echo "❌ Installing npm dependencies - FAILED (continuing...)"
    echo "Error output:"
    tail -n 10 "$LOG_FILE"
    echo "---"
    FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
fi

# Install iOS pods
echo "🍎 Installing iOS Pods..."
if [ -d "ios" ]; then
    cd ios
    echo "🔧 Trying pod install (without repo update)..."
    if pod install >> "$LOG_FILE" 2>&1; then
        echo "✅ Installing iOS Pods - SUCCESS"
    else
        echo "❌ Pod install failed, trying with --repo-update..."
        if pod install --repo-update >> "$LOG_FILE" 2>&1; then
            echo "✅ Installing iOS Pods with repo update - SUCCESS"
        else
            echo "❌ Installing iOS Pods - FAILED (continuing...)"
            echo "Error output:"
            tail -n 10 "$LOG_FILE"
            echo "---"
            FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
        fi
    fi
    cd ..
else
    echo "⚠️  iOS directory not found, skipping Pod install..."
fi

# Clean Android with Gradle
echo "🧼 Cleaning Android with Gradle..."
if [ -d "android" ]; then
    cd android
    if ./gradlew clean --no-daemon >> "$LOG_FILE" 2>&1; then
        echo "✅ Cleaning Android with Gradle - SUCCESS"
    else
        echo "❌ Cleaning Android with Gradle - FAILED (continuing...)"
        echo "Error output:"
        tail -n 10 "$LOG_FILE"
        echo "---"
        FAILED_COMMANDS=$((FAILED_COMMANDS + 1))
    fi
    cd ..
else
    echo "⚠️  Android directory not found, skipping Gradle clean..."
fi

echo ""
echo "🎉 React Native project cleanup completed!"

if [ $FAILED_COMMANDS -eq 0 ]; then
    echo "🌟 All commands executed successfully! Your project is now clean and ready."
else
    echo "⚠️  Cleanup completed with $FAILED_COMMANDS failed command(s). Check the log for details."
fi

echo "📋 Full log available at: $LOG_FILE"%