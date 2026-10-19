#!/usr/bin/env python3
"""Generate a dependency-free native macOS Xcode project. No package manager required."""
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WorkRhythm.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(name, body):
    key = ident(name)
    objects[key] = body
    return key

def refs(values):
    return "(" + ",".join(values) + ",)"

sources = sorted((ROOT / "Sources").rglob("*.swift"))
file_refs = []
build_refs = []
for path in sources:
    relative = path.relative_to(ROOT).as_posix()
    file_ref = add(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    file_refs.append(file_ref)
    build_refs.append(add("build:" + relative, f"isa = PBXBuildFile; fileRef = {file_ref};"))
app = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "工位节奏.app"; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f"isa = PBXGroup; children = {refs([app])}; name = Products; sourceTree = \"<group>\";")
main_group = add("main-group", f'isa = PBXGroup; children = {refs(file_refs + [products])}; sourceTree = "<group>";')
phase = add("sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(build_refs)}; runOnlyForDeploymentPostprocessing = 0;")
frameworks = add("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
icon_ref = add("icon", 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = SOURCE_ROOT;')
icon_build = add("build-icon", f"isa = PBXBuildFile; fileRef = {icon_ref};")
resources = add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs([icon_build])}; runOnlyForDeploymentPostprocessing = 0;")
common = """
    MACOSX_DEPLOYMENT_TARGET = 14.0;
    SDKROOT = macosx;
    SWIFT_VERSION = 5.0;
    CLANG_ENABLE_MODULES = YES;
    CODE_SIGN_STYLE = Manual;
    CODE_SIGN_IDENTITY = "-";
    ENABLE_HARDENED_RUNTIME = YES;
    ENABLE_APP_SANDBOX = NO;
    PRODUCT_BUNDLE_IDENTIFIER = local.workrhythm.app;
    PRODUCT_NAME = "工位节奏";
    MARKETING_VERSION = 1.1.0;
    CURRENT_PROJECT_VERSION = 24;
    GENERATE_INFOPLIST_FILE = NO;
    INFOPLIST_FILE = Resources/Info.plist;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
    SWIFT_EMIT_LOC_STRINGS = NO;
"""
target_configs = []
project_configs = []
for name in ["Debug", "Release"]:
    settings = common + (
        "\nSWIFT_OPTIMIZATION_LEVEL = \"-Onone\"; DEBUG_INFORMATION_FORMAT = dwarf;"
        if name == "Debug"
        else '\nSWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'
    )
    target_configs.append(add("target-config-" + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{{settings}}};'))
    project_configs.append(add("project-config-" + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; }};'))
target_list = add("target-config-list", f"isa = XCConfigurationList; buildConfigurations = {refs(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
project_list = add("project-config-list", f"isa = XCConfigurationList; buildConfigurations = {refs(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = {refs([phase, frameworks, resources])}; buildRules = (); dependencies = (); name = WorkRhythm; productName = WorkRhythm; productReference = {app}; productType = "com.apple.product-type.application";')
root = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans"); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([target])};')
output = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
output += "\n".join(f"{key} = {{{value}}};" for key, value in objects.items())
output += f"\n}}; rootObject = {root}; }}\n"
(PROJECT / "project.pbxproj").write_text(output)
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="工位节奏.app" BlueprintName="WorkRhythm" ReferencedContainer="container:WorkRhythm.xcodeproj"/>'
(scheme_dir / "WorkRhythm.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(PROJECT)
