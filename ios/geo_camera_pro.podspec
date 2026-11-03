#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint geo_camera_pro.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'geo_camera_pro'
  s.version          = '0.0.1'
  s.summary          = 'Camera capture with background GPS tracking for Flutter.'
  s.description      = <<-DESC
Portrait-normalized photo capture with native Android and iOS background location tracking.
                       DESC
  s.homepage         = 'https://github.com/Kanojiya987/Can-Image-New-App'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'geo_camera_pro/Sources/geo_camera_pro/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'geo_camera_pro_privacy' => ['geo_camera_pro/Sources/geo_camera_pro/PrivacyInfo.xcprivacy']}
end
