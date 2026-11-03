#!/usr/bin/env bash
# Compila RootDesk para iPhone en una Mac (Xcode + MacPorts ya instalados). Se corre desde la raiz del repositorio:
#   bash rootdesk-tools/compilar-ios-mac.sh                      # edicion Soporte, sin firmar
#   EDITION=staff TEAM_ID=ABCDE12345 bash rootdesk-tools/compilar-ios-mac.sh
# Variables: EDITION=staff|cliente (por defecto staff), TEAM_ID (equipo de Apple para firmar; opcional), BUILD_NUMBER, FORCE_BRIDGE=1.
# Es repetible: lo ya instalado/compilado se reutiliza. Versiones iguales a las del flujo de GitHub (Rust 1.75, Flutter 3.24.5).
set -euo pipefail

EDITION="${EDITION:-staff}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
RUST_VERSION="1.75.0"
VCPKG_COMMIT="9e593bb18ea69cc5095e012465dcd675a822ed0d"
HERR="$HOME/rootdesk-herramientas"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HERR"
cd "$REPO"

paso() { printf '\n== %s\n' "$*"; }

paso "1/7 herramientas del sistema (MacPorts; Homebrew ya no soporta Macs Intel)"
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:$PATH"
faltan=""
for c in nasm yasm pkg-config cmake autoconf automake glibtool pod; do command -v "$c" >/dev/null || faltan="$faltan $c"; done
if [ -n "$faltan" ]; then
  echo "Faltan:$faltan"
  echo "Instalalos con:  sudo port install nasm yasm pkgconfig cmake autoconf automake libtool cocoapods"
  exit 1
fi

paso "2/7 Rust $RUST_VERSION y puente Flutter-Rust"
if ! command -v rustup >/dev/null; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION" -c rustfmt
fi
export PATH="$HOME/.cargo/bin:$PATH"
rustup toolchain install "$RUST_VERSION" --profile minimal -c rustfmt
rustup default "$RUST_VERSION"
rustup target add aarch64-apple-ios
command -v flutter_rust_bridge_codegen >/dev/null || {
  cargo install cargo-expand --version 1.0.95 --locked
  cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
}

paso "3/7 Flutter 3.22.3 (puente) y 3.24.5 (compilacion)"
for v in 3.22.3 3.24.5; do
  if [ ! -x "$HERR/flutter-$v/bin/flutter" ]; then
    curl -fsSL -o "$HERR/f.zip" "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_${v}-stable.zip"
    rm -rf "$HERR/flutter"; unzip -q "$HERR/f.zip" -d "$HERR"; mv "$HERR/flutter" "$HERR/flutter-$v"; rm "$HERR/f.zip"
  fi
done
git config --global --add safe.directory "$HERR/flutter-3.24.5" || true
if (cd "$HERR/flutter-3.24.5" && git apply --check "$REPO/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff" 2>/dev/null); then
  (cd "$HERR/flutter-3.24.5" && git apply "$REPO/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff")
fi

paso "4/7 puente generado"
if [ ! -f flutter/lib/generated_bridge.dart ] || [ -n "${FORCE_BRIDGE:-}" ]; then
  cp flutter/pubspec.yaml /tmp/pubspec.yaml.orig; cp flutter/pubspec.lock /tmp/pubspec.lock.orig
  (
    export PATH="$HERR/flutter-3.22.3/bin:$PATH"
    sed -i '' -e 's/extended_text: 14.0.0/extended_text: 13.0.0/g' flutter/pubspec.yaml
    (cd flutter && flutter pub get)
    flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
      --c-output ./flutter/macos/Runner/bridge_generated.h
    cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h
  )
  cp /tmp/pubspec.yaml.orig flutter/pubspec.yaml; cp /tmp/pubspec.lock.orig flutter/pubspec.lock
fi

paso "5/7 dependencias nativas para iPhone (vcpkg arm64-ios; la primera vez tarda mucho)"
export VCPKG_ROOT="$HERR/vcpkg"
if [ ! -x "$VCPKG_ROOT/vcpkg" ]; then
  git clone https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
  (cd "$VCPKG_ROOT" && git checkout "$VCPKG_COMMIT" && ./bootstrap-vcpkg.sh -disableMetrics)
fi
"$VCPKG_ROOT/vcpkg" install --triplet arm64-ios --x-install-root="$VCPKG_ROOT/installed"

paso "6/7 libreria de Rust para iPhone"
cargo build --locked --features flutter,hwcodec --release --target aarch64-apple-ios --lib

paso "7/7 aplicacion iOS (edicion: $EDITION)"
PBX=flutter/ios/Runner.xcodeproj/project.pbxproj
if [ "$EDITION" = "staff" ]; then
  printf "const String kEdition = 'staff';\n\nbool get isStaffEdition => kEdition == 'staff';\n" > flutter/lib/edition.dart
  sed -i '' 's|<string>RootDesk</string>|<string>RootDesk Soporte</string>|g' flutter/ios/Runner/Info.plist
  sed -i '' 's|com.carriez.flutterHbb|mx.rootinc.rootdesk.soporte|g' "$PBX"
else
  sed -i '' 's|com.carriez.flutterHbb|mx.rootinc.rootdesk|g' "$PBX"
fi
# Las cuentas gratuitas de Apple no permiten notificaciones push ni datos de Wi-Fi: sin esas capacidades la firma funciona.
# Con la cuenta de pago de Apple Developer se corre con SIN_CAPACIDADES=0 para conservar las del proyecto original.
if [ "${SIN_CAPACIDADES:-1}" = "1" ]; then
  sed -i '' 's|Runner/Runner.entitlements|Runner/Runner-libre.entitlements|g' "$PBX"
fi
if [ -n "${TEAM_ID:-}" ]; then sed -i '' "s|DEVELOPMENT_TEAM = HZF9JMC8YN;|DEVELOPMENT_TEAM = $TEAM_ID;|g" "$PBX"; fi
export PATH="$HERR/flutter-3.24.5/bin:$PATH"
cd flutter
flutter pub get
(cd ios && pod install)
flutter build ios --release --no-codesign --build-name 1.5.0 --build-number "$BUILD_NUMBER"
echo
echo "LISTO: compilo bien (sin firmar)."
echo "Para instalar en tu iPhone: 1) abre ios/Runner.xcworkspace en Xcode, elige Runner > Signing & Capabilities > tu Personal Team;"
echo "2) con el iPhone conectado y en Modo de desarrollador, desde la carpeta flutter corre:"
echo "   $HERR/flutter-3.24.5/bin/flutter run --release"
