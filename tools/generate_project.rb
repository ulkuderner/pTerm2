#!/usr/bin/env ruby
# Generates iTerm2Pad.xcodeproj from scratch. Re-run after adding,
# removing, or renaming source files and commit the result.
# Requires the xcodeproj gem: gem install --user-install xcodeproj
#
# Targets:
#   * iTerm2Pad              - SwiftUI iPad app
#   * iTerm2PadFileProvider  - sshfs File Provider extension
#   * iTerm2PadTests         - unit tests hosted by the app

require 'xcodeproj'
require 'pathname'

IPAD_DIR = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(IPAD_DIR, 'iTerm2Pad.xcodeproj')
APP_DIR = File.join(IPAD_DIR, 'iTerm2Pad')
PROVIDER_DIR = File.join(IPAD_DIR, 'iTerm2PadFileProvider')
TESTS_DIR = File.join(IPAD_DIR, 'iTerm2PadTests')
UI_TESTS_DIR = File.join(IPAD_DIR, 'iTerm2PadUITests')
BUNDLE_ID = 'com.googlecode.iterm2.pad'
TEAM = 'H7V7XYVQ7D'
DEPLOYMENT_TARGET = '17.0'
MARKETING_VERSION = '1.0'
CURRENT_PROJECT_VERSION = '1'
SWIFTTERM_URL = 'https://github.com/migueldeicaza/SwiftTerm.git'
# 1.99+ pulls a build plugin that Xcode rejects without user trust.
# 1.5.1 is the last simple iOS TerminalView release without that plugin.
SWIFTTERM_VERSION = '1.5.1'

project = Xcodeproj::Project.new(PROJECT_PATH)

def add_local_package(project, relative_path)
  pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  pkg.relative_path = relative_path
  project.root_object.package_references << pkg
  pkg
end

tmux_pkg = add_local_package(project, 'TmuxControl')
ssh_pkg = add_local_package(project, 'SSHClient')
shell_pkg = add_local_package(project, 'LocalShell')

swiftterm_pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
swiftterm_pkg.repositoryURL = SWIFTTERM_URL
swiftterm_pkg.requirement = { 'kind' => 'exactVersion', 'version' => SWIFTTERM_VERSION }
project.root_object.package_references << swiftterm_pkg

def link_package_product(project, target, package, product_name)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product_name
  dependency.package = package
  target.package_product_dependencies << dependency

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

def add_swift_tree(project, target, root_dir, group_name)
  group = project.new_group(group_name, root_dir)
  Dir.glob(File.join(root_dir, '**', '*.swift')).sort.each do |path|
    rel = Pathname.new(path).relative_path_from(Pathname.new(root_dir)).to_s
    parent = group
    File.dirname(rel).split('/').each do |segment|
      next if segment == '.'
      parent = parent[segment] || parent.new_group(segment, segment)
    end
    ref = parent.new_reference(path)
    target.add_file_references([ref])
  end
  group
end

# ---------------------------------------------------------------------------
# File Provider
# ---------------------------------------------------------------------------
provider_target = project.new_target(:app_extension, 'iTerm2PadFileProvider', :ios, DEPLOYMENT_TARGET)
provider_group = add_swift_tree(project, provider_target, PROVIDER_DIR, 'iTerm2PadFileProvider')
provider_group.new_reference(File.join(PROVIDER_DIR, 'Info.plist'))
link_package_product(project, provider_target, shell_pkg, 'LocalShell')

provider_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['CODE_SIGN_ENTITLEMENTS'] = 'iTerm2PadFileProvider/iTerm2PadFileProvider.entitlements'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['MARKETING_VERSION'] = MARKETING_VERSION
  settings['CURRENT_PROJECT_VERSION'] = CURRENT_PROJECT_VERSION
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'iTerm2PadFileProvider/Info.plist'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.sshfs"
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SDKROOT'] = 'iphoneos'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '2'
  settings['SUPPORTS_MACCATALYST'] = 'NO'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
