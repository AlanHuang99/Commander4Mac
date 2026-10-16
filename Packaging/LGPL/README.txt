Commander4Mac open-source components

This product includes software developed by Niels Provos.

AMSMB2 and libsmb2 are provided under GNU LGPL version 2.1 or later.
See ThirdPartyNotices.txt and the original license files in the source kit.
The accompanying LGPL-Sources.tar.gz contains their complete pinned source,
including the libsmb2 submodule, original build files and notices, and the
two Swift package build dependencies. SourceManifest.json records every
file hash; Dependencies.json records source URLs and exact revisions.

Commander4Mac permits modification for your own use and reverse engineering
to debug modifications to these LGPL libraries. You may replace the linked
AMSMB2 framework with an interface-compatible modified version. These
permissions do not restrict any rights under the third-party licenses and
do not apply a new license to unrelated Commander4Mac source code.

Rebuild on macOS with Xcode's command line tools and Python 3:
  tar -xzf LGPL-Sources.tar.gz
  cd LGPL-Sources
  ./rebuild_smb.sh /absolute/path/to/fresh-build arm64
Use x86_64 for an Intel-only copy. To create a universal replacement, build
each architecture into separate fresh directories and combine the two
AMSMB2 binaries with /usr/bin/lipo -create -output /path/to/AMSMB2 ... .
The rebuild uses local package paths and needs no remote package checkout.
Modify the extracted library sources before running the rebuild script.

Replacement for your own use:
  1. Quit the personal copy you intend to modify.
  2. Copy Commander4Mac.app to a separate writable folder outside Applications.
  3. Run ./replace_smb.sh /path/to/personal-copy.app /path/to/rebuilt/AMSMB2
  4. Open your modified copy. Personal changes invalidate the original
     Developer ID signature and notarization. The script ad-hoc signs only
     your modified copy; it does not change the original distributed app,
     system settings, Gatekeeper configuration or privacy databases.

The supplied distribution retains hardened runtime and library validation.
Personal re-signing changes the copy's signing identity. Full Disk Access
or Local Network access previously granted to the official app is not
promised for modified copies; macOS may require fresh user setup.

For advertising mentioning features or use of the included Blowfish code,
retain this acknowledgement: This product includes software developed by
Niels Provos. Do not use authors' names to endorse derived products.
