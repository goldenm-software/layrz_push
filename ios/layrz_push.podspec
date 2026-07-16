#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint layrz_push.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'layrz_push'
  s.version          = '0.0.1'
  s.summary          = 'Multi-tenant push notifications for Layrz powered apps'
  s.description      = <<-DESC
Wraps Firebase Cloud Messaging with runtime credential injection for multi-tenant support.
No GoogleService-Info.plist required — FirebaseOptions are built at runtime.
                       DESC
  s.homepage         = 'https://github.com/goldenm-software/layrz_push'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Golden M, Inc.' => 'software@goldenm.com' }
  s.source           = { :path => '.' }
  s.source_files = 'layrz_push/Sources/layrz_push/**/*'
  s.dependency 'Flutter'
  s.dependency 'Firebase/Messaging', '~> 12.0'
  s.platform = :ios, '15.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'layrz_push_privacy' => ['layrz_push/Sources/layrz_push/PrivacyInfo.xcprivacy']}
end
