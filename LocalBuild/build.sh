#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
output_root="$repo_root/Artifacts/LocalBuild"
build_root="$output_root/Build"
module_root="$build_root/Modules"
header_root="$build_root/GeneratedHeaders"
object_root="$build_root/Objects"
engine_root="$build_root/Engine"
app="$output_root/McBopomofo.app"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
target="arm64-apple-macosx14.0"

if [[ ! -d "$sdk" ]]; then
    sdk="$(xcrun --show-sdk-path)"
fi

mkdir -p "$module_root" "$header_root" "$object_root" "$engine_root"

swift_common=(
    -sdk "$sdk"
    -target "$target"
    -swift-version 5
    -module-cache-path "$build_root/SwiftModuleCache"
    -I "$module_root"
)

function compile_swift_module() {
    local module_name="$1"
    shift
    local sources=("$@")
    echo "Building Swift module $module_name"
    xcrun swiftc "${swift_common[@]}" \
        -parse-as-library \
        -whole-module-optimization \
        -emit-object \
        -emit-module \
        -emit-module-path "$module_root/$module_name.swiftmodule" \
        -emit-objc-header \
        -emit-objc-header-path "$header_root/$module_name-Swift.h" \
        -module-name "$module_name" \
        -o "$object_root/$module_name.o" \
        "${sources[@]}"
}

