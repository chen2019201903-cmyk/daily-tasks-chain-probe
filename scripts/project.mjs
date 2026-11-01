import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Generates a standard, dependency-free Xcode project. Commit the generated
// files so Xcode can open it directly; --check detects stale generated files.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const id = name => createHash('sha256').update(`ChainProbe:${name}`).digest('hex').slice(0, 24).toUpperCase();
const objects = {};
const add = (name, value) => { objects[id(name)] = value; return id(name); };
const sourceFiles = [
  'Sources/App/ChainProbeApp.swift',
  'Sources/App/ProbeModel.swift',
  'Sources/ProbeCore/MarkerStore.swift',
];
const sources = sourceFiles.map(path => add(`file:${path}`, {
  isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path, sourceTree: '<group>',
}));
const builds = sources.map(fileRef => add(`build:${fileRef}`, { isa: 'PBXBuildFile', fileRef }));
const plist = add('plist', {
  isa: 'PBXFileReference', lastKnownFileType: 'text.plist.xml',
  path: 'Sources/App/Info.plist', sourceTree: '<group>',
});
const product = add('product', {
  isa: 'PBXFileReference', explicitFileType: 'wrapper.application',
  includeInIndex: '0', path: 'ChainProbe.app', sourceTree: 'BUILT_PRODUCTS_DIR',
});
const productGroup = add('products', { isa: 'PBXGroup', children: [product], name: 'Products', sourceTree: '<group>' });
const mainGroup = add('mainGroup', { isa: 'PBXGroup', children: [...sources, plist, productGroup], sourceTree: '<group>' });
const sourcePhase = add('sources', {
  isa: 'PBXSourcesBuildPhase', buildActionMask: '2147483647', files: builds, runOnlyForDeploymentPostprocessing: '0',
});
const frameworkPhase = add('frameworks', {
  isa: 'PBXFrameworksBuildPhase', buildActionMask: '2147483647', files: [], runOnlyForDeploymentPostprocessing: '0',
});
const resourcePhase = add('resources', {
  isa: 'PBXResourcesBuildPhase', buildActionMask: '2147483647', files: [], runOnlyForDeploymentPostprocessing: '0',
});
const projectBase = {
  CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES',
  SDKROOT: 'iphoneos', IPHONEOS_DEPLOYMENT_TARGET: '17.0', SWIFT_VERSION: '5.0',
  SWIFT_STRICT_CONCURRENCY: 'targeted', ENABLE_USER_SCRIPT_SANDBOXING: 'YES',
};
const targetBase = {
  PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: 'com.dailyhabit.chainprobe',
  MARKETING_VERSION: '0.1.0', CURRENT_PROJECT_VERSION: '1.1', PROBE_VARIANT: 'A',
  INFOPLIST_FILE: 'Sources/App/Info.plist', GENERATE_INFOPLIST_FILE: 'NO',
  CODE_SIGNING_ALLOWED: 'NO', CODE_SIGNING_REQUIRED: 'NO', CODE_SIGN_IDENTITY: '',
  DEVELOPMENT_TEAM: '', CODE_SIGN_STYLE: 'Manual',
  TARGETED_DEVICE_FAMILY: '1', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator',
  SUPPORTS_MACCATALYST: 'NO', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: 'NO',
  LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks'],
};
for (const [scope, base] of [['project', projectBase], ['target', targetBase]]) {
  const configs = ['Debug', 'Release'].map(name => add(`${scope}:${name}`, {
    isa: 'XCBuildConfiguration', name,
    buildSettings: {
      ...base,
      ...(scope === 'project' ? {
        DEBUG_INFORMATION_FORMAT: name === 'Debug' ? 'dwarf' : 'dwarf-with-dsym',
        SWIFT_OPTIMIZATION_LEVEL: name === 'Debug' ? '-Onone' : '-O',
        SWIFT_COMPILATION_MODE: name === 'Debug' ? 'singlefile' : 'wholemodule',
        ONLY_ACTIVE_ARCH: name === 'Debug' ? 'YES' : 'NO',
      } : {}),
    },
  }));
  add(`${scope}:configs`, {
    isa: 'XCConfigurationList', buildConfigurations: configs,
    defaultConfigurationIsVisible: '0', defaultConfigurationName: 'Release',
  });
}
const target = add('target', {
  isa: 'PBXNativeTarget', buildConfigurationList: id('target:configs'),
  buildPhases: [sourcePhase, frameworkPhase, resourcePhase], buildRules: [], dependencies: [],
  name: 'ChainProbe', productName: 'ChainProbe', productReference: product,
  productType: 'com.apple.product-type.application',
});
const project = add('project', {
  isa: 'PBXProject', attributes: { LastUpgradeCheck: '1600' },
  buildConfigurationList: id('project:configs'), compatibilityVersion: 'Xcode 14.0',
  developmentRegion: 'zh_CN', hasScannedForEncodings: '0', knownRegions: ['en', 'zh-Hans', 'Base'],
  mainGroup, productRefGroup: productGroup, projectDirPath: '', projectRoot: '', targets: [target],
});
function openStep(value, depth = 0) {
  const pad = '\t'.repeat(depth);
  if (Array.isArray(value)) return `(\n${value.map(item => `${pad}\t${openStep(item, depth + 1)},`).join('\n')}\n${pad})`;
  if (value && typeof value === 'object') {
    return `{\n${Object.entries(value).map(([key, item]) => `${pad}\t${JSON.stringify(key)} = ${openStep(item, depth + 1)};`).join('\n')}\n${pad}}`;
  }
  return JSON.stringify(String(value));
}
const reference = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="ChainProbe.app" BlueprintName="ChainProbe" ReferencedContainer="container:ChainProbe.xcodeproj"/>`;
const outputs = {
  'ChainProbe.xcodeproj/project.pbxproj': '// !$*UTF8*$!\n' + openStep({ archiveVersion: '1', classes: {}, objectVersion: '56', objects, rootObject: project }) + '\n',
  'ChainProbe.xcodeproj/xcshareddata/xcschemes/ChainProbe.xcscheme': `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${reference}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">${reference}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">${reference}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`,
};
for (const [relative, content] of Object.entries(outputs)) {
  const path = resolve(root, relative);
  if (process.argv.includes('--check')) {
    const actual = await readFile(path, 'utf8');
    if (actual.replaceAll('\r\n', '\n') !== content) throw new Error(`Stale generated project: ${relative}`);
  } else {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, content, 'utf8');
  }
}
console.log(process.argv.includes('--check') ? 'Xcode project matches its generator.' : 'Generated Xcode project and shared scheme.');