target = project.new_target(:application, 'iTerm2Pad', :ios, DEPLOYMENT_TARGET)
app_group = add_swift_tree(project, target, APP_DIR, 'iTerm2Pad')

include_assets = ENV['SKIP_ASSETS'].nil?
if include_assets
  assets = File.join(APP_DIR, 'Resources', 'Assets.xcassets')
  assets_ref = app_group.new_reference(assets)
  target.add_resources([assets_ref])
end
privacy = File.join(APP_DIR, 'Resources', 'PrivacyInfo.xcprivacy')
target.add_resources([app_group.new_reference(privacy)])
commands = File.join(APP_DIR, 'Resources', 'commandDictionary.plist')
if File.exist?(commands)
  target.add_resources([app_group.new_reference(commands)])
end
tmux_dir = File.join(APP_DIR, 'Resources', 'tmux')
if Dir.exist?(tmux_dir)
  tmux_group = app_group.new_group('tmux', tmux_dir)
  Dir.glob(File.join(tmux_dir, '*')).sort.each do |path|
    target.add_resources([tmux_group.new_reference(path)])
  end
end

link_package_product(project, target, tmux_pkg, 'TmuxControl')
link_package_product(project, target, ssh_pkg, 'SSHClient')
link_package_product(project, target, shell_pkg, 'LocalShell')
link_package_product(project, target, swiftterm_pkg, 'SwiftTerm')

target.add_dependency(provider_target)
embed_phase = target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.dst_path = ''
embed_build_file = embed_phase.add_file_reference(provider_target.product_reference, true)
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['MARKETING_VERSION'] = MARKETING_VERSION
  settings['CURRENT_PROJECT_VERSION'] = CURRENT_PROJECT_VERSION
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '2'
  settings['SUPPORTS_MACCATALYST'] = 'NO'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'iTerm2Pad/Resources/Info.plist'
  settings['SDKROOT'] = 'iphoneos'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' if include_assets
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor' if include_assets
  settings['ENABLE_PREVIEWS'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['CODE_SIGN_ENTITLEMENTS'] = 'iTerm2Pad/Resources/iTerm2Pad.entitlements'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['VALIDATE_PRODUCT'] = 'YES' if config.name != 'Debug'
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
tests_target = project.new_target(:unit_test_bundle, 'iTerm2PadTests', :ios, DEPLOYMENT_TARGET)
add_swift_tree(project, tests_target, TESTS_DIR, 'iTerm2PadTests')
tests_target.add_dependency(target)
link_package_product(project, tests_target, tmux_pkg, 'TmuxControl')
link_package_product(project, tests_target, ssh_pkg, 'SSHClient')

tests_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/iTerm2Pad.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/iTerm2Pad'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.tests"
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SDKROOT'] = 'iphoneos'
  settings['SWIFT_VERSION'] = '5.0'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['TARGETED_DEVICE_FAMILY'] = '2'
end

# ---------------------------------------------------------------------------
# UI tests
# ---------------------------------------------------------------------------
ui_tests_target = project.new_target(:ui_test_bundle, 'iTerm2PadUITests', :ios, DEPLOYMENT_TARGET)
add_swift_tree(project, ui_tests_target, UI_TESTS_DIR, 'iTerm2PadUITests')
ui_tests_target.add_dependency(target)

ui_tests_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.uitests"
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SDKROOT'] = 'iphoneos'
  settings['SWIFT_VERSION'] = '5.0'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['TARGETED_DEVICE_FAMILY'] = '2'
  settings['TEST_TARGET_NAME'] = 'iTerm2Pad'
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.add_test_target(tests_target)
scheme.add_test_target(ui_tests_target)
scheme.save_as(PROJECT_PATH, 'iTerm2Pad', true)

puts "Wrote #{PROJECT_PATH}"
puts "Targets: iTerm2Pad, iTerm2PadFileProvider, iTerm2PadTests, iTerm2PadUITests"
