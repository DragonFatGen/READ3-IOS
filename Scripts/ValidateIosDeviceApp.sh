#!/usr/bin/env bash
# Validates a built iOS device .app bundle before it is packaged into an IPA.
#
# Checks performed:
#   1. The Mach-O binary contains arm64 and no simulator-only architecture.
#   2. Every LC_BUILD_VERSION platform is a real-device iOS platform
#      (numeric 2 or the text "IOS"). Simulator platforms (7 / IOSSIMULATOR),
#      other platforms, and unrecognizable output are rejected. When
#      LC_BUILD_VERSION is present it is authoritative: there is no fallback
#      to legacy LC_VERSION_MIN_* commands that could mask a mismatch.
#   3. Every non-system dynamic library dependency of the main binary and of
#      the actually-embedded frameworks resolves through LC_RPATH /
#      @executable_path / @loader_path to a file inside the app bundle.
#      A missing Frameworks directory is only an error when a required
#      non-system dependency cannot be resolved without it.
#
# Tool commands can be overridden through the OTOOL / LIPO environment
# variables so the checks can be exercised offline with synthetic output
# (see Scripts/Tests/ValidateIosDeviceApp.Tests.ps1).
#
# Usage: ValidateIosDeviceApp.sh <path-to-app-bundle>

set -euo pipefail

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "FAIL: app bundle not found: ${APP_PATH:-<missing argument>}" >&2
  exit 1
fi

OTOOL="${OTOOL:-otool}"
LIPO="${LIPO:-lipo}"
BINARY="$APP_PATH/LegadoIOS"
[ -f "$BINARY" ] || { echo "FAIL: Mach-O binary missing: $BINARY" >&2; exit 1; }

echo "== Architectures =="
ARCHS="$("$LIPO" -info "$BINARY")"
echo "$ARCHS"
echo "$ARCHS" | grep -q 'arm64' || { echo "FAIL: arm64 slice missing" >&2; exit 1; }
if echo "$ARCHS" | grep -q 'x86_64'; then
  echo "FAIL: simulator architecture (x86_64) present in a device build" >&2
  exit 1
fi

echo "== Mach-O platform =="
OTOOL_LISTING="$("$OTOOL" -l "$BINARY")"
[ -n "$OTOOL_LISTING" ] || { echo "FAIL: $OTOOL -l produced no output; cannot determine the Mach-O platform" >&2; exit 1; }

# Extract the platform value of every LC_BUILD_VERSION command. Each value is
# matched as a whole field, so "IOS" never matches "IOSSIMULATOR".
PLATFORM_VALUES="$(printf '%s\n' "$OTOOL_LISTING" | awk '
  $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
  in_build_version && $1 == "platform"    { print $2; in_build_version = 0 }
  in_build_version && ($1 == "minos" || $1 == "sdk") { in_build_version = 0 }
')"

if [ -n "$PLATFORM_VALUES" ]; then
  # LC_BUILD_VERSION is authoritative when present: no legacy fallback below.
  PLATFORM_BAD=0
  while IFS= read -r PLATFORM; do
    case "$PLATFORM" in
      2|IOS)
        echo "  accepted platform: $PLATFORM" ;;
      7)
        echo "FAIL: Mach-O platform 7 targets the iOS Simulator, not a real device" >&2
        PLATFORM_BAD=1 ;;
      IOSSIMULATOR)
        echo "FAIL: Mach-O platform IOSSIMULATOR targets the iOS Simulator, not a real device" >&2
        PLATFORM_BAD=1 ;;
      *)
        echo "FAIL: unexpected Mach-O platform: $PLATFORM" >&2
        PLATFORM_BAD=1 ;;
    esac
  done <<< "$PLATFORM_VALUES"
  [ "$PLATFORM_BAD" -eq 0 ] || exit 1
