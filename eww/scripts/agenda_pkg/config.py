"""Calendar accounts from the island's private config file."""

from dataclasses import dataclass
import os
from pathlib import Path
import re
import stat

COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")


@dataclass(frozen=True)
class Account:
    name: str
    color: str
    email: str
    url: str


def config_path(env=None):
    env = os.environ if env is None else env
    if env.get("ISLAND_CALENDARS"):
        return Path(env["ISLAND_CALENDARS"])
    base = Path(env.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "openbox-island" / "calendars"


def parse(text):
    """Accounts and per-line errors from `NAME | #RRGGBB | EMAIL | https://URL` lines."""
    accounts, errors = [], []
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split("|")]
        if (len(fields) != 4 or not fields[0] or not COLOR.match(fields[1])
                or not re.fullmatch(r"https://\S+", fields[3])):
            errors.append(f"baris {number} config kalender tidak valid")
            continue
        accounts.append(Account(fields[0], fields[1], fields[2].lower(), fields[3]))
    return accounts, errors


def load(path):
    """(accounts, errors, loose); loose = group or others may access the file."""
    try:
        text = path.read_text(encoding="utf-8")
        mode = path.stat().st_mode
    except FileNotFoundError:
        return [], [], False
    except (OSError, UnicodeDecodeError):
        return [], ["config kalender tidak bisa dibaca"], False
    accounts, errors = parse(text)
    return accounts, errors, bool(mode & (stat.S_IRWXG | stat.S_IRWXO))
