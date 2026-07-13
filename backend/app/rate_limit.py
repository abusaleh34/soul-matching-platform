"""In-memory sliding-window rate limiter.

Bounds OTP-send abuse (brute force + SMS cost) per key (phone or IP). Process-
local — adequate for a single Render instance at soft-launch scale; swap for a
shared store (Redis/Postgres) when horizontally scaled (noted in the report).
"""
from collections import defaultdict, deque


class RateLimiter:
    def __init__(self, max_attempts: int, window_seconds: float):
        self._max = max_attempts
        self._win = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str, now: float) -> bool:
        """Record and allow the attempt, or reject if the key is over its limit
        within the sliding window."""
        q = self._hits[key]
        cutoff = now - self._win
        while q and q[0] <= cutoff:
            q.popleft()
        if len(q) >= self._max:
            return False
        q.append(now)
        return True
