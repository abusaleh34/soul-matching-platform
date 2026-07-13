"""Phone number normalization and the country allow-list.

Single source of truth for the Saudi-only launch constraint. The allow-list is
DATA (a list of prefixes + per-prefix format), so extending to other GCC
countries is a config change here — never a Saudi condition scattered across the
codebase. The server guard (SMS hook) and the DB CHECK both derive from this;
the Flutter client mirrors the same rules.
"""
import re

# Extend this list to expand coverage (e.g. add '+9715' for UAE mobiles).
# Each entry: (E.164 prefix, full-format regex for that prefix).
_ALLOW: tuple[tuple[str, "re.Pattern[str]"], ...] = (
    ("+9665", re.compile(r"^\+9665\d{8}$")),  # Saudi mobile: +966 5X XXX XXXX
)

ALLOWED_PHONE_PREFIXES: tuple[str, ...] = tuple(p for p, _ in _ALLOW)


def normalize_phone(raw: str | None) -> str | None:
    """Best-effort E.164 normalization.

    Local Saudi forms (``05XXXXXXXX``, ``5XXXXXXXX``) are interpreted as +966.
    Returns None when the input cannot form a plausible E.164 number. Allow-list
    enforcement is separate — see :func:`is_allowed_phone`.
    """
    if not raw:
        return None
    s = re.sub(r"[^\d+]", "", raw)
    if not s:
        return None

    if s.startswith("00"):
        e164 = "+" + s[2:]
    elif s.startswith("+"):
        e164 = s
    elif s.startswith("966"):
        e164 = "+" + s
    elif s.startswith("0"):
        # local trunk form, e.g. 05XXXXXXXX -> national 5XXXXXXXX under +966
        e164 = "+966" + s[1:]
    elif s.startswith("5") and len(s) == 9:
        # bare Saudi national mobile
        e164 = "+966" + s
    else:
        e164 = "+" + s

    if not re.fullmatch(r"\+\d{8,15}", e164):
        return None
    return e164


def is_allowed_phone(e164: str | None) -> bool:
    """True only for numbers on the allow-list AND matching that country's
    full format (prefix alone is not enough — a wrong-length +9665 fails)."""
    if not e164:
        return False
    return any(e164.startswith(prefix) and rx.match(e164) for prefix, rx in _ALLOW)
