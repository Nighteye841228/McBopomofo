#!/usr/bin/env python3
"""Run production mixed-input Swift tests with Command Line Tools dependencies."""

import argparse
import os
from pathlib import Path
import subprocess


def run(arguments, environment=None):
    subprocess.run(list(map(str, arguments)), check=True, env=environment)


def write_test_source(source, destination):
    destination.write_text(source.read_text().replace('@testable import McBopomofo', ''))
    return destination


def compile_bridge(source, common, objects):
    output = objects / (source.stem + '.o')
    run(['xcrun', 'clang++', *common, '-c', source, '-o', output])
    return output


def compile_dependency(name, root, output, common):
    sources = sorted((root / 'Packages' / name / 'Sources' / name).rglob('*.swift'))
    stub = root / 'LocalBuild' / (name + 'Stub.swift')
    sources = [stub] if stub.exists() else sources
    run(['xcrun', 'swiftc', *common, '-parse-as-library', '-whole-module-optimization',
         '-emit-object', '-emit-module', '-emit-module-path', output / 'Modules' / (name + '.swiftmodule'),
         '-emit-objc-header', '-emit-objc-header-path', output / 'GeneratedHeaders' / (name + '-Swift.h'),
         '-module-name', name, '-o', output / 'Objects' / (name + '.o'), *sources])


def compile_dependencies(root, output, common):
    names = ['CandidateUI', 'TooltipUI', 'NotifierUI', 'InputSourceHelper', 'FSEventStreamHelper',
             'NSStringUtils', 'ChineseNumbers', 'RomanNumbers', 'BopomofoBraille', 'InfoCollector',
             'OpenCCBridge', 'SystemCharacterInfo']
    list(map(lambda name: (output / name).mkdir(exist_ok=True),
             ['Objects', 'Modules', 'GeneratedHeaders']))
    list(map(lambda name: compile_dependency(name, root, output, common), names))
    bridged = ['CandidateUI', 'NSStringUtils', 'OpenCCBridge', 'ChineseNumbers',
               'RomanNumbers', 'BopomofoBraille']
    module_map = output / 'GeneratedHeaders/module.modulemap'
    module_map.write_text('\n'.join(map(lambda name:
        f'module {name} {{ header "{name}-Swift.h" export * }}', bridged)))


