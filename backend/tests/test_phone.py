"""Phone allow-list — the single source of truth consumed by the server guard
(and mirrored by the client UI and the DB CHECK). Saudi-only at launch, but the
allow-list is data so GCC expansion is a config change, not a refactor."""
from app.phone import ALLOWED_PHONE_PREFIXES, normalize_phone, is_allowed_phone


def test_normalizes_local_zero_prefixed():
    assert normalize_phone("0512345678") == "+966512345678"


def test_normalizes_bare_national():
    assert normalize_phone("512345678") == "+966512345678"


def test_normalizes_already_e164():
    assert normalize_phone("+966512345678") == "+966512345678"


def test_normalizes_double_zero_international():
    assert normalize_phone("00966512345678") == "+966512345678"


def test_normalizes_966_without_plus():
    assert normalize_phone("966512345678") == "+966512345678"


def test_strips_spaces_and_dashes():
    assert normalize_phone(" 05 1234-5678 ") == "+966512345678"


def test_rejects_garbage():
    assert normalize_phone("abc") is None
    assert normalize_phone("") is None
    assert normalize_phone(None) is None


def test_saudi_number_is_allowed():
    assert is_allowed_phone("+966512345678") is True


def test_non_saudi_e164_is_not_allowed():
    # A valid US E.164 normalizes but must NOT be allowed at launch.
    assert normalize_phone("+15551234567") == "+15551234567"
    assert is_allowed_phone("+15551234567") is False


def test_saudi_landline_prefix_not_allowed_only_mobile():
    # +9661.. (landline) is not a mobile OTP target.
    assert is_allowed_phone("+966112345678") is False


def test_wrong_length_saudi_rejected_by_allow_check():
    # right prefix, wrong length must fail the full-format check.
    assert is_allowed_phone("+96651234") is False


def test_allow_list_is_data_not_hardcoded_condition():
    # Extensibility guard: prefixes live in one list.
    assert "+9665" in ALLOWED_PHONE_PREFIXES
