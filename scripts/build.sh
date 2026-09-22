#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
configuration="${CONFIGURATION:-debug}"
app_name="RandomActionLauncher"
output_root="${project_root}/build"
app_bundle="${output_root}/${app_name}.app"
swiftpm_root="${project_root}/.build"

cd "${project_root}"

mkdir -p \
    "${swiftpm_root}/cache" \
    "${swiftpm_root}/config" \
    "${swiftpm_root}/module-cache" \
    "${swiftpm_root}/security"

export CLANG_MODULE_CACHE_PATH="${swiftpm_root}/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${swiftpm_root}/module-cache"

# 保留 swift 默认 SDK 选择。实测固定旧版 SDK（如 MacOSX15.4）会与
# 新编译器的 Observation 宏展开不兼容；如需覆盖请通过环境变量显式传入。

swift_build_arguments=(
    --disable-sandbox
    --configuration "${configuration}"
    --scratch-path "${swiftpm_root}"
    --cache-path "${swiftpm_root}/cache"
    --config-path "${swiftpm_root}/config"
    --security-path "${swiftpm_root}/security"
)

swift build "${swift_build_arguments[@]}"
binary_directory="$(swift build "${swift_build_arguments[@]}" --show-bin-path)"

rm -rf "${app_bundle}"
install -d "${app_bundle}/Contents/MacOS"
install -d "${app_bundle}/Contents/Resources"
install -m 755 "${binary_directory}/${app_name}" "${app_bundle}/Contents/MacOS/${app_name}"
install -m 644 "${project_root}/Configuration/Info.plist" "${app_bundle}/Contents/Info.plist"

codesign \
    --force \
    --sign - \
    --entitlements "${project_root}/Configuration/${app_name}.entitlements" \
    "${app_bundle}"

echo "Built ${app_bundle}"
