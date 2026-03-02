# Third-Party Notices

This project uses or integrates third-party components. When redistributing binaries or source code, you must review and comply with their respective licenses in addition to this project's MIT License.

## libssh

- Project: libssh
- Site: https://www.libssh.org/
- Use in this project: SSH/SFTP library used by `term_core`
- License: LGPL (libssh describes it as LGPL in its official documentation)
- Distribution Note: The libssh project itself warns that static linking with LGPL code requires carefully reviewing the applicable obligations before redistributing binaries.

## OpenSSL

- Project: OpenSSL
- Site: https://www.openssl.org/
- Use in this project: Cryptographic primitives required by the SSH integration
- License: Apache License 2.0 for OpenSSL 3.x

## SwiftTerm

- Project: SwiftTerm
- Site: https://github.com/migueldeicaza/SwiftTerm
- Use in this project: Local terminal emulator and VT100/Xterm rendering for SSH.
- License: MIT License

## Official Sources

- libssh licensing overview: https://www.libssh.org/features/
- libssh static linking note: https://api.libssh.org/stable/libssh_linking.html
- OpenSSL license: https://www.openssl.org/source/license.html
- SwiftTerm license: https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE

## Practical Recommendations

- Include this file along with `LICENSE` when redistributing the project or its binaries.
- Preserve all third-party copyright and license notices.
- If you plan to distribute statically linked binaries, validate the exact LGPL obligations for your distribution method beforehand.
