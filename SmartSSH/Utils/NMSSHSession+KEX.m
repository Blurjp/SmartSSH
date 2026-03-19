//
//  NMSSHSession+KEX.m
//  SmartSSH
//
//  Sets libssh2 KEX preferences so we can connect to modern OpenSSH servers.
//  libssh2 in the bundled NMSSH only supports legacy DH algorithms; modern
//  OpenSSH servers prefer curve25519/ecdh which are not compiled into this
//  libssh2. By explicitly setting method preferences we ensure libssh2
//  advertises what it actually supports rather than letting the negotiation
//  silently fail.
//

#import "NMSSHSession+KEX.h"
#import <NMSSH/NMSSH.h>

@implementation NMSSHSession (KEX)

- (void)applyBroadKEXPreferences {
    LIBSSH2_SESSION *raw = [self rawSession];
    if (!raw) return;

    // Key exchange: prefer group14 (stronger DH) then group1, then GEX variants
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_KEX,
        "diffie-hellman-group14-sha256,"
        "diffie-hellman-group14-sha1,"
        "diffie-hellman-group-exchange-sha256,"
        "diffie-hellman-group-exchange-sha1,"
        "diffie-hellman-group1-sha1");

    // Host key: accept both RSA variants
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_HOSTKEY,
        "ssh-rsa,rsa-sha2-256,rsa-sha2-512,ssh-dss");

    // Ciphers client->server
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_CRYPT_CS,
        "aes128-ctr,aes256-ctr,aes192-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc");

    // Ciphers server->client
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_CRYPT_SC,
        "aes128-ctr,aes256-ctr,aes192-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc");

    // MACs
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_MAC_CS,
        "hmac-sha2-256,hmac-sha2-512,hmac-sha1,hmac-md5");
    libssh2_session_method_pref(raw, LIBSSH2_METHOD_MAC_SC,
        "hmac-sha2-256,hmac-sha2-512,hmac-sha1,hmac-md5");
}

@end
