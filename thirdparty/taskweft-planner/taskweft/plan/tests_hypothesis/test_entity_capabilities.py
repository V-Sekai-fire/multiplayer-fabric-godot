#!/usr/bin/env python
"""
Hypothesis Property-Based Tests for Entity-Capabilities System in IPyHOP-temporal

Converted from unittest-based tests to hypothesis @given-based property tests.

These tests validate:
1. EntityCapabilities class functionality
2. Integration with Actions class
3. Integration with Methods class
4. Capability-based filtering in IPyHOP planner
5. Multi-agent planning with heterogeneous capabilities
6. ReBAC engine
7. Backward compatibility wrapper

Author: Ernest Lee
"""

import os
import sys
import importlib.util

import pytest
from hypothesis import given, settings, assume, HealthCheck
from hypothesis import strategies as st

# Add parent directory to path for imports
_plan_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, _plan_dir)

# Load State module
state_spec = importlib.util.spec_from_file_location("state", os.path.join(_plan_dir, "ipyhop/state.py"))
state_module = importlib.util.module_from_spec(state_spec)
state_spec.loader.exec_module(state_module)
State = state_module.State

# Load Methods module
methods_spec = importlib.util.spec_from_file_location("methods", os.path.join(_plan_dir, "ipyhop/methods.py"))
methods_module = importlib.util.module_from_spec(methods_spec)
methods_spec.loader.exec_module(methods_module)
Methods = methods_module.Methods

# Load Actions module
actions_spec = importlib.util.spec_from_file_location("actions", os.path.join(_plan_dir, "ipyhop/actions.py"))
actions_module = importlib.util.module_from_spec(actions_spec)
actions_spec.loader.exec_module(actions_module)
Actions = actions_module.Actions

# Load Capabilities module (ReBAC-based)
caps_spec = importlib.util.spec_from_file_location("capabilities", os.path.join(_plan_dir, "ipyhop/capabilities.py"))
caps_module = importlib.util.module_from_spec(caps_spec)
caps_spec.loader.exec_module(caps_module)
ReBACEngine = caps_module.ReBACEngine
EntityCapabilities = caps_module.EntityCapabilities
RelationshipType = caps_module.RelationshipType
Condition = caps_module.Condition

# Load Planner module
try:
    from ipyhop.planner import IPyHOP

    PLANNER_AVAILABLE = True
except ImportError as e:
    IPyHOP = None
    PLANNER_AVAILABLE = False


# ============================================================================
# Hypothesis Strategies
# ============================================================================

_identifier_alphabet = st.characters(
    whitelist_categories=("Ll", "Lu", "Nd"),
    whitelist_characters="_",
)

entity_names = st.text(
    alphabet=_identifier_alphabet,
    min_size=1,
    max_size=20,
).filter(lambda s: s[0].isalpha() or s[0] == "_").map(lambda s: "entity_" + s)

capability_names = st.text(
    alphabet=_identifier_alphabet,
    min_size=1,
    max_size=20,
).filter(lambda s: s[0].isalpha() or s[0] == "_").map(lambda s: "cap_" + s)

capability_lists = st.lists(capability_names, min_size=1, max_size=10)

unique_capability_lists = st.lists(
    capability_names, min_size=1, max_size=10, unique=True
)


@st.composite
def entity_capability_pair(draw):
    """Draw an (entity, capability) pair."""
    entity = draw(entity_names)
    cap = draw(capability_names)
    return entity, cap


@st.composite
def entity_with_capabilities(draw):
    """Draw an entity name paired with a list of unique capabilities."""
    entity = draw(entity_names)
    caps = draw(unique_capability_lists)
    return entity, caps


@st.composite
def bulk_assignments(draw):
    """Draw a dict mapping entities to capability lists for bulk_assign."""
    entities = draw(st.lists(entity_names, min_size=1, max_size=5, unique=True))
    assignments = {}
    for e in entities:
        caps = draw(unique_capability_lists)
        assignments[e] = caps
    return assignments


