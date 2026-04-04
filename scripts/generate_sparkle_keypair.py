#!/usr/bin/env python3
"""Print a Sparkle Ed25519 keypair for SUPublicEDKey (app) and SPARKLE_EDDSA_PRIVATE_KEY (CI).

Requires: pip install cryptography
"""
from __future__ import annotations

import base64

try:
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
except ImportError:
    raise SystemExit("Install cryptography: pip3 install cryptography") from None


def main() -> None:
    pk = ed25519.Ed25519PrivateKey.generate()
    seed = pk.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub = pk.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    pub_b64 = base64.b64encode(pub).decode()
    priv_b64 = base64.b64encode(seed).decode()
    print("Set in Xcode build settings (both Debug & Release):")
    print(f"  INFOPLIST_KEY_SUPublicEDKey = {pub_b64}")
    print()
    print("Add as GitHub Actions secret SPARKLE_EDDSA_PRIVATE_KEY:")
    print(f"  {priv_b64}")


if __name__ == "__main__":
    main()
