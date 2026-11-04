"""consent.py: usage agreement and consent file (spec 04, Nutzungsvertrag und Zustimmung)."""
import datetime
import getpass
import hashlib
import json
import os
from pathlib import Path


def legal_version(base: Path) -> str:
    return (base / "legal" / "VERSION").read_text(encoding="utf-8").strip()


def is_draft(version: str) -> bool:
    return version.startswith("0.")


def agreement_file(base: Path, lang: str) -> Path:
    return base / "legal" / f"nutzungsvertrag.{lang}.md"


def agreement_text(base: Path, lang: str) -> str:
    return agreement_file(base, lang).read_text(encoding="utf-8")


def consent_path(home: Path, version: str) -> Path:
    return home / ".aios" / "consent" / f"nutzungsvertrag-{version}.json"


def has_consent(home: Path, version: str) -> bool:
    return consent_path(home, version).is_file()


def write_consent(home: Path, base: Path, version: str, lang: str, way: str,
                  installer: str, distribution: str) -> Path:
    """Record that a human accepted the agreement (IN1, IN2); folder 700, file 600."""
    data = agreement_file(base, lang).read_bytes()
    record = {
        "agreement": "nutzungsvertrag",
        "version": version,
        "draft": is_draft(version),
        "language": lang,
        "sha256": hashlib.sha256(data).hexdigest(),
        "accepted_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "user": getpass.getuser(),
        "way": way,
        "installer": installer,
        "distribution": distribution,
    }
    folder = home / ".aios" / "consent"
    folder.mkdir(parents=True, exist_ok=True)
    os.chmod(folder, 0o700)
    path = consent_path(home, version)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return path