def prepare_bundle(bundle, resources):
    (bundle / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (bundle / 'Contents/Resources').unlink(missing_ok=True)
    (bundle / 'Contents/Resources').symlink_to(resources)
    run(['plutil', '-create', 'xml1', bundle / 'Contents/Info.plist'])
    run(['plutil', '-insert', 'CFBundleIdentifier', '-string',
         'org.openvanilla.McBopomofo.MixedInputTests', bundle / 'Contents/Info.plist'])
    run(['plutil', '-insert', 'CFBundleExecutable', '-string', 'MixedInputTests',
         bundle / 'Contents/Info.plist'])


def prepare_dependencies(skip, root, output, common):
    if not skip:
        compile_dependencies(root, output, common)


def baseline_paths(baseline_enabled, root, output, bridge_paths):
    if baseline_enabled:
        baseline = output / 'BaselineKeyHandler.mm'
        baseline.write_text(subprocess.check_output(
            ['git', '-C', str(root), 'show', 'HEAD:Source/KeyHandler.mm'], text=True))
        bridge_paths[0] = baseline
    return bridge_paths


def filter_arguments(name):
    return ['--filter', name] if name else []


def export_coverage(executable, output, root):
    profile = output / 'coverage.profdata'
    run(['xcrun', 'llvm-profdata', 'merge', '-sparse', output / 'coverage.profraw', '-o', profile])
    coverage = subprocess.check_output(['xcrun', 'llvm-cov', 'export', str(executable),
        '-instr-profile=' + str(profile), '-format=lcov'], text=True)
    # Test copies only remove their import of the module compiled in this runner;
    # source line numbers are identical to the checked-in test files.
    coverage = coverage.replace(str(output / 'MixedInputKeyHandlerTests.swift'),
                                str(root / 'McBopomofoTests/MixedInputKeyHandlerTests.swift'))
    coverage = coverage.replace(str(output / 'MixedInputPersonalizationTests.swift'),
                                str(root / 'McBopomofoTests/MixedInputPersonalizationTests.swift'))
    (output / 'coverage.lcov').write_text(coverage)


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument('--filter', help='Swift Testing name filter')
    arguments.add_argument('--skip-dependencies', action='store_true')
    arguments.add_argument('--baseline', action='store_true', help='Use HEAD KeyHandler for regression comparison')
    options = arguments.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = root / 'Artifacts/MixedInputTests'
    output.mkdir(parents=True, exist_ok=True)
    dependencies = output
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    frameworks = developer / 'Library/Developer/Frameworks'
    modules = output / 'Modules'
    headers = output / 'GeneratedHeaders'
    headers.mkdir(exist_ok=True)
    sources = sorted((root / 'Source').glob('*.swift'))
    sources.remove(root / 'Source/main.swift')
    sources.extend(sorted((root / 'Source/PreferencesUI').glob('*.swift')))
    test_files = ['MixedInputKeyHandlerTests.swift', 'MixedInputPersonalizationTests.swift']
    sources.extend(map(lambda name: write_test_source(root / 'McBopomofoTests' / name,
                                                     output / name), test_files))
    runner = output / 'TestMain.swift'
    runner.write_text('import Testing\nimport Darwin\n@main enum TestMain {\n'
                      'static func main() async { let result: CInt = await '
                      'Testing.__swiftPMEntryPoint(); exit(result) }\n}\n')
    sources.append(runner)
    swift_common = ['-sdk', sdk, '-target', 'arm64-apple-macosx14.0', '-swift-version', '5',
                    '-module-cache-path', output / 'ModuleCache', '-I', modules,
                    '-F', frameworks, '-load-plugin-library',
                    developer / 'usr/lib/swift/host/plugins/testing/libTestingMacros.dylib',
                    '-profile-generate', '-profile-coverage-mapping']
    prepare_dependencies(options.skip_dependencies, root, output, swift_common)
    application_object = output / 'McBopomofo.o'
    run(['xcrun', 'swiftc', *swift_common, '-parse-as-library', '-whole-module-optimization',
         '-emit-object', '-emit-module', '-emit-module-path', output / 'McBopomofo.swiftmodule',
         '-emit-objc-header', '-emit-objc-header-path', headers / 'McBopomofo-Swift.h',
         '-import-objc-header', root / 'Source/McBopomofo-Bridging-Header.h',
         '-Xcc', '-I' + str(root / 'Source'), '-module-name', 'McBopomofo',
         '-o', application_object, *sources])
    objc_common = ['-std=c++20', '-fobjc-arc', '-fblocks', '-fmodules', '-fcxx-modules',
                   '-fmodules-cache-path=' + str(output / 'ClangModuleCache'),
                   '-isysroot', sdk, '-isystem', sdk + '/usr/include/c++/v1',
                   '-mmacosx-version-min=14.0', '-fprofile-instr-generate', '-fcoverage-mapping',
                   '-I', root / 'Source', '-I', root / 'Source/Engine',
                   '-I', root / 'Source/Engine/Mandarin',
                   '-I', root / 'Source/Engine/gramambular2', '-I', headers,
                   '-I', output / 'GeneratedHeaders',
                   '-fmodule-map-file=' + str(output / 'GeneratedHeaders/module.modulemap')]
    bridge_sources = ['KeyHandler.mm', 'LanguageModelManager.mm', 'ServiceProviderInputHelper.mm']
    bridge_paths = list(map(lambda name: root / 'Source' / name, bridge_sources))
    bridge_paths = baseline_paths(options.baseline, root, output, bridge_paths)
    bridges = list(map(lambda path: compile_bridge(path, objc_common, output), bridge_paths))
    run(['cmake', '-S', root / 'Source', '-B', dependencies / 'Engine',
         '-DENABLE_TEST=OFF', '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0',
         '-DCMAKE_OSX_SYSROOT=' + sdk, '-DCMAKE_CXX_FLAGS=-isystem ' + sdk + '/usr/include/c++/v1'])
    run(['cmake', '--build', dependencies / 'Engine', '--parallel'])
    excluded = {'McBopomofo.o', *map(lambda name: Path(name).stem + '.o', bridge_sources)}
    dependency_objects = list(filter(lambda path: path.name not in excluded,
                                     (output / 'Objects').glob('*.o')))
    bundle = output / 'MixedInputTests.app'
    prepare_bundle(bundle, root / 'Source/Data')
    executable = bundle / 'Contents/MacOS/MixedInputTests'
    run(['xcrun', 'swiftc', *swift_common, '-o', executable, application_object,
         *bridges, *dependency_objects,
         dependencies / 'Engine/Engine/libMcBopomofoLMLib.a',
         dependencies / 'Engine/Engine/Mandarin/libMandarinLib.a',
         dependencies / 'Engine/Engine/gramambular2/libgramambular2_lib.a',
         '-framework', 'AppKit', '-framework', 'Carbon', '-framework', 'CoreServices',
         '-framework', 'InputMethodKit', '-framework', 'IOKit', '-framework', 'Security',
         '-framework', 'Testing', '-Xlinker', '-lc++', '-Xlinker', '-rpath',
         '-Xlinker', frameworks, '-Xlinker', '-rpath', '-Xlinker',
         developer / 'Library/Developer/usr/lib'])
    environment = dict(os.environ, LLVM_PROFILE_FILE=str(output / 'coverage.profraw'))
    test_arguments = filter_arguments(options.filter)
    run([executable, '--no-parallel', *test_arguments], environment)
    export_coverage(executable, output, root)


if __name__ == '__main__':
    main()
