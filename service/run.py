#!/usr/bin/env python3
"""Run the loopback dev service with a private, persistent local owner credential."""
import os
from pathlib import Path
import secrets
import stat

from app import main


def local_owner_token(directory):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / "owner-token.txt"
    flags = os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            token = secrets.token_urlsafe(48)
            handle.write(token + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        return token
    except FileExistsError:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor) as handle:
            metadata = os.fstat(handle.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o077:
                raise ValueError("The local owner credential must be a private regular file (mode 600).")
            token = handle.read(513).strip()
        if not 32 <= len(token) <= 512:
            raise ValueError("The local owner credential is invalid. Configure RECALL_SERVICE_TOKEN or replace the local dev credential.")
        return token


if __name__ == "__main__":
    if not os.environ.get("RECALL_SERVICE_TOKEN"):
        try:
            os.environ["RECALL_SERVICE_TOKEN"] = local_owner_token(Path(__file__).parent / "local-data")
        except (OSError, ValueError) as problem:
            raise SystemExit("Could not load the private local owner credential. Check service/local-data permissions.") from None
    main()
