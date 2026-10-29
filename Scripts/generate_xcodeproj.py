#!/usr/bin/env python3
"""Generate FennFocus.xcodeproj/project.pbxproj with stable UUIDs.

Targets:
  - FennFocusCore (framework) — Sources/FennFocusCore + Shared JSON
  - FennFocus (macOS app) — Sources/FennFocus + Assets; embeds Extension + Core
  - FennFocusWidgets (WidgetKit) — Sources/FennFocusWidgets

Run from anywhere; paths are relative to the repository root. Signing, bundle ids and the App Group come from
Config/Base.xcconfig (and your own, git-ignored Config/Local.xcconfig).
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # repository root
PROJ = ROOT / "FennFocus.xcodeproj"
PBX = PROJ / "project.pbxproj"
SCHEME = PROJ / "xcshareddata" / "xcschemes" / "FennFocus.xcscheme"


def uid(name: str) -> str:
    """Deterministic 24-hex Xcode-style ID from a stable name."""
    digest = hashlib.sha1(f"fennfocus.{name}".encode()).hexdigest().upper()
    return digest[:24]


# --- File lists ---
CORE_SWIFT = sorted((ROOT / "Sources" / "FennFocusCore").glob("*.swift"))
HOST_SWIFT = sorted((ROOT / "Sources" / "FennFocus").glob("*.swift"))
EXT_SWIFT = sorted((ROOT / "Sources" / "FennFocusWidgets").glob("*.swift"))
SHARED_JSON = sorted((ROOT / "Shared").glob("*.json"))
# Extension files the app compiles too (the widget QA gallery renders the real widget views).
EXT_ALSO_IN_HOST = [p for p in EXT_SWIFT if p.name in {"DesktopClayViews.swift"}]

assert CORE_SWIFT, "FennFocusCore sources missing"
assert HOST_SWIFT, "FennFocus sources missing"
assert EXT_SWIFT, "FennFocusWidgets sources missing"

# --- IDs ---
PROJECT = uid("project")
ROOT_GROUP = uid("root_group")
PRODUCTS = uid("products")
SOURCES_GROUP = uid("sources_group")
CORE_GROUP = uid("core_group")
HOST_GROUP = uid("host_group")
EXT_GROUP = uid("ext_group")
SHARED_GROUP = uid("shared_group")
SUPPORT_GROUP = uid("support_group")
BASE_XCCONFIG = uid("base_xcconfig")
FRAMEWORKS_GROUP = uid("frameworks_group")

CORE_TARGET = uid("core_target")
HOST_TARGET = uid("host_target")
EXT_TARGET = uid("ext_target")

CORE_PRODUCT = uid("core_product")
HOST_PRODUCT = uid("host_product")
EXT_PRODUCT = uid("ext_product")

CORE_CONFIG_LIST = uid("core_config_list")
HOST_CONFIG_LIST = uid("host_config_list")
EXT_CONFIG_LIST = uid("ext_config_list")
PROJECT_CONFIG_LIST = uid("project_config_list")

CORE_DEBUG = uid("core_debug")
CORE_RELEASE = uid("core_release")
HOST_DEBUG = uid("host_debug")
HOST_RELEASE = uid("host_release")
EXT_DEBUG = uid("ext_debug")
EXT_RELEASE = uid("ext_release")
PROJ_DEBUG = uid("proj_debug")
PROJ_RELEASE = uid("proj_release")

# Build phases
CORE_SOURCES_PHASE = uid("core_sources_phase")
CORE_FRAMEWORKS_PHASE = uid("core_frameworks_phase")
CORE_RESOURCES_PHASE = uid("core_resources_phase")
CORE_HEADERS_PHASE = uid("core_headers_phase")

HOST_SOURCES_PHASE = uid("host_sources_phase")
HOST_FRAMEWORKS_PHASE = uid("host_frameworks_phase")
HOST_RESOURCES_PHASE = uid("host_resources_phase")
HOST_EMBED_FRAMEWORKS = uid("host_embed_frameworks")
HOST_EMBED_EXTENSIONS = uid("host_embed_extensions")

EXT_SOURCES_PHASE = uid("ext_sources_phase")
EXT_FRAMEWORKS_PHASE = uid("ext_frameworks_phase")
EXT_RESOURCES_PHASE = uid("ext_resources_phase")

# Dependencies / container proxies
HOST_DEP_CORE = uid("host_dep_core")
HOST_DEP_EXT = uid("host_dep_ext")
EXT_DEP_CORE = uid("ext_dep_core")
PROXY_CORE_FOR_HOST = uid("proxy_core_for_host")
PROXY_EXT_FOR_HOST = uid("proxy_ext_for_host")
PROXY_CORE_FOR_EXT = uid("proxy_core_for_ext")

# Product refs in embed phases (same product file refs reused)
CORE_IN_HOST_FW = uid("core_in_host_fw")  # PBXBuildFile embed
EXT_IN_HOST_EMB = uid("ext_in_host_emb")
CORE_IN_HOST_LINK = uid("core_in_host_link")
# Swift packages of the host app: MLX for Fenn's built-in Small and Big Brain (Qwen 3.5), swift-transformers for the tokenizer.
PACKAGES = [
    ("mlx-swift-lm", "https://github.com/ml-explore/mlx-swift-lm", "3.32.3", ["MLXLLM", "MLXLMCommon"]),
    ("swift-transformers", "https://github.com/huggingface/swift-transformers", "1.3.0", ["Tokenizers"]),
]
PACKAGE_REFS = {name: uid(f"package_{name}") for name, *_ in PACKAGES}
PRODUCT_DEPS = [(product, uid(f"product_{product}"), uid(f"product_link_{product}"), name)
                for name, _, _, products in PACKAGES for product in products]
CORE_IN_EXT_LINK = uid("core_in_ext_link")

# Support file refs
HOST_ENTITLEMENTS = uid("host_entitlements")
EXT_ENTITLEMENTS = uid("ext_entitlements")
HOST_INFO = uid("host_info")
EXT_INFO = uid("ext_info")
ASSETS = uid("assets")
ASSETS_BUILD = uid("assets_build")
# The widget extension gets its own small catalog (rank pebbles) – not the app icon and backdrop.
EXT_ASSETS = uid("ext_assets")
EXT_ASSETS_BUILD = uid("ext_assets_build")

WIDGETKIT_REF = uid("widgetkit_ref")
WIDGETKIT_HOST = uid("widgetkit_host_link")  # optional; Host may not need WidgetKit directly
WIDGETKIT_EXT = uid("widgetkit_ext_link")
SWIFTUI_REF = uid("swiftui_ref")
FOUNDATION_REF = uid("foundation_ref")

# File → IDs
file_refs: dict[str, str] = {}
build_files: dict[str, str] = {}


def file_id(key: str) -> str:
    if key not in file_refs:
        file_refs[key] = uid(f"fileref.{key}")
    return file_refs[key]


def build_id(key: str) -> str:
    if key not in build_files:
        build_files[key] = uid(f"buildfile.{key}")
    return build_files[key]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


lines: list[str] = []


def w(s: str = "") -> None:
    lines.append(s)


w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")
w("")

# --- PBXBuildFile ---
w("/* Begin PBXBuildFile section */")
for p in CORE_SWIFT:
    key = f"core.src.{p.name}"
    w(f"\t\t{build_id(key)} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id(key)} /* {p.name} */; }};")
for p in SHARED_JSON:
    key = f"core.res.{p.name}"
    w(f"\t\t{build_id(key)} /* {p.name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_id(key)} /* {p.name} */; }};")
for p in HOST_SWIFT:
    key = f"host.src.{p.name}"
    w(f"\t\t{build_id(key)} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id(key)} /* {p.name} */; }};")
for p in EXT_SWIFT:
    key = f"ext.src.{p.name}"
    w(f"\t\t{build_id(key)} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id(key)} /* {p.name} */; }};")
for p in EXT_ALSO_IN_HOST:
    w(f"\t\t{build_id('hostshared.' + p.name)} /* {p.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id('ext.src.' + p.name)} /* {p.name} */; }};")
w(f"\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS} /* Assets.xcassets */; }};")
w(f"\t\t{EXT_ASSETS_BUILD} /* WidgetAssets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {EXT_ASSETS} /* WidgetAssets.xcassets */; }};")
w(f"\t\t{CORE_IN_HOST_LINK} /* FennFocusCore.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {CORE_PRODUCT} /* FennFocusCore.framework */; }};")
w(f"\t\t{CORE_IN_EXT_LINK} /* FennFocusCore.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {CORE_PRODUCT} /* FennFocusCore.framework */; }};")
w(f"\t\t{CORE_IN_HOST_FW} /* FennFocusCore.framework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {CORE_PRODUCT} /* FennFocusCore.framework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};")
w(f"\t\t{EXT_IN_HOST_EMB} /* FennFocusWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {EXT_PRODUCT} /* FennFocusWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
w(f"\t\t{WIDGETKIT_EXT} /* WidgetKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {WIDGETKIT_REF} /* WidgetKit.framework */; }};")
for product, dep, link, _ in PRODUCT_DEPS:
    w(f"\t\t{link} /* {product} in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep} /* {product} */; }};")
w("/* End PBXBuildFile section */")
w("")

# --- PBXContainerItemProxy ---
w("/* Begin PBXContainerItemProxy section */")
w(f"\t\t{PROXY_CORE_FOR_HOST} /* PBXContainerItemProxy */ = {{")
w("\t\t\tisa = PBXContainerItemProxy;")
w(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
w("\t\t\tproxyType = 1;")
w(f"\t\t\tremoteGlobalIDString = {CORE_TARGET};")
w("\t\t\tremoteInfo = FennFocusCore;")
w("\t\t};")
w(f"\t\t{PROXY_EXT_FOR_HOST} /* PBXContainerItemProxy */ = {{")
w("\t\t\tisa = PBXContainerItemProxy;")
w(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
w("\t\t\tproxyType = 1;")
w(f"\t\t\tremoteGlobalIDString = {EXT_TARGET};")
w("\t\t\tremoteInfo = FennFocusWidgets;")
w("\t\t};")
w(f"\t\t{PROXY_CORE_FOR_EXT} /* PBXContainerItemProxy */ = {{")
w("\t\t\tisa = PBXContainerItemProxy;")
w(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
w("\t\t\tproxyType = 1;")
w(f"\t\t\tremoteGlobalIDString = {CORE_TARGET};")
w("\t\t\tremoteInfo = FennFocusCore;")
w("\t\t};")
w("/* End PBXContainerItemProxy section */")
w("")

# --- PBXCopyFilesBuildPhase (Embed) ---
w("/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{HOST_EMBED_FRAMEWORKS} /* Embed Frameworks */ = {{")
w("\t\t\tisa = PBXCopyFilesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tdstPath = \"\";")
w("\t\t\tdstSubfolderSpec = 10;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{CORE_IN_HOST_FW} /* FennFocusCore.framework in Embed Frameworks */,")
w("\t\t\t);")
w("\t\t\tname = \"Embed Frameworks\";")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{HOST_EMBED_EXTENSIONS} /* Embed Foundation Extensions */ = {{")
w("\t\t\tisa = PBXCopyFilesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tdstPath = \"\";")
w("\t\t\tdstSubfolderSpec = 13;")
w("\t\t\tfiles = (")
# Fenn's desktop widgets (pebble, today, tasks, routines, food, training, focus) ship inside the app again.
w(f"\t\t\t\t{EXT_IN_HOST_EMB} /* FennFocusWidgets.appex in Embed Foundation Extensions */,")
w("\t\t\t);")
w("\t\t\tname = \"Embed Foundation Extensions\";")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXCopyFilesBuildPhase section */")
w("")

# --- PBXFileReference ---
w("/* Begin PBXFileReference section */")
w(f"\t\t{CORE_PRODUCT} /* FennFocusCore.framework */ = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = FennFocusCore.framework; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{HOST_PRODUCT} /* FennFocus.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FennFocus.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{EXT_PRODUCT} /* FennFocusWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = FennFocusWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
for p in CORE_SWIFT:
    key = f"core.src.{p.name}"
    w(f"\t\t{file_id(key)} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{p.name}\"; sourceTree = \"<group>\"; }};")
for p in HOST_SWIFT:
    key = f"host.src.{p.name}"
    w(f"\t\t{file_id(key)} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{p.name}\"; sourceTree = \"<group>\"; }};")
for p in EXT_SWIFT:
    key = f"ext.src.{p.name}"
    w(f"\t\t{file_id(key)} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{p.name}\"; sourceTree = \"<group>\"; }};")
for p in SHARED_JSON:
    key = f"core.res.{p.name}"
    w(f"\t\t{file_id(key)} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = \"{p.name}\"; sourceTree = \"<group>\"; }};")
w(f"\t\t{HOST_ENTITLEMENTS} /* FennFocus.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = FennFocus.entitlements; sourceTree = \"<group>\"; }};")
w(f"\t\t{EXT_ENTITLEMENTS} /* FennFocusWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = FennFocusWidgets.entitlements; sourceTree = \"<group>\"; }};")
w(f"\t\t{HOST_INFO} /* Host-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"Host-Info.plist\"; sourceTree = \"<group>\"; }};")
w(f"\t\t{EXT_INFO} /* WidgetExtension-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"WidgetExtension-Info.plist\"; sourceTree = \"<group>\"; }};")
w(f"\t\t{ASSETS} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
w(f"\t\t{EXT_ASSETS} /* WidgetAssets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = WidgetAssets.xcassets; sourceTree = \"<group>\"; }};")
w(f"\t\t{WIDGETKIT_REF} /* WidgetKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WidgetKit.framework; path = System/Library/Frameworks/WidgetKit.framework; sourceTree = SDKROOT; }};")
w(f"\t\t{BASE_XCCONFIG} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = Base.xcconfig; path = Config/Base.xcconfig; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")
w("")

# --- PBXFrameworksBuildPhase ---
w("/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{CORE_FRAMEWORKS_PHASE} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{HOST_FRAMEWORKS_PHASE} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{CORE_IN_HOST_LINK} /* FennFocusCore.framework in Frameworks */,")
for product, _, link, _ in PRODUCT_DEPS:
    w(f"\t\t\t\t{link} /* {product} in Frameworks */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{EXT_FRAMEWORKS_PHASE} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{CORE_IN_EXT_LINK} /* FennFocusCore.framework in Frameworks */,")
w(f"\t\t\t\t{WIDGETKIT_EXT} /* WidgetKit.framework in Frameworks */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")
w("")

# --- PBXGroup ---
w("/* Begin PBXGroup section */")
w(f"\t\t{ROOT_GROUP} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{BASE_XCCONFIG} /* Base.xcconfig */,")
w(f"\t\t\t\t{SOURCES_GROUP} /* Sources */,")
w(f"\t\t\t\t{SHARED_GROUP} /* Shared */,")
w(f"\t\t\t\t{SUPPORT_GROUP} /* Support */,")
w(f"\t\t\t\t{FRAMEWORKS_GROUP} /* Frameworks */,")
w(f"\t\t\t\t{PRODUCTS} /* Products */,")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{PRODUCTS} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{HOST_PRODUCT} /* FennFocus.app */,")
w(f"\t\t\t\t{CORE_PRODUCT} /* FennFocusCore.framework */,")
w(f"\t\t\t\t{EXT_PRODUCT} /* FennFocusWidgets.appex */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{SOURCES_GROUP} /* Sources */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{CORE_GROUP} /* FennFocusCore */,")
w(f"\t\t\t\t{HOST_GROUP} /* FennFocus */,")
w(f"\t\t\t\t{EXT_GROUP} /* FennFocusWidgets */,")
w("\t\t\t);")
w("\t\t\tpath = Sources;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{CORE_GROUP} /* FennFocusCore */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for p in CORE_SWIFT:
    key = f"core.src.{p.name}"
    w(f"\t\t\t\t{file_id(key)} /* {p.name} */,")
w("\t\t\t);")
w("\t\t\tpath = FennFocusCore;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{HOST_GROUP} /* FennFocus */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for p in HOST_SWIFT:
    key = f"host.src.{p.name}"
    w(f"\t\t\t\t{file_id(key)} /* {p.name} */,")
w("\t\t\t);")
w("\t\t\tpath = FennFocus;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{EXT_GROUP} /* FennFocusWidgets */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for p in EXT_SWIFT:
    key = f"ext.src.{p.name}"
    w(f"\t\t\t\t{file_id(key)} /* {p.name} */,")
w("\t\t\t);")
w("\t\t\tpath = FennFocusWidgets;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{SHARED_GROUP} /* Shared */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for p in SHARED_JSON:
    key = f"core.res.{p.name}"
    w(f"\t\t\t\t{file_id(key)} /* {p.name} */,")
w("\t\t\t);")
w("\t\t\tpath = Shared;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{SUPPORT_GROUP} /* Support */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{ASSETS} /* Assets.xcassets */,")
w(f"\t\t\t\t{EXT_ASSETS} /* WidgetAssets.xcassets */,")
w(f"\t\t\t\t{HOST_ENTITLEMENTS} /* FennFocus.entitlements */,")
w(f"\t\t\t\t{EXT_ENTITLEMENTS} /* FennFocusWidgets.entitlements */,")
w(f"\t\t\t\t{HOST_INFO} /* Host-Info.plist */,")
w(f"\t\t\t\t{EXT_INFO} /* WidgetExtension-Info.plist */,")
w("\t\t\t);")
w("\t\t\tpath = Support;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{FRAMEWORKS_GROUP} /* Frameworks */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{WIDGETKIT_REF} /* WidgetKit.framework */,")
w("\t\t\t);")
w("\t\t\tname = Frameworks;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")
w("")

# --- PBXHeadersBuildPhase (empty for dynamic framework) ---
w("/* Begin PBXHeadersBuildPhase section */")
w(f"\t\t{CORE_HEADERS_PHASE} /* Headers */ = {{")
w("\t\t\tisa = PBXHeadersBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXHeadersBuildPhase section */")
w("")

# --- PBXNativeTarget ---
w("/* Begin PBXNativeTarget section */")
w(f"\t\t{CORE_TARGET} /* FennFocusCore */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {CORE_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocusCore\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{CORE_HEADERS_PHASE} /* Headers */,")
w(f"\t\t\t\t{CORE_SOURCES_PHASE} /* Sources */,")
w(f"\t\t\t\t{CORE_FRAMEWORKS_PHASE} /* Frameworks */,")
w(f"\t\t\t\t{CORE_RESOURCES_PHASE} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = FennFocusCore;")
w("\t\t\tproductName = FennFocusCore;")
w(f"\t\t\tproductReference = {CORE_PRODUCT} /* FennFocusCore.framework */;")
w("\t\t\tproductType = \"com.apple.product-type.framework\";")
w("\t\t};")
w(f"\t\t{HOST_TARGET} /* FennFocus */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {HOST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocus\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{HOST_SOURCES_PHASE} /* Sources */,")
w(f"\t\t\t\t{HOST_FRAMEWORKS_PHASE} /* Frameworks */,")
w(f"\t\t\t\t{HOST_RESOURCES_PHASE} /* Resources */,")
w(f"\t\t\t\t{HOST_EMBED_FRAMEWORKS} /* Embed Frameworks */,")
w(f"\t\t\t\t{HOST_EMBED_EXTENSIONS} /* Embed Foundation Extensions */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w(f"\t\t\t\t{HOST_DEP_CORE} /* PBXTargetDependency */,")
w(f"\t\t\t\t{HOST_DEP_EXT} /* PBXTargetDependency */,")
w("\t\t\t);")
w("\t\t\tpackageProductDependencies = (")
for product, dep, _, _ in PRODUCT_DEPS:
    w(f"\t\t\t\t{dep} /* {product} */,")
w("\t\t\t);")
w("\t\t\tname = FennFocus;")
w("\t\t\tproductName = FennFocus;")
w(f"\t\t\tproductReference = {HOST_PRODUCT} /* FennFocus.app */;")
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w(f"\t\t{EXT_TARGET} /* FennFocusWidgets */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {EXT_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocusWidgets\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{EXT_SOURCES_PHASE} /* Sources */,")
w(f"\t\t\t\t{EXT_FRAMEWORKS_PHASE} /* Frameworks */,")
w(f"\t\t\t\t{EXT_RESOURCES_PHASE} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w(f"\t\t\t\t{EXT_DEP_CORE} /* PBXTargetDependency */,")
w("\t\t\t);")
w("\t\t\tname = FennFocusWidgets;")
w("\t\t\tproductName = FennFocusWidgets;")
w(f"\t\t\tproductReference = {EXT_PRODUCT} /* FennFocusWidgets.appex */;")
w("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")
w("")

# --- PBXProject ---
w("/* Begin PBXProject section */")
w(f"\t\t{PROJECT} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
w("\t\t\t\tLastUpgradeCheck = 1500;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{CORE_TARGET} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w(f"\t\t\t\t\t{HOST_TARGET} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w(f"\t\t\t\t\t{EXT_TARGET} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"FennFocus\" */;")
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t\tde,")
w("\t\t\t);")
w(f"\t\t\tmainGroup = {ROOT_GROUP};")
w("\t\t\tpackageReferences = (")
for name, *_ in PACKAGES:
    w(f"\t\t\t\t{PACKAGE_REFS[name]} /* XCRemoteSwiftPackageReference \"{name}\" */,")
w("\t\t\t);")
w(f"\t\t\tproductRefGroup = {PRODUCTS} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{HOST_TARGET} /* FennFocus */,")
w(f"\t\t\t\t{CORE_TARGET} /* FennFocusCore */,")
w(f"\t\t\t\t{EXT_TARGET} /* FennFocusWidgets */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")
w("")

# --- PBXResourcesBuildPhase ---
w("/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{CORE_RESOURCES_PHASE} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in SHARED_JSON:
    key = f"core.res.{p.name}"
    w(f"\t\t\t\t{build_id(key)} /* {p.name} in Resources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{HOST_RESOURCES_PHASE} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{EXT_RESOURCES_PHASE} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{EXT_ASSETS_BUILD} /* WidgetAssets.xcassets in Resources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")
w("")

# --- PBXSourcesBuildPhase ---
w("/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{CORE_SOURCES_PHASE} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in CORE_SWIFT:
    key = f"core.src.{p.name}"
    w(f"\t\t\t\t{build_id(key)} /* {p.name} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{HOST_SOURCES_PHASE} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in HOST_SWIFT:
    key = f"host.src.{p.name}"
    w(f"\t\t\t\t{build_id(key)} /* {p.name} in Sources */,")
for p in EXT_ALSO_IN_HOST:
    w(f"\t\t\t\t{build_id('hostshared.' + p.name)} /* {p.name} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{EXT_SOURCES_PHASE} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in EXT_SWIFT:
    key = f"ext.src.{p.name}"
    w(f"\t\t\t\t{build_id(key)} /* {p.name} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w("")

# --- PBXTargetDependency ---
w("/* Begin PBXTargetDependency section */")
w(f"\t\t{HOST_DEP_CORE} /* PBXTargetDependency */ = {{")
w("\t\t\tisa = PBXTargetDependency;")
w(f"\t\t\ttarget = {CORE_TARGET} /* FennFocusCore */;")
w(f"\t\t\ttargetProxy = {PROXY_CORE_FOR_HOST} /* PBXContainerItemProxy */;")
w("\t\t};")
w(f"\t\t{HOST_DEP_EXT} /* PBXTargetDependency */ = {{")
w("\t\t\tisa = PBXTargetDependency;")
w(f"\t\t\ttarget = {EXT_TARGET} /* FennFocusWidgets */;")
w(f"\t\t\ttargetProxy = {PROXY_EXT_FOR_HOST} /* PBXContainerItemProxy */;")
w("\t\t};")
w(f"\t\t{EXT_DEP_CORE} /* PBXTargetDependency */ = {{")
w("\t\t\tisa = PBXTargetDependency;")
w(f"\t\t\ttarget = {CORE_TARGET} /* FennFocusCore */;")
w(f"\t\t\ttargetProxy = {PROXY_CORE_FOR_EXT} /* PBXContainerItemProxy */;")
w("\t\t};")
w("/* End PBXTargetDependency section */")
w("")

# --- XCBuildConfiguration ---
COMMON_PROJ = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;
"""

