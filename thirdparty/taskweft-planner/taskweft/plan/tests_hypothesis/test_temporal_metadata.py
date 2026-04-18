#!/usr/bin/env python
"""
Property-based tests for TemporalMetadata class using Hypothesis.
Tests temporal metadata creation, manipulation, and serialization.
"""

from datetime import datetime, timedelta, timezone

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, assume, given, settings

from ipyhop.temporal.utils import (
    format_iso8601_datetime,
    format_iso8601_duration,
    parse_iso8601_datetime,
    parse_iso8601_duration,
)
from ipyhop.temporal_metadata import TemporalMetadata

# ============================================================================
# Strategies
# ============================================================================


@st.composite
def iso8601_duration_strings(draw):
    """Generate valid ISO 8601 duration strings."""
    hours = draw(st.integers(0, 23))
    minutes = draw(st.integers(0, 59))
    seconds = draw(st.integers(0, 59))

    parts = []
    if hours > 0:
        parts.append(f"{hours}H")
    if minutes > 0:
        parts.append(f"{minutes}M")
    if seconds > 0 or not parts:
        parts.append(f"{seconds}S")

    return "PT" + "".join(parts)


@st.composite
def valid_durations(draw):
    """Generate valid ISO 8601 duration strings."""
    return draw(iso8601_duration_strings())


@st.composite
def iso8601_datetime_strings(draw):
    """Generate valid ISO 8601 datetime strings with Z suffix (tz-aware)."""
    year = draw(st.integers(2000, 2100))
    month = draw(st.integers(1, 12))
    day = draw(st.integers(1, 28))
    hour = draw(st.integers(0, 23))
    minute = draw(st.integers(0, 59))
    second = draw(st.integers(0, 59))
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"


@st.composite
def aware_datetimes(draw):
    """Generate tz-aware datetime objects."""
    dt = draw(
        st.datetimes(
            min_value=datetime(2000, 1, 1),
            max_value=datetime(2100, 12, 31),
        )
    )
    return dt.replace(tzinfo=timezone.utc)


@st.composite
def valid_datetimes(draw):
    """Generate valid datetime inputs (ISO string with Z or tz-aware datetime)."""
    if draw(st.booleans()):
        return draw(iso8601_datetime_strings())
    else:
        return draw(aware_datetimes())


