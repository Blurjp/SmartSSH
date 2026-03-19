platform :ios, '17.0'
use_frameworks!

target 'SmartSSH' do
  pod 'NMSSH-riden', '~> 2.7.2'
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

  # Patch NMSSHSession.m to set KEX algorithm preferences before handshake.
  # Modern OpenSSH servers disable legacy DH algorithms; we must explicitly
  # advertise what this libssh2 build supports.
  ['NMSSH-riden', 'NMSSH'].each do |pod_name|
    nmssh_session = File.join(installer.sandbox.pod_dir(pod_name), 'NMSSH', 'NMSSHSession.m')
    next unless File.exist?(nmssh_session)
    content = File.read(nmssh_session)
    kex_patch = <<~'PATCH'
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_KEX,
            "ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,"
            "diffie-hellman-group14-sha256,"
            "diffie-hellman-group14-sha1,"
            "diffie-hellman-group-exchange-sha256,"
            "diffie-hellman-group-exchange-sha1,"
            "diffie-hellman-group1-sha1");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_HOSTKEY,
            "ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,"
            "ssh-rsa,rsa-sha2-256,rsa-sha2-512,ssh-dss");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_CRYPT_CS,
            "aes128-ctr,aes192-ctr,aes256-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_CRYPT_SC,
            "aes128-ctr,aes192-ctr,aes256-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_MAC_CS,
            "hmac-sha2-256,hmac-sha2-512,hmac-sha1,hmac-md5");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_MAC_SC,
            "hmac-sha2-256,hmac-sha2-512,hmac-sha1,hmac-md5");

    PATCH
    anchor = '    // Set the custom banner'
    unless content.include?('LIBSSH2_METHOD_KEX')
      patched = content.sub(anchor, kex_patch + anchor)
      File.write(nmssh_session, patched)
      puts "✅ Patched #{pod_name}/NMSSHSession.m with KEX algorithm preferences"
    else
      puts "ℹ️  #{pod_name}/NMSSHSession.m already patched"
    end
    break
  end
end