w("/* Begin XCBuildConfiguration section */")
w(f"\t\t{PROJ_DEBUG} /* Debug */ = {{")
w("\t\t\tisa = XCBuildConfiguration;")
w(f"\t\t\tbaseConfigurationReference = {BASE_XCCONFIG} /* Base.xcconfig */;")
w("\t\t\tbuildSettings = {")
w(COMMON_PROJ)
w("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
w("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
w("\t\t\t};")
w("\t\t\tname = Debug;")
w("\t\t};")
w(f"\t\t{PROJ_RELEASE} /* Release */ = {{")
w("\t\t\tisa = XCBuildConfiguration;")
w(f"\t\t\tbaseConfigurationReference = {BASE_XCCONFIG} /* Base.xcconfig */;")
w("\t\t\tbuildSettings = {")
w(COMMON_PROJ.replace("ONLY_ACTIVE_ARCH = YES;", "ONLY_ACTIVE_ARCH = NO;").replace("DEBUG_INFORMATION_FORMAT = dwarf;", "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";"))
w("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
w("\t\t\t};")
w("\t\t\tname = Release;")
w("\t\t};")

# Core Debug/Release
for cfg_id, cfg_name in ((CORE_DEBUG, "Debug"), (CORE_RELEASE, "Release")):
    w(f"\t\t{cfg_id} /* {cfg_name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    w("\t\t\t\tBUILD_LIBRARY_FOR_DISTRIBUTION = NO;")
    w("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    w("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    w("\t\t\t\tDEFINES_MODULE = YES;")
    w("\t\t\t\tDYLIB_COMPATIBILITY_VERSION = 1;")
    w("\t\t\t\tDYLIB_CURRENT_VERSION = 1;")
    w("\t\t\t\tDYLIB_INSTALL_NAME_BASE = \"@rpath\";")
    w("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    w("\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"\";")
    w("\t\t\t\tINSTALL_PATH = \"$(LOCAL_LIBRARY_DIR)/Frameworks\";")
    w("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    w("\t\t\t\t\t\"$(inherited)\",")
    w("\t\t\t\t\t\"@executable_path/../Frameworks\",")
    w("\t\t\t\t\t\"@loader_path/Frameworks\",")
    w("\t\t\t\t);")
    w("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    w("\t\t\t\tMARKETING_VERSION = 1.0;")
    w("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"$(FENN_BUNDLE_PREFIX).core\";")
    w("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    w("\t\t\t\tSKIP_INSTALL = YES;")
    w("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    w("\t\t\t\tSWIFT_VERSION = 5.0;")
    w("\t\t\t\tVERSIONING_SYSTEM = \"apple-generic\";")
    w("\t\t\t\tVERSION_INFO_PREFIX = \"\";")
    w("\t\t\t};")
    w(f"\t\t\tname = {cfg_name};")
    w("\t\t};")

# Host
for cfg_id, cfg_name in ((HOST_DEBUG, "Debug"), (HOST_RELEASE, "Release")):
    w(f"\t\t{cfg_id} /* {cfg_name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    w("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    w("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    w("\t\t\t\tCODE_SIGN_ENTITLEMENTS = Support/FennFocus.entitlements;")
    w("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    w("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    w("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    w("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    w("\t\t\t\tINFOPLIST_FILE = \"Support/Host-Info.plist\";")
    w("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    w("\t\t\t\t\t\"$(inherited)\",")
    w("\t\t\t\t\t\"@executable_path/../Frameworks\",")
    w("\t\t\t\t);")
    w("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    w("\t\t\t\tMARKETING_VERSION = 1.0;")
    w("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"$(FENN_BUNDLE_PREFIX)\";")
    w("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    w("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    w("\t\t\t\tSWIFT_VERSION = 5.0;")
    w("\t\t\t};")
    w(f"\t\t\tname = {cfg_name};")
    w("\t\t};")

# Extension
for cfg_id, cfg_name in ((EXT_DEBUG, "Debug"), (EXT_RELEASE, "Release")):
    w(f"\t\t{cfg_id} /* {cfg_name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    w("\t\t\t\tCODE_SIGN_ENTITLEMENTS = Support/FennFocusWidgets.entitlements;")
    w("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    w("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    w("\t\t\t\tINFOPLIST_FILE = \"Support/WidgetExtension-Info.plist\";")
    w("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    w("\t\t\t\t\t\"$(inherited)\",")
    w("\t\t\t\t\t\"@executable_path/../Frameworks\",")
    w("\t\t\t\t\t\"@executable_path/../../../../Frameworks\",")
    w("\t\t\t\t);")
    w("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    w("\t\t\t\tMARKETING_VERSION = 1.0;")
    w("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"$(FENN_BUNDLE_PREFIX).widgets\";")
    w("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    w("\t\t\t\tSKIP_INSTALL = YES;")
    w("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    w("\t\t\t\tSWIFT_VERSION = 5.0;")
    w("\t\t\t};")
    w(f"\t\t\tname = {cfg_name};")
    w("\t\t};")

w("/* End XCBuildConfiguration section */")
w("")

# --- XCConfigurationList ---
w("/* Begin XCConfigurationList section */")
w(f"\t\t{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"FennFocus\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{PROJ_DEBUG} /* Debug */,")
w(f"\t\t\t\t{PROJ_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w(f"\t\t{CORE_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocusCore\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{CORE_DEBUG} /* Debug */,")
w(f"\t\t\t\t{CORE_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w(f"\t\t{HOST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocus\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{HOST_DEBUG} /* Debug */,")
w(f"\t\t\t\t{HOST_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w(f"\t\t{EXT_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"FennFocusWidgets\" */ = {{")
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w(f"\t\t\t\t{EXT_DEBUG} /* Debug */,")
w(f"\t\t\t\t{EXT_RELEASE} /* Release */,")
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("/* End XCConfigurationList section */")
w("")
w("/* Begin XCRemoteSwiftPackageReference section */")
for name, url, version, _ in PACKAGES:
    w(f"\t\t{PACKAGE_REFS[name]} /* XCRemoteSwiftPackageReference \"{name}\" */ = {{")
    w("\t\t\tisa = XCRemoteSwiftPackageReference;")
    w(f"\t\t\trepositoryURL = \"{url}\";")
    w("\t\t\trequirement = {")
    w("\t\t\t\tkind = upToNextMinorVersion;")
    w(f"\t\t\t\tminimumVersion = {version};")
    w("\t\t\t};")
    w("\t\t};")
w("/* End XCRemoteSwiftPackageReference section */")
w("")
w("/* Begin XCSwiftPackageProductDependency section */")
for product, dep, _, name in PRODUCT_DEPS:
    w(f"\t\t{dep} /* {product} */ = {{")
    w("\t\t\tisa = XCSwiftPackageProductDependency;")
    w(f"\t\t\tpackage = {PACKAGE_REFS[name]} /* XCRemoteSwiftPackageReference \"{name}\" */;")
    w(f"\t\t\tproductName = {product};")
    w("\t\t};")
w("/* End XCSwiftPackageProductDependency section */")
w("\t};")
w(f"\trootObject = {PROJECT} /* Project object */;")
w("}")

PROJ.mkdir(parents=True, exist_ok=True)
PBX.write_text("\n".join(lines) + "\n")
print(f"Wrote {PBX} ({PBX.stat().st_size} bytes)")

# Scheme
SCHEME.parent.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{CORE_TARGET}"
               BuildableName = "FennFocusCore.framework"
               BlueprintName = "FennFocusCore"
               ReferencedContainer = "container:FennFocus.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{EXT_TARGET}"
               BuildableName = "FennFocusWidgets.appex"
               BlueprintName = "FennFocusWidgets"
               ReferencedContainer = "container:FennFocus.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{HOST_TARGET}"
               BuildableName = "FennFocus.app"
               BlueprintName = "FennFocus"
               ReferencedContainer = "container:FennFocus.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{HOST_TARGET}"
            BuildableName = "FennFocus.app"
            BlueprintName = "FennFocus"
            ReferencedContainer = "container:FennFocus.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{HOST_TARGET}"
            BuildableName = "FennFocus.app"
            BlueprintName = "FennFocus"
            ReferencedContainer = "container:FennFocus.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
SCHEME.write_text(scheme)
print(f"Wrote {SCHEME}")
print("Targets: FennFocusCore, FennFocus, FennFocusWidgets")
print(f"Core sources: {len(CORE_SWIFT)}; Host: {len(HOST_SWIFT)}; Ext: {len(EXT_SWIFT)}; Shared: {len(SHARED_JSON)}")
