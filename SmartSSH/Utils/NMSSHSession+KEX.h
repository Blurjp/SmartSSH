//
//  NMSSHSession+KEX.h
//  SmartSSH
//
//  Sets libssh2 key exchange method preferences to include legacy
//  Diffie-Hellman algorithms so we can connect to modern OpenSSH servers
//  that have disabled curve25519/ecdh (which this libssh2 doesn't support).
//

#import <NMSSH/NMSSHSession.h>

NS_ASSUME_NONNULL_BEGIN

@interface NMSSHSession (KEX)

/// Call this immediately after creating the session, before calling -connect.
/// Sets the KEX, hostkey, cipher, and MAC preferences to the full set of
/// algorithms supported by the bundled libssh2, broadest-first.
- (void)applyBroadKEXPreferences;

@end

NS_ASSUME_NONNULL_END
