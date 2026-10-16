"""Release requirements must remain active under optimized Python."""
import re


def require(condition, message="Release verification failed"):
    if not condition:
        raise ValueError(message)


def verify_signature_policy(details, entitlements, *, main):
    require(re.search(r"^Authority=Developer ID Application: .+", details, re.M), "Developer ID Application certificate required")
    require("TeamIdentifier=66LBY954DT" in details, "Unexpected signing team")
    require(re.search(r"^Timestamp=.+", details, re.M), "Secure timestamp required")
    if main:
        require(re.search(r"^CodeDirectory .*flags=0x[0-9a-fA-F]+\([^)]*\bruntime\b[^)]*\)", details, re.M), "Hardened runtime disabled")
    for key in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"]:
        require(not entitlements.get(key), f"Unexpected release entitlement: {key}")
