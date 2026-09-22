#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
swiftpm_root="${project_root}/.build"
developer_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
developer_libraries="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

cd "${project_root}"

arguments=(
    --disable-sandbox
    --scratch-path "${swiftpm_root}"
    --cache-path "${swiftpm_root}/cache"
    --config-path "${swiftpm_root}/config"
    --security-path "${swiftpm_root}/security"
)

if [[ -d "${developer_frameworks}/Testing.framework" ]]; then
    arguments+=(
        -Xswiftc -F
        -Xswiftc "${developer_frameworks}"
        -Xlinker "-F${developer_frameworks}"
        -Xlinker -rpath
        -Xlinker "${developer_frameworks}"
        -Xlinker -rpath
        -Xlinker "${developer_libraries}"
    )
fi

swift test "${arguments[@]}"
