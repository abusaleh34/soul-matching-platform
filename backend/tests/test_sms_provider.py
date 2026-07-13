"""Provider-agnostic SMS layer. The real Saudi provider (Taqnyat/Unifonic/…)
is not chosen yet, so this must be swappable via one class + env vars."""
import logging

import pytest

from app.sms import (
    DeliveryResult,
    LoggingSmsProvider,
    NullSmsProvider,
    SaudiSmsProvider,
    get_sms_provider,
)


def test_logging_provider_succeeds_and_logs_without_sending(caplog):
    p = LoggingSmsProvider()
    with caplog.at_level(logging.INFO):
        result = p.send("+966512345678", "رمزك هو 123456")
    assert isinstance(result, DeliveryResult)
    assert result.success is True
    assert result.provider == "logging"
    # the OTP message is visible in logs (how the soft-launch reads the code)
    assert any("123456" in r.message for r in caplog.records)


def test_null_provider_fails_loud():
    # No silent no-op: an unconfigured prod must fail loudly, not swallow.
    with pytest.raises(RuntimeError):
        NullSmsProvider().send("+966512345678", "x")


def test_saudi_provider_is_a_documented_stub():
    # Not wired until a provider + Sender ID exist; must fail loud, not fake success.
    with pytest.raises(NotImplementedError):
        SaudiSmsProvider(api_key="k", sender_id="SOULM").send("+966512345678", "x")


def test_factory_selects_by_env(monkeypatch):
    monkeypatch.setenv("SMS_PROVIDER", "logging")
    assert isinstance(get_sms_provider(), LoggingSmsProvider)

    monkeypatch.setenv("SMS_PROVIDER", "saudi")
    monkeypatch.setenv("SMS_API_KEY", "k")
    monkeypatch.setenv("SMS_SENDER_ID", "SOULM")
    assert isinstance(get_sms_provider(), SaudiSmsProvider)


def test_factory_defaults_to_null_when_unset(monkeypatch):
    monkeypatch.delenv("SMS_PROVIDER", raising=False)
    assert isinstance(get_sms_provider(), NullSmsProvider)
