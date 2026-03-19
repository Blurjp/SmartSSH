platform :ios, '17.0'
use_frameworks!

def shared_pods
  pod 'NMSSH', '~> 2.3'
end

target 'SmartSSH' do
  pod 'SwiftNIO', '~> 2.65'
  pod 'SwiftNIOSSH', '~> 0.13.0'
  pod 'NIOSSH', '~> 0.13.0'
end

target 'SmartSSHTests' do
  shared_pods
end

target 'SmartSSHUITests' do
  shared_pods
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
      end
    end
    target.user_project.save
  end
end
