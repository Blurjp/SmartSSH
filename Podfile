platform :ios, '17.0'
use_frameworks!

target 'SmartSSH' do
  pod 'NMSSH', '~> 2.3'
end

target 'SmartSSHTests' do
  inherit! :search_paths
end

target 'SmartSSHUITests' do
  inherit! :search_paths
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end

  installer.aggregate_targets.each do |target|
    target.user_project.native_targets.each do |native_target|
      native_target.build_configurations.each do |config|
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    target.user_project.save
  end
end