compile_swift_module CandidateUI \
    "$repo_root"/Packages/CandidateUI/Sources/CandidateUI/*.swift
compile_swift_module TooltipUI \
    "$repo_root"/Packages/TooltipUI/Sources/TooltipUI/*.swift
compile_swift_module NotifierUI \
    "$repo_root"/Packages/NotifierUI/Sources/NotifierUI/*.swift
compile_swift_module InputSourceHelper \
    "$repo_root"/Packages/InputSourceHelper/Sources/InputSourceHelper/*.swift
compile_swift_module FSEventStreamHelper \
    "$repo_root"/Packages/FSEventStreamHelper/Sources/FSEventStreamHelper/*.swift
compile_swift_module NSStringUtils \
    "$repo_root"/Packages/NSStringUtils/Sources/NSStringUtils/*.swift
compile_swift_module ChineseNumbers \
    "$repo_root"/Packages/ChineseNumbers/Sources/ChineseNumbers/*.swift
compile_swift_module RomanNumbers \
    "$repo_root"/Packages/RomanNumbers/Sources/RomanNumbers/*.swift
compile_swift_module BopomofoBraille \
    "$repo_root"/Packages/BopomofoBraille/Sources/BopomofoBraille/*.swift \
    "$repo_root"/Packages/BopomofoBraille/Sources/BopomofoBraille/Tokens/*.swift
compile_swift_module InfoCollector \
    "$repo_root"/Packages/InfoCollector/Sources/InfoCollector/*.swift \
    "$repo_root"/Packages/InfoCollector/Sources/InfoCollector/Plugins/*.swift
compile_swift_module OpenCCBridge "$script_dir/OpenCCBridgeStub.swift"
compile_swift_module SystemCharacterInfo "$script_dir/SystemCharacterInfoStub.swift"

module_map="$header_root/module.modulemap"
: > "$module_map"
for module_name in CandidateUI NSStringUtils OpenCCBridge ChineseNumbers RomanNumbers BopomofoBraille; do
    print "module $module_name {" >> "$module_map"
    print "  header \"$header_root/$module_name-Swift.h\"" >> "$module_map"
    print "  export *" >> "$module_map"
    print "}" >> "$module_map"
done

echo "Building C++ engine"
cmake -S "$repo_root/Source" -B "$engine_root" \
    -DENABLE_TEST=OFF \
    -DENABLE_MIXED_INPUT_DEMO=OFF \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    "-DCMAKE_CXX_FLAGS=-isystem $sdk/usr/include/c++/v1"
cmake --build "$engine_root" --parallel

app_sources=(
    "$repo_root"/Source/*.swift
    "$repo_root"/Source/PreferencesUI/*.swift
    "$script_dir/LocalMain.swift"
)
app_sources=("${app_sources[@]:#"$repo_root/Source/main.swift"}")

echo "Building Swift application module"
xcrun swiftc "${swift_common[@]}" \
    -whole-module-optimization \
    -emit-object \
    -emit-module \
    -emit-module-path "$module_root/McBopomofo.swiftmodule" \
    -emit-objc-header \
    -emit-objc-header-path "$header_root/McBopomofo-Swift.h" \
    -import-objc-header "$repo_root/Source/McBopomofo-Bridging-Header.h" \
    -Xcc -I"$repo_root/Source" \
    -module-name McBopomofo \
    -o "$object_root/McBopomofo.o" \
    "${app_sources[@]}"

objc_common=(
    -std=c++20
    -fobjc-arc
    -fblocks
    -fmodules
    -fcxx-modules
    -fmodules-cache-path="$build_root/ClangModuleCache"
    -isysroot "$sdk"
    -isystem "$sdk/usr/include/c++/v1"
    -mmacosx-version-min=14.0
    -I "$repo_root/Source"
    -I "$repo_root/Source/Engine"
    -I "$repo_root/Source/Engine/Mandarin"
    -I "$repo_root/Source/Engine/gramambular2"
    -I "$header_root"
    -fmodule-map-file="$module_map"
)

echo "Building Objective-C++ bridge"
for source in KeyHandler.mm LanguageModelManager.mm ServiceProviderInputHelper.mm; do
    xcrun clang++ "${objc_common[@]}" -c "$repo_root/Source/$source" \
        -o "$object_root/${source:r}.o"
done

echo "Linking application"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swift_objects=("$object_root"/*.o)
xcrun swiftc "${swift_common[@]}" \
    -o "$app/Contents/MacOS/McBopomofo" \
    "${swift_objects[@]}" \
    "$engine_root/Engine/libMcBopomofoLMLib.a" \
    "$engine_root/Engine/Mandarin/libMandarinLib.a" \
    "$engine_root/Engine/gramambular2/libgramambular2_lib.a" \
    -framework AppKit \
    -framework Carbon \
    -framework CoreServices \
    -framework InputMethodKit \
    -framework IOKit \
    -framework Security \
    -Xlinker -lc++

cp "$repo_root/Source/McBopomofo-Info.plist" "$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string McBopomofo "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string org.openvanilla.inputmethod.McBopomofo "$app/Contents/Info.plist"
plutil -replace CFBundleName -string McBopomofo "$app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string McBopomofo "$app/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 14.0 "$app/Contents/Info.plist"
plutil -remove NSMainNibFile "$app/Contents/Info.plist"
plutil -replace InputMethodConnectionName -string McBopomofo_1_Connection "$app/Contents/Info.plist"
plutil -replace TISInputSourceID -string org.openvanilla.inputmethod.McBopomofo "$app/Contents/Info.plist"

resources="$app/Contents/Resources"
cp "$repo_root/Source/Data/data.txt" "$resources/"
cp "$repo_root/Source/Data/data-plain-bpmf.txt" "$resources/"
cp "$repo_root/Source/Data/associated-phrases-v2.txt" "$resources/"
cp "$repo_root/Source/Data/bpmfvs-pua.txt" "$resources/"
cp "$repo_root/Source/Data/bpmfvs-variants.txt" "$resources/"
cp "$repo_root/Source/dictionary_service.json" "$resources/"
cp "$repo_root/Source/add-phrase-hook.sh" "$resources/"
cp "$repo_root"/Source/Images/*.tiff "$resources/"

for locale in Base en zh-Hant; do
    source_locale="$repo_root/Source/$locale.lproj"
    target_locale="$resources/$locale.lproj"
    mkdir -p "$target_locale"
    for pattern in '*.strings' '*.stringsdict' '*.txt' '*.rtf'; do
        for resource in "$source_locale"/$~pattern(N); do
            cp "$resource" "$target_locale/"
        done
    done
done

print -n 'APPLBPMF' > "$app/Contents/PkgInfo"
codesign --force --deep --sign - "$app"

echo "Verifying local application"
codesign --verify --deep --strict --verbose=2 "$app"
"$app/Contents/MacOS/McBopomofo" --self-check
file "$app/Contents/MacOS/McBopomofo"
du -sh "$app"
echo "Built $app"
