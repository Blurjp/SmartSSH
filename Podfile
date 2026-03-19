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

  # Patch NMSSH to advertise only the KEX algorithms compiled into libssh2 v1.8.
  # Modern OpenSSH servers disable legacy DH algorithms by default; without this
  # patch the SSH handshake fails with "Failure establishing SSH session".
  nmssh_session = File.join(installer.sandbox.pod_dir('NMSSH'), 'NMSSH', 'NMSSHSession.m')
  if File.exist?(nmssh_session)
    content = File.read(nmssh_session)
    kex_patch = <<~'PATCH'
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_KEX,
            "diffie-hellman-group14-sha256,"
            "diffie-hellman-group14-sha1,"
            "diffie-hellman-group-exchange-sha256,"
            "diffie-hellman-group-exchange-sha1,"
            "diffie-hellman-group1-sha1");
        libssh2_session_method_pref(self.session, LIBSSH2_METHOD_HOSTKEY,
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
      puts "✅ Patched NMSSHSession.m with KEX algorithm preferences"
    else
      puts "ℹ️  NMSSHSession.m already patched"
    end
  end
end
