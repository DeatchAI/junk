#!/bin/bash
set -euo pipefail

helper_dir="$SRCROOT/PowerHelper"
output_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
build_dir="$DERIVED_FILE_DIR/keep-awake-helper"
mkdir -p "$build_dir" "$output_dir/MacOS" "$output_dir/Library/LaunchDaemons"

executables=()
for architecture in $ARCHS; do
  executable="$build_dir/helper-$architecture"
  xcrun swiftc -sdk "$SDKROOT" -target "$architecture-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
    -module-cache-path "$build_dir/modules" -parse-as-library \
    "$SRCROOT/lazzy/Core/KeepAwake/KeepAwakeProtocol.swift" \
    "$helper_dir/"*.swift -framework IOKit \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$helper_dir/Info.plist" \
    -o "$executable"
  executables+=("$executable")
done

destination="$output_dir/MacOS/DetachKeepAwakeHelper"
if [[ ${#executables[@]} -eq 1 ]]; then
  cp "${executables[0]}" "$destination"
else
  xcrun lipo -create "${executables[@]}" -output "$destination"
fi
chmod 755 "$destination"
cp "$helper_dir/app.getlazzy.keep-awake.plist" "$output_dir/Library/LaunchDaemons/"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --identifier app.getlazzy.keep-awake-helper \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$destination"
fi
