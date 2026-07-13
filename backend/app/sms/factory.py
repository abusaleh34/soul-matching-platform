"""Select the SMS provider from environment configuration.

    SMS_PROVIDER   logging | saudi | null   (default: null — fail loud)
    SMS_API_KEY    provider credential (saudi)
    SMS_SENDER_ID  registered CST sender id (saudi)
"""
import os

from .provider import (
    LoggingSmsProvider,
    NullSmsProvider,
    SaudiSmsProvider,
    SmsProvider,
)


def get_sms_provider() -> SmsProvider:
    choice = (os.getenv("SMS_PROVIDER") or "null").strip().lower()
    if choice == "logging":
        return LoggingSmsProvider()
    if choice == "saudi":
        return SaudiSmsProvider(
            api_key=os.getenv("SMS_API_KEY"),
            sender_id=os.getenv("SMS_SENDER_ID"),
        )
    return NullSmsProvider()