def _to_aware(dt):
    """Ensure a datetime is timezone-aware (UTC)."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


# ============================================================================
# Constructor Tests
# ============================================================================


@given(valid_durations())
@settings(max_examples=100)
def test_constructor_with_duration(duration):
    """Constructor should accept ISO 8601 duration strings."""
    tm = TemporalMetadata(duration=duration)
    assert tm.duration is not None
    assert tm.duration == duration


@given(valid_datetimes())
@settings(max_examples=100)
def test_constructor_with_start_time(start_time):
    """Constructor should accept start_time as string or datetime."""
    tm = TemporalMetadata(start_time=start_time)
    assert tm.start_time is not None

    if isinstance(start_time, datetime):
        expected_str = format_iso8601_datetime(start_time)
        assert tm.start_time == expected_str
    else:
        assert tm.start_time == start_time


@given(valid_datetimes())
@settings(max_examples=100)
def test_constructor_with_end_time(end_time):
    """Constructor should accept end_time as string or datetime."""
    tm = TemporalMetadata(end_time=end_time)
    assert tm.end_time is not None

    if isinstance(end_time, datetime):
        expected_str = format_iso8601_datetime(end_time)
        assert tm.end_time == expected_str
    else:
        assert tm.end_time == end_time


@given(valid_durations(), valid_datetimes())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_constructor_with_duration_and_start(duration, start_time):
    """Constructor should handle duration and start_time together."""
    tm = TemporalMetadata(duration=duration, start_time=start_time)
    assert tm.duration is not None
    assert tm.start_time is not None
    assert tm.end_time is None  # Not auto-calculated


# ============================================================================
# Setter Tests
# ============================================================================


@given(valid_durations())
@settings(max_examples=100)
def test_set_duration(duration_input):
    """set_duration should accept ISO 8601 strings."""
    tm = TemporalMetadata()
    tm.set_duration(duration_input)
    assert tm.duration == duration_input


@given(st.floats(0.0, 86400.0, allow_infinity=False, allow_nan=False))
@settings(max_examples=50)
def test_set_duration_float_raises(seconds):
    """set_duration should reject float values with TypeError."""
    tm = TemporalMetadata()
    with pytest.raises(TypeError):
        tm.set_duration(seconds)


@given(st.integers(0, 86400))
@settings(max_examples=50)
def test_set_duration_int_raises(int_val):
    """set_duration should reject int values with TypeError."""
    tm = TemporalMetadata()
    with pytest.raises(TypeError):
        tm.set_duration(int_val)


@given(st.text(min_size=1, max_size=20))
@settings(max_examples=50)
def test_set_duration_invalid_string_raises(invalid_str):
    """set_duration should raise ValueError for invalid ISO 8601 strings."""
    assume(not invalid_str.startswith("PT"))
    tm = TemporalMetadata()
    with pytest.raises(ValueError):
        tm.set_duration(invalid_str)


@given(valid_datetimes())
@settings(max_examples=100)
def test_set_start_time(datetime_input):
    """set_start_time should accept string or datetime."""
    tm = TemporalMetadata()
    tm.set_start_time(datetime_input)
    assert tm.start_time is not None

    if isinstance(datetime_input, datetime):
        expected_str = format_iso8601_datetime(datetime_input)
        assert tm.start_time == expected_str


@given(valid_datetimes())
@settings(max_examples=100)
def test_set_end_time(datetime_input):
    """set_end_time should accept string or datetime."""
    tm = TemporalMetadata()
    tm.set_end_time(datetime_input)
    assert tm.end_time is not None


# ============================================================================
# Calculation Tests
# ============================================================================


@given(valid_durations(), iso8601_datetime_strings())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_calculate_end_from_duration(duration, start_time):
    """calculate_end_from_duration should compute correct end time."""
    tm = TemporalMetadata(duration=duration, start_time=start_time)
    success = tm.calculate_end_from_duration()

    assert success
    assert tm.end_time is not None

    # Verify correctness: parse everything to aware datetimes
    duration_sec = parse_iso8601_duration(duration)

    start_dt = parse_iso8601_datetime(start_time)
    expected_end = start_dt + timedelta(seconds=duration_sec)
    actual_end = parse_iso8601_datetime(tm.end_time)

    # Both should be aware (Z suffix strings parse to aware datetimes)
    assert abs((actual_end - expected_end).total_seconds()) < 0.01


@given(iso8601_datetime_strings(), iso8601_datetime_strings())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_calculate_duration(start_time, end_time):
    """calculate_duration should compute correct duration from start and end."""
    start_dt = parse_iso8601_datetime(start_time)
    end_dt = parse_iso8601_datetime(end_time)

    # Ensure end >= start
    if end_dt < start_dt:
        start_time, end_time = end_time, start_time
        start_dt, end_dt = end_dt, start_dt

    tm = TemporalMetadata(start_time=start_time, end_time=end_time)
    success = tm.calculate_duration()

    assert success
    assert tm.duration is not None

    expected_duration_sec = (end_dt - start_dt).total_seconds()
    actual_duration_sec = parse_iso8601_duration(tm.duration)

    assert abs(actual_duration_sec - expected_duration_sec) < 0.01


@given(valid_durations())
@settings(max_examples=50)
def test_calculate_end_without_start_fails(duration):
    """calculate_end_from_duration should fail without start time."""
    tm = TemporalMetadata(duration=duration)
    success = tm.calculate_end_from_duration()
    assert not success
    assert tm.end_time is None


@given(iso8601_datetime_strings())
@settings(max_examples=50)
def test_calculate_duration_without_end_fails(start_time):
    """calculate_duration should fail without end time."""
    tm = TemporalMetadata(start_time=start_time)
    success = tm.calculate_duration()
    assert not success
    assert tm.duration is None


# ============================================================================
# Property: Duration Consistency (roundtrip)
# ============================================================================


@given(valid_durations(), iso8601_datetime_strings())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_duration_end_time_consistency(duration, start_time):
    """
    Property: Calculating end from duration, then recalculating duration
    should return the original duration (within precision).
    """
    tm = TemporalMetadata(duration=duration, start_time=start_time)
    tm.calculate_end_from_duration()

    original_duration = tm.duration

    # Clear duration and recalculate from start/end
    tm._duration = None
    tm.calculate_duration()

    original_sec = parse_iso8601_duration(original_duration)
    recalculated_sec = parse_iso8601_duration(tm.duration)

    assert abs(original_sec - recalculated_sec) < 0.01


# ============================================================================
# Copy Tests
# ============================================================================


@given(valid_durations(), iso8601_datetime_strings(), iso8601_datetime_strings())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_copy_creates_independent_copy(duration, start_time, end_time):
    """copy() should create an independent copy."""
    tm1 = TemporalMetadata(duration=duration, start_time=start_time, end_time=end_time)
    tm2 = tm1.copy()

    assert tm1.duration == tm2.duration
    assert tm1.start_time == tm2.start_time
    assert tm1.end_time == tm2.end_time

    # Modifications should be independent
    new_dur = "PT99H" if duration != "PT99H" else "PT88H"
    tm2.set_duration(new_dur)
    assert tm1.duration != tm2.duration


# ============================================================================
# Serialization Tests
# ============================================================================


@given(valid_durations(), iso8601_datetime_strings(), iso8601_datetime_strings())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_to_dict_from_dict_roundtrip(duration, start_time, end_time):
    """to_dict() and from_dict() should preserve all data."""
    tm1 = TemporalMetadata(duration=duration, start_time=start_time, end_time=end_time)
    data = tm1.to_dict()
    tm2 = TemporalMetadata.from_dict(data)

    assert tm1.duration == tm2.duration
    assert tm1.start_time == tm2.start_time
    assert tm1.end_time == tm2.end_time


@given(valid_durations())
@settings(max_examples=50)
def test_to_dict_partial_data(duration):
    """to_dict() should handle partial data (only duration)."""
    tm = TemporalMetadata(duration=duration)
    data = tm.to_dict()

    assert "duration" in data
    assert data["duration"] == duration
    assert "start_time" not in data
    assert "end_time" not in data


def test_to_dict_empty():
    """to_dict() should return empty dict for empty TemporalMetadata."""
    tm = TemporalMetadata()
    data = tm.to_dict()
    assert data == {}


# ============================================================================
# duration_seconds() Tests
# ============================================================================


@given(iso8601_duration_strings())
@settings(max_examples=100)
def test_duration_seconds_returns_float(duration):
    """duration_seconds() should return the duration as float."""
    tm = TemporalMetadata(duration=duration)
    result = tm.duration_seconds()

    assert isinstance(result, float)
    expected = parse_iso8601_duration(duration)
    assert abs(result - expected) < 0.001


def test_duration_seconds_none():
    """duration_seconds() should return None if no duration set."""
    tm = TemporalMetadata()
    result = tm.duration_seconds()
    assert result is None


# ============================================================================
# set_start_now() and set_end_now() Tests
# ============================================================================


def test_set_start_now_sets_current_time():
    """set_start_now() should set start time to current time."""
    tm = TemporalMetadata()
    tm.set_start_now()

    assert tm.start_time is not None
    parsed = parse_iso8601_datetime(tm.start_time)
    now = datetime.now(timezone.utc)

    assert abs((_to_aware(parsed) - now).total_seconds()) < 60


def test_set_end_now_sets_current_time():
    """set_end_now() should set end time to current time."""
    tm = TemporalMetadata()
    tm.set_end_now()

    assert tm.end_time is not None
    parsed = parse_iso8601_datetime(tm.end_time)
    now = datetime.now(timezone.utc)

    assert abs((_to_aware(parsed) - now).total_seconds()) < 60


# ============================================================================
# String Representation Tests
# ============================================================================


@given(valid_durations(), iso8601_datetime_strings(), iso8601_datetime_strings())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_str_repr_includes_all_fields(duration, start_time, end_time):
    """__str__ and __repr__ should include all set fields."""
    tm = TemporalMetadata(duration=duration, start_time=start_time, end_time=end_time)
    str_repr = str(tm)
    repr_repr = repr(tm)

    assert str_repr == repr_repr
    assert "duration=" in str_repr
    assert "start=" in str_repr
    assert "end=" in str_repr


def test_str_empty():
    """__str__ should handle empty TemporalMetadata."""
    tm = TemporalMetadata()
    str_repr = str(tm)
    assert "TemporalMetadata" in str_repr


# ============================================================================
# Edge Cases
# ============================================================================


def test_zero_duration():
    """Zero duration should be handled correctly."""
    tm = TemporalMetadata(duration="PT0S")
    assert tm.duration == "PT0S"
    assert tm.duration_seconds() == 0.0


@given(iso8601_datetime_strings())
@settings(max_examples=50)
def test_same_start_and_end_time(datetime_str):
    """Same start and end time should result in zero duration."""
    tm = TemporalMetadata(start_time=datetime_str, end_time=datetime_str)
    tm.calculate_duration()

    assert tm.duration == "PT0S"


@given(st.floats(min_value=-86400, max_value=-0.001, allow_infinity=False, allow_nan=False))
@settings(max_examples=50)
def test_negative_duration_from_times(start_before_end):
    """
    If end time is before start time, calculate_duration should fail.
    """
    base = datetime(2025, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    end_time = base + timedelta(seconds=start_before_end)  # Earlier
    start_time = base  # Later

    tm = TemporalMetadata(start_time=start_time, end_time=end_time)
    success = tm.calculate_duration()

    assert not success


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
