#!/usr/bin/env python3
"""Generate the committed, dependency-free Xcode project deterministically."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, value):
    key = ident(name)
    objects[key] = value
    return key
def quote(value): return json.dumps(str(value))
def array(values): return '(' + ', '.join(values) + (',)' if values else ')')
def obj(**values): return '{ ' + ' '.join(f'{k} = {v};' for k,v in values.items()) + ' }'

project = ident('project')
package = add('package', obj(isa='XCRemoteSwiftPackageReference', repositoryURL=quote('https://github.com/sindresorhus/KeyboardShortcuts'), requirement=obj(kind='exactVersion', version='3.1.0')))
packageProduct = add('package-product', obj(isa='XCSwiftPackageProductDependency', package=package, productName='KeyboardShortcuts'))
packageBuild = add('package-build', obj(isa='PBXBuildFile', productRef=packageProduct))
products = []
groups = []
targets = []
for name, folder, productType, extension in [
    ('Disciplina', 'Disciplina', 'com.apple.product-type.application', 'app'),
    ('DisciplinaTests', 'DisciplinaTests', 'com.apple.product-type.bundle.unit-test', 'xctest'),
    ('DisciplinaUITests', 'DisciplinaUITests', 'com.apple.product-type.bundle.ui-testing', 'xctest')]:
    files = []
    builds = []
    for path in sorted((ROOT / folder).rglob('*.swift')):
        relative = path.relative_to(ROOT).as_posix()
        ref = add(relative, obj(isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=quote(relative), sourceTree=quote('SOURCE_ROOT')))
        files.append(ref)
        builds.append(add(relative + '-build', obj(isa='PBXBuildFile', fileRef=ref)))
    groups.append(add(folder+'-group', obj(isa='PBXGroup', children=array(files), name=quote(folder), sourceTree=quote('<group>'))))
    product = add(name+'-product', obj(isa='PBXFileReference', explicitFileType=quote('wrapper.application' if extension == 'app' else 'wrapper.cfbundle'), includeInIndex='0', path=quote(name+'.'+extension), sourceTree='BUILT_PRODUCTS_DIR'))
    products.append(product)
    sources = add(name+'-sources', obj(isa='PBXSourcesBuildPhase', buildActionMask='2147483647', files=array(builds), runOnlyForDeploymentPostprocessing='0'))
    frameworks = add(name+'-frameworks', obj(isa='PBXFrameworksBuildPhase', buildActionMask='2147483647', files=array([packageBuild] if name == 'Disciplina' else []), runOnlyForDeploymentPostprocessing='0'))
    resources = add(name+'-resources', obj(isa='PBXResourcesBuildPhase', buildActionMask='2147483647', files='()', runOnlyForDeploymentPostprocessing='0'))
    configs = []
    for config in ['Debug', 'Release']:
        settings = dict(PRODUCT_NAME=quote('$(TARGET_NAME)'), PRODUCT_BUNDLE_IDENTIFIER=quote('com.danyloplaksyvy.'+name), SWIFT_VERSION='6.0', MACOSX_DEPLOYMENT_TARGET='14.0', SDKROOT='macosx', CODE_SIGN_IDENTITY=quote('-'), CODE_SIGN_STYLE='Manual', COMBINE_HIDPI_IMAGES='YES', SWIFT_EMIT_LOC_STRINGS='YES', LD_RUNPATH_SEARCH_PATHS=quote('$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'))
        if name == 'Disciplina':
            settings.update(INFOPLIST_FILE=quote('Config/Info.plist'), CODE_SIGN_ENTITLEMENTS=quote('Config/Disciplina.entitlements'), ENABLE_APP_SANDBOX='YES')
        else:
            settings['GENERATE_INFOPLIST_FILE'] = 'YES'
            if name == 'DisciplinaTests':
                settings.update(TEST_HOST=quote('$(BUILT_PRODUCTS_DIR)/Disciplina.app/Contents/MacOS/Disciplina'), BUNDLE_LOADER=quote('$(TEST_HOST)'))
            else: settings['TEST_TARGET_NAME'] = 'Disciplina'
        configs.append(add(name+config, obj(isa='XCBuildConfiguration', buildSettings=obj(**settings), name=config)))
    configList = add(name+'-configs', obj(isa='XCConfigurationList', buildConfigurations=array(configs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
    deps = []
    if name != 'Disciplina':
        proxy = add(name+'-proxy', obj(isa='PBXContainerItemProxy', containerPortal=project, proxyType='1', remoteGlobalIDString=ident('Disciplina-target'), remoteInfo='Disciplina'))
        deps.append(add(name+'-dependency', obj(isa='PBXTargetDependency', target=ident('Disciplina-target'), targetProxy=proxy)))
    targets.append(add(name+'-target', obj(isa='PBXNativeTarget', buildConfigurationList=configList, buildPhases=array([sources,frameworks,resources]), buildRules='()', dependencies=array(deps), name=name, packageProductDependencies=array([packageProduct] if name == 'Disciplina' else []), productName=name, productReference=product, productType=quote(productType))))
productsGroup = add('products-group', obj(isa='PBXGroup', children=array(products), name='Products', sourceTree=quote('<group>')))
rootGroup = add('root-group', obj(isa='PBXGroup', children=array(groups+[productsGroup]), sourceTree=quote('<group>')))
configs = []
for config in ['Debug','Release']:
    settings = dict(ONLY_ACTIVE_ARCH='YES' if config == 'Debug' else 'NO', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES', SWIFT_VERSION='6.0', MACOSX_DEPLOYMENT_TARGET='14.0', SDKROOT='macosx', DEBUG_INFORMATION_FORMAT=quote('dwarf' if config=='Debug' else 'dwarf-with-dsym'), SWIFT_OPTIMIZATION_LEVEL=quote('-Onone' if config=='Debug' else '-O'), ENABLE_TESTABILITY='YES' if config=='Debug' else 'NO', SWIFT_ACTIVE_COMPILATION_CONDITIONS=quote('DEBUG $(inherited)' if config=='Debug' else '$(inherited)'))
    configs.append(add('project-'+config, obj(isa='XCBuildConfiguration', buildSettings=obj(**settings), name=config)))
configList = add('project-configs', obj(isa='XCConfigurationList', buildConfigurations=array(configs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
add('project', obj(isa='PBXProject', attributes=obj(BuildIndependentTargetsInParallel='YES', LastUpgradeCheck='2600'), buildConfigurationList=configList, compatibilityVersion=quote('Xcode 14.0'), developmentRegion='en', hasScannedForEncodings='0', knownRegions='(en, Base,)', mainGroup=rootGroup, packageReferences=array([package]), productRefGroup=productsGroup, projectDirPath=quote(''), projectRoot=quote(''), targets=array(targets)))
projectDir = ROOT/'Disciplina.xcodeproj'
projectDir.mkdir(exist_ok=True)
(projectDir/'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n'+'\n'.join(f'{key} = {value};' for key,value in objects.items())+'\n};\nrootObject = '+project+';\n}\n')
schemeDir = projectDir/'xcshareddata/xcschemes'
schemeDir.mkdir(parents=True, exist_ok=True)
def reference(name):
    ext = 'app' if name == 'Disciplina' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name+"-target")}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:Disciplina.xcodeproj"/>'
(schemeDir/'Disciplina.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('Disciplina')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO">{reference('DisciplinaTests')}</TestableReference>
<TestableReference skipped="NO">{reference('DisciplinaUITests')}</TestableReference>
</Testables><EnvironmentVariables><EnvironmentVariable key="DISCIPLINA_TESTING" value="1" isEnabled="YES"/></EnvironmentVariables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Disciplina')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Disciplina')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
workspace = projectDir/'project.xcworkspace'
workspace.mkdir(exist_ok=True)
(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
print('Generated Disciplina.xcodeproj')