@st.composite
def distinct_entity_pairs(draw):
    """Draw two distinct entity names."""
    e1 = draw(entity_names)
    e2 = draw(entity_names)
    assume(e1 != e2)
    return e1, e2


@st.composite
def distinct_capability_pairs(draw):
    """Draw two distinct capability names."""
    c1 = draw(capability_names)
    c2 = draw(capability_names)
    assume(c1 != c2)
    return c1, c2


relationship_types = st.sampled_from(list(RelationshipType))


# ============================================================================
# Test EntityCapabilities
# ============================================================================


class TestEntityCapabilities:
    """Property-based tests for EntityCapabilities class."""

    @given(st.data())
    @settings(max_examples=50)
    def test_initialization_is_empty(self, data):
        """A fresh EntityCapabilities has no entities and no capabilities."""
        caps = EntityCapabilities()
        assert caps.get_all_entities() == set()
        assert caps.get_all_capabilities() == set()

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=100)
    def test_assign_capability_then_has(self, entity, cap):
        """After assigning a capability, has_capability returns True for it."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        assert caps.has_capability(entity, cap)
        assert entity in caps.get_all_entities()
        assert cap in caps.get_all_capabilities()

    @given(entity=entity_names, cap=capability_names, other_cap=capability_names)
    @settings(max_examples=100)
    def test_assign_capability_does_not_grant_unrelated(self, entity, cap, other_cap):
        """Assigning one capability does not grant a different one."""
        assume(cap != other_cap)
        assume(other_cap != entity)
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        assert not caps.has_capability(entity, other_cap)

    @given(data=entity_with_capabilities())
    @settings(max_examples=100)
    def test_assign_multiple_capabilities(self, data):
        """assign_capabilities grants all listed capabilities."""
        entity, cap_list = data
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)

        for c in cap_list:
            assert caps.has_capability(entity, c)
        assert caps.count_capabilities_of_entity(entity) == len(set(cap_list))

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=100)
    def test_revoke_capability(self, entity, cap):
        """Revoking an assigned capability removes it."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)
        assert caps.has_capability(entity, cap)

        result = caps.revoke_capability(entity, cap)
        assert result is True
        assert not caps.has_capability(entity, cap)

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_revoke_nonexistent_returns_false(self, entity, cap):
        """Revoking a capability that was never assigned returns False."""
        caps = EntityCapabilities()
        result = caps.revoke_capability(entity, cap)
        assert result is False

    @given(
        entities=st.lists(entity_names, min_size=2, max_size=5, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=100)
    def test_get_entities_with_capability(self, entities, cap):
        """get_entities_with_capability returns exactly the entities that were assigned."""
        caps = EntityCapabilities()
        for e in entities:
            caps.assign_capability(e, cap)

        result = caps.get_entities_with_capability(cap)
        assert result == set(entities)

    @given(data=entity_with_capabilities())
    @settings(max_examples=100)
    def test_get_entity_capabilities(self, data):
        """get_entity_capabilities returns the exact set of assigned capabilities."""
        entity, cap_list = data
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)

        result = caps.get_entity_capabilities(entity)
        assert result == set(cap_list)

    @given(
        entities=st.lists(entity_names, min_size=1, max_size=5, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=100)
    def test_count_entities_with_capability(self, entities, cap):
        """count_entities_with_capability matches the number of assigned entities."""
        caps = EntityCapabilities()
        for e in entities:
            caps.assign_capability(e, cap)

        assert caps.count_entities_with_capability(cap) == len(entities)

    @given(data=entity_with_capabilities())
    @settings(max_examples=100)
    def test_count_capabilities_of_entity(self, data):
        """count_capabilities_of_entity matches the number of unique assigned capabilities."""
        entity, cap_list = data
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)

        assert caps.count_capabilities_of_entity(entity) == len(set(cap_list))

    @given(
        entity=entity_names,
        assigned_cap=capability_names,
        query_caps=unique_capability_lists,
    )
    @settings(max_examples=100)
    def test_has_any_capability(self, entity, assigned_cap, query_caps):
        """has_any_capability is True iff assigned_cap is among the queried list."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, assigned_cap)

        result = caps.has_any_capability(entity, query_caps)
        assert result == (assigned_cap in query_caps)

    @given(data=entity_with_capabilities(), extra_cap=capability_names)
    @settings(max_examples=100)
    def test_has_all_capabilities(self, data, extra_cap):
        """has_all_capabilities is True for a subset, False when an unassigned cap is included."""
        entity, cap_list = data
        assume(extra_cap not in cap_list)
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)

        # All assigned caps should pass
        assert caps.has_all_capabilities(entity, cap_list)
        # Adding an unassigned cap should fail
        assert not caps.has_all_capabilities(entity, cap_list + [extra_cap])

    @given(assignments=bulk_assignments())
    @settings(max_examples=100)
    def test_bulk_assign(self, assignments):
        """bulk_assign grants all capabilities to all entities."""
        caps = EntityCapabilities()
        caps.bulk_assign(assignments)

        for entity, cap_list in assignments.items():
            for c in cap_list:
                assert caps.has_capability(entity, c)

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_copy_is_independent(self, entity, cap):
        """Modifying a copy does not affect the original."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        caps_copy = caps.copy()
        assert caps_copy.has_capability(entity, cap)

        caps_copy.revoke_capability(entity, cap)
        assert caps.has_capability(entity, cap)
        assert not caps_copy.has_capability(entity, cap)

    @given(
        entities=st.lists(entity_names, min_size=1, max_size=3, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=50)
    def test_clear(self, entities, cap):
        """After clear(), all entities and capabilities are gone."""
        caps = EntityCapabilities()
        for e in entities:
            caps.assign_capability(e, cap)

        caps.clear()
        assert caps.get_all_entities() == set()
        assert caps.get_all_capabilities() == set()

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_string_representation(self, entity, cap):
        """String representation contains entity and capability names."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        str_repr = str(caps)
        assert "ENTITY-CAPABILITIES:" in str_repr
        assert entity in str_repr
        assert cap in str_repr


# ============================================================================
# Test Actions Integration
# ============================================================================


class TestActionsCapabilitiesIntegration:
    """Property-based tests for Actions class capability integration."""

    @given(cap_list=unique_capability_lists)
    @settings(max_examples=50, suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_declare_action_capabilities(self, cap_list):
        """Declared action capabilities can be retrieved."""
        actions = Actions()

        def dummy_action():
            return False

        actions.declare_actions([dummy_action])
        actions.declare_action_capabilities({"dummy_action": cap_list})

        retrieved = actions.get_action_capabilities("dummy_action")
        assert retrieved == cap_list

    @given(action_name=entity_names)
    @settings(max_examples=50)
    def test_get_action_capabilities_nonexistent(self, action_name):
        """Querying capabilities for a non-existent action returns empty list."""
        actions = Actions()
        assert actions.get_action_capabilities(action_name) == []

    @given(cap_list=unique_capability_lists)
    @settings(max_examples=50, suppress_health_check=[HealthCheck.function_scoped_fixture])
    def test_requires_capabilities(self, cap_list):
        """An action with declared capabilities requires capabilities; one without does not."""
        actions = Actions()

        def action_with_caps():
            return False

        def action_without_caps():
            return False

        actions.declare_actions([action_with_caps, action_without_caps])
        actions.declare_action_capabilities({"action_with_caps": cap_list})

        assert actions.requires_capabilities("action_with_caps")
        assert not actions.requires_capabilities("action_without_caps")


# ============================================================================
# Test Methods Integration
# ============================================================================


class TestMethodsCapabilitiesIntegration:
    """Property-based tests for Methods class capability integration."""

    @given(
        goal_name=entity_names,
        cap_list=unique_capability_lists,
    )
    @settings(max_examples=50)
    def test_declare_goal_capabilities(self, goal_name, cap_list):
        """Declared goal capabilities can be retrieved."""
        methods = Methods()
        methods.declare_goal_capabilities({goal_name: cap_list})

        retrieved = methods.get_goal_capabilities(goal_name)
        assert retrieved == cap_list

    @given(goal_name=entity_names)
    @settings(max_examples=50)
    def test_get_goal_capabilities_nonexistent(self, goal_name):
        """Querying capabilities for a non-existent goal returns empty list."""
        methods = Methods()
        assert methods.get_goal_capabilities(goal_name) == []

    @given(
        task_name=entity_names,
        cap_list=unique_capability_lists,
    )
    @settings(max_examples=50)
    def test_declare_task_capabilities(self, task_name, cap_list):
        """Declared task capabilities can be retrieved."""
        methods = Methods()
        methods.declare_task_capabilities({task_name: cap_list})

        retrieved = methods.get_task_capabilities(task_name)
        assert retrieved == cap_list

    @given(task_name=entity_names)
    @settings(max_examples=50)
    def test_get_task_capabilities_nonexistent(self, task_name):
        """Querying capabilities for a non-existent task returns empty list."""
        methods = Methods()
        assert methods.get_task_capabilities(task_name) == []


# ============================================================================
# Test Planner Integration
# ============================================================================


@pytest.mark.skipif(not PLANNER_AVAILABLE, reason="IPyHOP planner not available")
class TestPlannerCapabilitiesIntegration:
    """Property-based tests for IPyHOP planner capability integration."""

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_planner_accepts_entity_capabilities(self, entity, cap):
        """Planner accepts entity_capabilities parameter and stores it."""
        methods = Methods()
        actions = Actions()
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        planner = IPyHOP(methods, actions, entity_capabilities=caps)
        assert planner._entity_capabilities is caps

    @given(data=st.data())
    @settings(max_examples=50)
    def test_planner_without_entity_capabilities(self, data):
        """Planner works without entity_capabilities (defaults to None)."""
        methods = Methods()
        actions = Actions()
        planner = IPyHOP(methods, actions)
        assert planner._entity_capabilities is None

    @given(
        entity=entity_names,
        cap=capability_names,
        other_cap=capability_names,
    )
    @settings(max_examples=50)
    def test_capability_checking_logic(self, entity, cap, other_cap):
        """Capability checks correctly distinguish assigned vs unassigned capabilities."""
        assume(cap != other_cap)
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)

        assert caps.has_all_capabilities(entity, [cap])
        assert not caps.has_all_capabilities(entity, [other_cap])

        actions = Actions()

        def dummy_action(state, agent, dest):
            return None

        actions.declare_actions([dummy_action])
        actions.declare_action_capabilities({"dummy_action": [cap]})

        required = actions.get_action_capabilities("dummy_action")
        assert required == [cap]
        assert caps.has_all_capabilities(entity, required)

    @given(
        entity=entity_names,
        required_cap=capability_names,
        entity_cap=capability_names,
    )
    @settings(max_examples=50)
    def test_capability_violation_detection(self, entity, required_cap, entity_cap):
        """Capability violations are detected: entity lacks the required capability."""
        assume(required_cap != entity_cap)
        caps = EntityCapabilities()
        caps.assign_capability(entity, entity_cap)

        actions = Actions()

        def some_action(state, agent, dest):
            return None

        actions.declare_actions([some_action])
        actions.declare_action_capabilities({"some_action": [required_cap]})

        required = actions.get_action_capabilities("some_action")
        # Entity has entity_cap but not required_cap
        assert not caps.has_all_capabilities(entity, required)

        # Now grant the required cap
        caps.assign_capability(entity, required_cap)
        assert caps.has_all_capabilities(entity, required)


# ============================================================================
# Test Multi-Agent Scenarios
# ============================================================================


@pytest.mark.skipif(not PLANNER_AVAILABLE, reason="IPyHOP planner not available")
class TestMultiAgentCapabilities:
    """Property-based tests for multi-agent planning with heterogeneous capabilities."""

    @given(
        agents=st.lists(entity_names, min_size=2, max_size=4, unique=True),
        locations=st.lists(
            st.text(
                alphabet=_identifier_alphabet,
                min_size=1,
                max_size=10,
            ).filter(lambda s: s[0].isalpha() or s[0] == "_"),
            min_size=2,
            max_size=4,
            unique=True,
        ),
    )
    @settings(max_examples=20, suppress_health_check=[HealthCheck.too_slow])
    def test_heterogeneous_capabilities(self, agents, locations):
        """Agents with different capabilities can each produce a plan using their own action."""
        assume(len(agents) >= 2 and len(locations) >= 2)

        actions = Actions()
        caps = EntityCapabilities()

        # Create distinct actions for each agent
        action_funcs = []
        cap_decls = {}
        agent_caps = {}

        for i, agent in enumerate(agents):
            cap_name = f"cap_{i}"
            action_name = f"a_move_{i}"

            # We need to create a closure capturing the action name
            def make_action(name):
                def action_fn(state, ag, dest):
                    new_state = State("s")
                    new_state.loc = state.loc.copy()
                    new_state.loc[ag] = dest
                    return new_state

                action_fn.__name__ = name
                return action_fn

            fn = make_action(action_name)
            action_funcs.append(fn)
            cap_decls[action_name] = [cap_name]
            caps.assign_capability(agent, cap_name)
            agent_caps[agent] = (action_name, cap_name)

        actions.declare_actions(action_funcs)
        actions.declare_action_capabilities(cap_decls)

        # Build a method that tries all actions
        all_action_names = [agent_caps[a][0] for a in agents]

        def m_move(state, agent, dest):
            return [(name, agent, dest) for name in all_action_names]

        methods = Methods()
        methods.declare_task_methods("m_move", [m_move])

        planner = IPyHOP(methods, actions, entity_capabilities=caps)

        # Each agent should be able to plan
        for agent in agents:
            state = State("s")
            state.loc = {agent: locations[0]}
            plan = planner.plan(state, [("m_move", agent, locations[1])])
            assert isinstance(plan, list)


# ============================================================================
# Test ReBAC Engine
# ============================================================================


class TestReBACEngine:
    """Property-based tests for ReBAC engine."""

    @given(subject=entity_names, cap=capability_names)
    @settings(max_examples=100)
    def test_direct_capability(self, subject, cap):
        """A direct HAS_CAPABILITY relationship authorizes the subject."""
        rebac = ReBACEngine()
        rebac.add_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)

        authorized, path = rebac.can(subject, cap)
        assert authorized
        assert path == [subject, "[has_capability]", cap]

    @given(
        subject=entity_names,
        group=entity_names,
        cap=capability_names,
    )
    @settings(max_examples=100)
    def test_transitive_capability_via_group(self, subject, group, cap):
        """Transitive capability through group membership is authorized."""
        assume(subject != group and group != cap and subject != cap)
        rebac = ReBACEngine()
        rebac.add_relationship(subject, group, RelationshipType.IS_MEMBER_OF)
        rebac.add_relationship(group, cap, RelationshipType.HAS_CAPABILITY)

        authorized, path = rebac.can(subject, cap)
        assert authorized
        assert group in path
        assert "[is_member_of]" in path

    @given(
        subject=entity_names,
        cap=capability_names,
        low_fuel=st.integers(min_value=0, max_value=100),
        high_fuel=st.integers(min_value=101, max_value=1000),
    )
    @settings(max_examples=50)
    def test_conditional_capability(self, subject, cap, low_fuel, high_fuel):
        """Conditional capabilities are only authorized when the condition holds."""

        class MockState:
            def __init__(self, fuel_val):
                self.fuel = {subject: fuel_val}

        def has_fuel(state, subj, obj):
            return state.fuel.get(subj, 0) > 100

        rebac = ReBACEngine()
        rebac.add_relationship(
            subject,
            cap,
            RelationshipType.HAS_CAPABILITY,
            conditions=[Condition(has_fuel, "fuel > 100")],
        )

        # Low fuel: not authorized
        state_low = MockState(low_fuel)
        authorized_low, _ = rebac.can(subject, cap, state_low)
        assert not authorized_low

        # High fuel: authorized
        state_high = MockState(high_fuel)
        authorized_high, _ = rebac.can(subject, cap, state_high)
        assert authorized_high

    @given(
        subject=entity_names,
        assigned_cap=capability_names,
        queried_cap=capability_names,
    )
    @settings(max_examples=100)
    def test_no_capability(self, subject, assigned_cap, queried_cap):
        """An entity does not have a capability it was not assigned."""
        assume(assigned_cap != queried_cap)
        rebac = ReBACEngine()
        rebac.add_relationship(subject, assigned_cap, RelationshipType.HAS_CAPABILITY)

        authorized, path = rebac.can(subject, queried_cap)
        assert not authorized
        assert path == []

    @given(
        subject=entity_names,
        resource=entity_names,
        cap=capability_names,
    )
    @settings(max_examples=100)
    def test_multiple_relationship_types(self, subject, resource, cap):
        """A CONTROLS relationship transitively grants the controlled entity's capabilities."""
        assume(subject != resource and resource != cap and subject != cap)
        rebac = ReBACEngine()
        rebac.add_relationship(subject, resource, RelationshipType.CONTROLS)
        rebac.add_relationship(resource, cap, RelationshipType.HAS_CAPABILITY)

        authorized, path = rebac.can(subject, cap)
        assert authorized
        assert "[controls]" in path

    @given(subject=entity_names, cap=capability_names)
    @settings(max_examples=100)
    def test_remove_relationship(self, subject, cap):
        """Removing a relationship revokes authorization."""
        rebac = ReBACEngine()
        rebac.add_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)
        assert rebac.can(subject, cap)[0]

        rebac.remove_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)
        assert not rebac.can(subject, cap)[0]

    @given(
        subject=entity_names,
        caps=st.lists(capability_names, min_size=1, max_size=5, unique=True),
    )
    @settings(max_examples=100)
    def test_get_relationships(self, subject, caps):
        """get_relationships returns all relationships for a subject."""
        rebac = ReBACEngine()
        for c in caps:
            rebac.add_relationship(subject, c, RelationshipType.HAS_CAPABILITY)

        relationships = rebac.get_relationships(subject)
        assert len(relationships) == len(caps)

    @given(
        subjects=st.lists(entity_names, min_size=1, max_size=5, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=100)
    def test_get_all_subjects(self, subjects, cap):
        """get_all_subjects returns all subjects that have relationships."""
        rebac = ReBACEngine()
        for s in subjects:
            rebac.add_relationship(s, cap, RelationshipType.HAS_CAPABILITY)

        result = rebac.get_all_subjects()
        assert result == set(subjects)

    @given(
        subject=entity_names,
        caps=st.lists(capability_names, min_size=1, max_size=5, unique=True),
    )
    @settings(max_examples=100)
    def test_get_all_objects(self, subject, caps):
        """get_all_objects returns all objects in the graph."""
        rebac = ReBACEngine()
        for c in caps:
            rebac.add_relationship(subject, c, RelationshipType.HAS_CAPABILITY)

        result = rebac.get_all_objects()
        assert result == set(caps)

    @given(subject=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_clear(self, subject, cap):
        """After clear(), the engine has no subjects or objects."""
        rebac = ReBACEngine()
        rebac.add_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)
        rebac.clear()

        assert rebac.get_all_subjects() == set()
        assert rebac.get_all_objects() == set()

    @given(subject=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_copy_is_independent(self, subject, cap):
        """Modifying a copy does not affect the original."""
        rebac = ReBACEngine()
        rebac.add_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)

        rebac_copy = rebac.copy()
        assert rebac_copy.can(subject, cap)[0]

        rebac_copy.remove_relationship(subject, cap, RelationshipType.HAS_CAPABILITY)
        assert rebac.can(subject, cap)[0]
        assert not rebac_copy.can(subject, cap)[0]

    @given(
        nodes=st.lists(entity_names, min_size=3, max_size=3, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
    def test_max_depth_prevents_infinite_loop(self, nodes, cap):
        """max_depth prevents infinite loops in cyclic relationship graphs."""
        assume(cap not in nodes)
        a, b, c = nodes

        rebac = ReBACEngine()
        rebac.add_relationship(a, b, RelationshipType.PARTNER_OF)
        rebac.add_relationship(b, c, RelationshipType.PARTNER_OF)
        rebac.add_relationship(c, a, RelationshipType.PARTNER_OF)
        rebac.add_relationship(c, cap, RelationshipType.HAS_CAPABILITY)

        authorized, path = rebac.can(a, cap, max_depth=5)
        # Should not hang; result is a bool regardless
        assert isinstance(authorized, bool)


# ============================================================================
# Test Backward Compatibility
# ============================================================================


class TestBackwardCompatibility:
    """Property-based tests for EntityCapabilities backward-compatible wrapper."""

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_assign_capability(self, entity, cap):
        """assign_capability grants the capability (backward compatible)."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)
        assert caps.has_capability(entity, cap)

    @given(data=entity_with_capabilities())
    @settings(max_examples=50)
    def test_assign_multiple_capabilities(self, data):
        """assign_capabilities grants all capabilities (backward compatible)."""
        entity, cap_list = data
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)
        for c in cap_list:
            assert caps.has_capability(entity, c)

    @given(entity=entity_names, cap=capability_names)
    @settings(max_examples=50)
    def test_revoke_capability(self, entity, cap):
        """revoke_capability removes the capability (backward compatible)."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, cap)
        caps.revoke_capability(entity, cap)
        assert not caps.has_capability(entity, cap)

    @given(data=entity_with_capabilities())
    @settings(max_examples=50)
    def test_get_entity_capabilities(self, data):
        """get_entity_capabilities returns the correct set (backward compatible)."""
        entity, cap_list = data
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)
        assert caps.get_entity_capabilities(entity) == set(cap_list)

    @given(
        entities=st.lists(entity_names, min_size=1, max_size=5, unique=True),
        cap=capability_names,
    )
    @settings(max_examples=50)
    def test_get_entities_with_capability(self, entities, cap):
        """get_entities_with_capability returns the correct set (backward compatible)."""
        caps = EntityCapabilities()
        for e in entities:
            caps.assign_capability(e, cap)
        assert caps.get_entities_with_capability(cap) == set(entities)

    @given(
        entity=entity_names,
        assigned_cap=capability_names,
        query_caps=unique_capability_lists,
    )
    @settings(max_examples=50)
    def test_has_any_capability(self, entity, assigned_cap, query_caps):
        """has_any_capability works correctly (backward compatible)."""
        caps = EntityCapabilities()
        caps.assign_capability(entity, assigned_cap)

        result = caps.has_any_capability(entity, query_caps)
        assert result == (assigned_cap in query_caps)

    @given(data=entity_with_capabilities(), extra_cap=capability_names)
    @settings(max_examples=50)
    def test_has_all_capabilities(self, data, extra_cap):
        """has_all_capabilities works correctly (backward compatible)."""
        entity, cap_list = data
        assume(extra_cap not in cap_list)
        caps = EntityCapabilities()
        caps.assign_capabilities(entity, cap_list)

        assert caps.has_all_capabilities(entity, cap_list)
        assert not caps.has_all_capabilities(entity, cap_list + [extra_cap])

    @given(assignments=bulk_assignments())
    @settings(max_examples=50)
    def test_bulk_assign(self, assignments):
        """bulk_assign grants all capabilities (backward compatible)."""
        caps = EntityCapabilities()
        caps.bulk_assign(assignments)
        for entity, cap_list in assignments.items():
            for c in cap_list:
                assert caps.has_capability(entity, c)