else
  echo "No LC_BUILD_VERSION command found; falling back to LC_VERSION_MIN_IPHONEOS."
  printf '%s\n' "$OTOOL_LISTING" | grep -q 'LC_VERSION_MIN_IPHONEOS' \
    || { echo "FAIL: no iOS min-version load command found" >&2; exit 1; }
fi

is_inside_app() {
  case "$1" in
    "$APP_PATH"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolves a non-system install name to a file inside the app bundle.
# Prints the resolved path and returns 0 on success, returns 1 otherwise.
# RPATHS_RAW must hold the target's LC_RPATH entries, one per line.
resolve_dependency() {
  local dep="$1" loader_dir="$2"
  local rp p suffix resolved
  case "$dep" in
    @rpath/*)
      suffix="${dep#@rpath/}"
      [ -n "$RPATHS_RAW" ] || return 1
      while IFS= read -r rp; do
        [ -n "$rp" ] || continue
        p="${rp//@executable_path/$APP_PATH}"
        p="${p//@loader_path/$loader_dir}"
        resolved="$p/$suffix"
        if [ -f "$resolved" ] && is_inside_app "$resolved"; then
          printf '%s\n' "$resolved"
          return 0
        fi
      done <<< "$RPATHS_RAW"
      return 1 ;;
    @executable_path/*)
      resolved="$APP_PATH/${dep#@executable_path/}" ;;
    @loader_path/*)
      resolved="$loader_dir/${dep#@loader_path/}" ;;
    *)
      return 1 ;;
  esac
  [ -f "$resolved" ] && is_inside_app "$resolved" || return 1
  printf '%s\n' "$resolved"
}

# Validates every dynamic dependency of one Mach-O target.
check_dependencies() {
  local target="$1" listing="$2"
  local loader_dir dep resolved
  local missing=0
  loader_dir="$(dirname "$target")"
  RPATHS_RAW="$(printf '%s\n' "$listing" | awk '$1 == "path" { print $2 }')"

  local deps
  deps="$("$OTOOL" -L "$target" | awk 'NR > 1 { print $1 }')"
  [ -n "$deps" ] || { echo "FAIL: $OTOOL -L returned no dependencies for $target; cannot validate linking" >&2; return 1; }

  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    case "$dep" in
      /System/Library/*|/usr/lib/*)
        echo "  [system ] $target -> $dep" ;;
      @rpath/*|@executable_path/*|@loader_path/*)
        if resolved="$(resolve_dependency "$dep" "$loader_dir")"; then
          echo "  [bundle ] $target -> $dep -> $resolved"
        else
          echo "FAIL: required dependency is not embedded in the app bundle: $dep" >&2
          echo "      target: $target; loader dir: $loader_dir; rpaths: ${RPATHS_RAW:-none}" >&2
          missing=1
        fi ;;
      *)
        echo "FAIL: non-system dependency uses an absolute or unrecognized path form and cannot be embedded: $dep (target: $target)" >&2
        missing=1 ;;
    esac
  done <<< "$deps"
  return "$missing"
}

echo "== Linked library dependencies =="
check_dependencies "$BINARY" "$OTOOL_LISTING"

# Embedded frameworks and dylibs must also satisfy their own dependencies.
FRAMEWORKS_DIR="$APP_PATH/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
  for entry in "$FRAMEWORKS_DIR"/*.dylib "$FRAMEWORKS_DIR"/*.framework; do
    [ -e "$entry" ] || continue
    case "$entry" in
      *.framework)
        framework_binary="$entry/$(basename "${entry%.framework}")"
        [ -f "$framework_binary" ] || continue ;;
      *)
        framework_binary="$entry" ;;
    esac
    framework_listing="$("$OTOOL" -l "$framework_binary")"
    check_dependencies "$framework_binary" "$framework_listing"
  done
fi
echo "All required non-system dependencies resolve within the app bundle."

echo "== Bundle contents =="
ls -la "$APP_PATH"
if [ -d "$FRAMEWORKS_DIR" ]; then
  ls -la "$FRAMEWORKS_DIR"
fi
