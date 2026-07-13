"""Provider-agnostic SMS delivery.

Supabase calls the app's Send SMS Hook to deliver an OTP; the hook dispatches
through an :class:`SmsProvider`. The concrete Saudi provider is not chosen yet
(pending CST Sender-ID registration), so wiring it must be ONE class + env vars
and touch nothing else. See docs/SMS_PROVIDER_INTEGRATION.md.
"""
from .provider import (
    DeliveryResult,
    LoggingSmsProvider,
    NullSmsProvider,
    SaudiSmsProvider,
    SmsProvider,
)
from .factory import get_sms_provider

__all__ = [
    "DeliveryResult",
    "SmsProvider",
    "LoggingSmsProvider",
    "NullSmsProvider",
    "SaudiSmsProvider",
    "get_sms_provider",
]
