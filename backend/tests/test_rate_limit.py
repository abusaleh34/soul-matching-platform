"""Rate limiter for OTP-send abuse (brute-force + SMS cost). Pure, time-injected."""
from app.rate_limit import RateLimiter


def test_allows_up_to_limit_then_rejects():
    rl = RateLimiter(max_attempts=3, window_seconds=60)
    assert rl.allow("+966500000001", now=100.0) is True
    assert rl.allow("+966500000001", now=101.0) is True
    assert rl.allow("+966500000001", now=102.0) is True
    # 4th within the window is rejected
    assert rl.allow("+966500000001", now=103.0) is False


def test_window_slides():
    rl = RateLimiter(max_attempts=2, window_seconds=60)
    assert rl.allow("k", now=0.0) is True
    assert rl.allow("k", now=1.0) is True
    assert rl.allow("k", now=2.0) is False
    # once the first attempts age out of the window, allowed again
    assert rl.allow("k", now=61.0) is True


def test_keys_are_isolated():
    rl = RateLimiter(max_attempts=1, window_seconds=60)
    assert rl.allow("phone-A", now=0.0) is True
    assert rl.allow("phone-A", now=1.0) is False
    # a different key (e.g. a different phone or IP) is unaffected
    assert rl.allow("phone-B", now=1.0) is True
