"""SMS provider interface and the built-in implementations."""
from __future__ import annotations

import abc
import logging
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DeliveryResult:
    success: bool
    provider: str
    detail: str | None = None


class SmsProvider(abc.ABC):
    """One method: deliver a message to an E.164 number."""

    name: str = "abstract"

    @abc.abstractmethod
    def send(self, to_e164: str, message: str) -> DeliveryResult:
        raise NotImplementedError


class LoggingSmsProvider(SmsProvider):
    """Dev/CI/soft-launch: logs the message (incl. the OTP) and sends nothing.
    Used to drive the live journey before a real provider is wired."""

    name = "logging"

    def send(self, to_e164: str, message: str) -> DeliveryResult:
        logger.info("SMS[logging] to=%s message=%s", to_e164, message)
        return DeliveryResult(success=True, provider=self.name, detail="logged")


class NullSmsProvider(SmsProvider):
    """Fails loud. The default when nothing is configured, so a misconfigured
    prod cannot silently drop OTPs."""

    name = "null"

    def send(self, to_e164: str, message: str) -> DeliveryResult:
        raise RuntimeError(
            "No SMS provider configured (SMS_PROVIDER unset). Refusing to send. "
            "Set SMS_PROVIDER=logging for soft launch, or wire a real provider."
        )


class SaudiSmsProvider(SmsProvider):
    """STUB for the eventual Saudi provider (Taqnyat / Unifonic / …).

    Wiring is intentionally the ONLY thing left: fill in the HTTP call below per
    the provider's API docs, then set SMS_PROVIDER=saudi + credentials. See
    docs/SMS_PROVIDER_INTEGRATION.md. Until then it fails loud rather than faking
    delivery.
    """

    name = "saudi"

    def __init__(self, api_key: str | None, sender_id: str | None):
        self.api_key = api_key
        self.sender_id = sender_id

    def send(self, to_e164: str, message: str) -> DeliveryResult:
        # TODO(provider): replace with the chosen provider's send call, e.g.:
        #   POST {PROVIDER_BASE_URL}/api/v1/messages
        #   Headers: {"Authorization": f"Bearer {self.api_key}"}
        #   JSON body: {"recipient": to_e164, "sender": self.sender_id, "body": message}
        #   -> parse provider message-id; map HTTP/status to DeliveryResult.
        # TODO(provider): register a delivery-report webhook and reconcile status.
        raise NotImplementedError(
            "SaudiSmsProvider is a documented stub — wire the chosen provider "
            "(see docs/SMS_PROVIDER_INTEGRATION.md) before enabling SMS_PROVIDER=saudi."
        )
