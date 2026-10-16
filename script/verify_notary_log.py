#!/usr/bin/env python3
import json
from pathlib import Path
import sys
from release_checks import require

data = json.loads(Path(sys.argv[1]).read_text())
require(data.get("status") == "Accepted", "Notarization was not accepted")
require(not data.get("issues"), "Notary log contains warnings or errors")
print("Apple accepted the submission with no reported issues.")
