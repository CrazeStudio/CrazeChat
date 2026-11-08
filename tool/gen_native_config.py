#!/usr/bin/env python3
"""Write android/app/src/main/cpp/config.h for the libcrazecfg.so native library.

The API origin and shared key are XOR-masked with a random per-build mask so
they never appear as plain strings in the APK. Reads CRAZECHAT_BURL and
CRAZECHAT_KEY from the environment and never prints them.
"""
import os
import secrets
import sys
from pathlib import Path

MASK_LEN = 16
KEY_OFFSET = 7


def fmt(data: bytes) -> str:
    return ", ".join(str(b) for b in data)


def encode(text: str, mask: bytes, offset: int) -> bytes:
    raw = text.encode("utf-8")
    masked = bytes(b ^ mask[(i + offset) % MASK_LEN] for i, b in enumerate(raw))
    return masked + b"\x00"


def main() -> None:
    url = os.environ.get("CRAZECHAT_BURL", "").strip()
    key = os.environ.get("CRAZECHAT_KEY", "").strip()
    if not url.startswith("https://") or not key:
        sys.exit("CRAZECHAT_BURL (https origin) and CRAZECHAT_KEY are required.")
    mask = secrets.token_bytes(MASK_LEN)
    url_enc = encode(url, mask, 0)
    key_enc = encode(key, mask, KEY_OFFSET)
    header = (
        "/* Generated at build time. Do not commit. */\n"
        f"#define CC_MASK_LEN {MASK_LEN}\n"
        f"#define CC_URL_LEN {len(url_enc) - 1}\n"
        f"#define CC_KEY_LEN {len(key_enc) - 1}\n"
        f"static const unsigned char cc_mask[CC_MASK_LEN] = {{{fmt(mask)}}};\n"
        f"static const unsigned char cc_url_enc[CC_URL_LEN + 1] = {{{fmt(url_enc)}}};\n"
        f"static const unsigned char cc_key_enc[CC_KEY_LEN + 1] = {{{fmt(key_enc)}}};\n"
    )
    target = Path("android/app/src/main/cpp/config.h")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(header)
    print("Native API config written (values not shown).")


if __name__ == "__main__":
    main()
