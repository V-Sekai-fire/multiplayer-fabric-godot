# Hypothesis Property-Based Tests

This directory contains comprehensive property-based tests using [Hypothesis](https://hypothesis.readthedocs.io/) for the IPyHOP-temporal planning library.

## Test Coverage

The test suite provides systematic, high-coverage testing across all core modules:

### Test Files

| File | Module | Test Count | Coverage Focus |
|------|--------|------------|----------------|
| `test_temporal_utils.py` | `ipyhop.temporal.utils` | 30+ | ISO 8601 duration parsing/formatting, datetime arithmetic |
| `test_temporal_metadata.py` | `ipyhop.temporal_metadata` | 25+ | TemporalMetadata class, duration calculations, serialization |
| `test_state.py` | `ipyhop.state` | 25+ | State management, temporal tracking, timeline operations |
| `test_actions.py` | `ipyhop.actions` | 20+ | Action declaration, temporal actions, action models |
| `test_methods.py` | `ipyhop.methods` | 20+ | Task/goal/multigoal methods, method decomposition |

### Total: 120+ property-based tests

## Properties Tested

Each test file validates critical properties:

### Temporal Utilities
- **Round-trip consistency**: Format → Parse → Original value preserved
- **Boundary conditions**: Zero durations, negative values, edge cases
- **Type safety**: Invalid inputs return None or raise appropriate exceptions
- **Monotonicity**: Time progression maintains ordering

### Temporal Metadata
- **Duration consistency**: Calculate end from duration, recalculate duration → match
- **Serialization**: to_dict() → from_dict() preserves all data
- **Independence**: copy() creates truly independent copies
- **Validation**: Invalid ISO 8601 strings raise ValueError

### State Management
- **Deep copying**: Nested structures are fully independent after copy()
- **Timeline integrity**: Actions added in order, retrieved in order
- **Temporal isolation**: Variable assignments don't affect time tracking
- **Update semantics**: update() merges variables correctly

### Actions & Methods
- **Registration consistency**: All dictionaries maintain same keys
- **Temporal integration**: Temporal actions registered in both action_dict and temporal_dict
- **Method decomposition**: _goals_not_achieved() correctly identifies unachieved goals
- **Multigoal splitting**: mgm_split_multigoal() produces correct goal lists

## Running Tests

### Run All Tests
```bash
uv run pytest tests_hypothesis/ -v
```

### Run Specific Test File
```bash
uv run pytest tests_hypothesis/test_temporal_utils.py -v
```

### Run With Coverage
```bash
uv run pytest tests_hypothesis/ --cov=ipyhop --cov-report=term-missing
```

### Run Specific Test
```bash
uv run pytest tests_hypothesis/test_temporal_utils.py::test_parse_valid_duration_returns_positive_seconds -v
```

### Quick Test (Fewer Examples)
```bash
# Edit test file: change max_examples=100 to max_examples=10
uv run pytest tests_hypothesis/ -v
```

## Test Structure

Each test follows the property-based testing paradigm:

```python
@given(strategy)
@settings(max_examples=100)
def test_property_name(generated_value):
    """Describe the property being tested."""
    # Arrange
    object = create_object(generated_value)
    
    # Act
    result = object.operation()
    
    # Assert property holds
    assert property_holds(result)
```

### Key Strategies

- **valid_iso8601_durations**: Generates valid ISO 8601 duration strings (PT1H30M, PT5M, etc.)
- **valid_iso8601_datetimes**: Generates valid ISO 8601 datetime strings
- **state_variables**: Generates random state variable assignments
- **action_functions**: Generates simple action functions with configurable success rates
- **method_functions**: Generates method functions that return subtask lists

## Property Examples

### Round-Trip Property
```python
@given(positive_seconds())
def test_parse_roundtrip_preserves_value(seconds):
    """Parsing a formatted duration should return the original seconds."""
    formatted = format_iso8601_duration(seconds)
    parsed = parse_iso8601_duration(formatted)
    assert abs(parsed - seconds) < 0.001  # Allow floating point error
```

### Consistency Property
```python
@given(valid_durations(), valid_datetimes())
def test_duration_end_time_consistency(duration, start_time):
    """
    Property: Calculating end from duration, then recalculating duration
    should return the original duration.
    """
    tm = TemporalMetadata(duration=duration, start_time=start_time)
    tm.calculate_end_from_duration()
    
    original_duration = tm.duration
    tm._duration = None
    tm.calculate_duration()
    
    assert abs(original_sec - recalculated_sec) < 0.01
```

### Invariant Property
```python
@given(action_functions())
def test_action_registration_consistency(action_list):
    """
    Property: After declare_actions, all three dicts should have the same keys.
    """
    actions = Actions()
    actions.declare_actions(action_list)
    
    action_names = {a.__name__ for a in action_list}
    assert set(actions.action_dict.keys()) == action_names
    assert set(actions.action_prob.keys()) == action_names
    assert set(actions.action_cost.keys()) == action_names
```

## Development Guidelines

### Adding New Tests

1. **Identify the property** you want to test (invariant, round-trip, consistency, etc.)
2. **Create appropriate strategies** for generating test data
3. **Write the test** using `@given()` decorator
4. **Set appropriate max_examples** (50-100 for most tests, use `suppress_health_check` for slow tests)
5. **Add assertions** that verify the property holds

### Strategy Best Practices

- Use `@st.composite` for complex generated data
- Use `assume()` to filter out invalid generated values
- Keep strategies focused and reusable
- Document what each strategy generates

### Performance Tips

- Use `max_examples=50` for quick feedback during development
- Use `max_examples=100` or higher for CI/CD
- Mark slow tests with `suppress_health_check=[HealthCheck.too_slow]`
- Use `@settings(deadline=None)` for tests that may take >2 seconds

## Coverage Goals

Target coverage metrics:
- **Line coverage**: >90% for core modules
- **Branch coverage**: >85% for decision points
- **Property coverage**: All critical invariants tested

## Integration with CI

Add to your CI pipeline:
```yaml
- name: Run hypothesis tests
  run: |
    uv run pytest tests_hypothesis/ -v --tb=short
```

## References

- [Hypothesis Documentation](https://hypothesis.readthedocs.io/)
- [Property-Based Testing Guide](https://hypothesis.readthedocs.io/en/latest/data.html)
- [ISO 8601 Duration Format](https://en.wikipedia.org/wiki/ISO_8601#Durations)
