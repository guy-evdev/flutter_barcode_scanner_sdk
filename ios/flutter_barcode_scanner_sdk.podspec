Pod::Spec.new do |s|
  s.name             = 'flutter_barcode_scanner_sdk'
  s.version          = '0.2.1'
  s.summary          = 'High-throughput barcode and QR scanner SDK for Flutter apps.'
  s.description      = <<-DESC
A native barcode and QR scanner plugin for Flutter applications with full-screen
and embedded scanning modes.
  DESC
  s.homepage         = 'https://github.com/guy-evdev/flutter_barcode_scanner_sdk'
  s.license          = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author           = { 'Eventer' => 'https://github.com/guy-evdev' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_barcode_scanner_sdk/Sources/flutter_barcode_scanner_sdk/**/*.{swift}'
  s.resources        = ['flutter_barcode_scanner_sdk/Sources/flutter_barcode_scanner_sdk/PrivacyInfo.xcprivacy']
  s.dependency       'Flutter'
  s.frameworks       = 'AVFoundation', 'UIKit'
  s.platform         = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.swift_version = '5.9'
end
