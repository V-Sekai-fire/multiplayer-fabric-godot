#!/usr/bin/env python
"""
Relationship-Based Access Control (ReBAC) for IPyHOP-temporal

This module implements ReBAC for planning domains, providing:
1. Relationship graphs (subject → relationship → object)
2. Transitive relationship evaluation
3. Contextual conditions on relationships
4. Role-based and group-based inheritance

LITERATURE BASIS:
- "ReBAC: Relationship-Based Access Control" (Google Zanzibar, 2018)
- "Decentralized Identity-Based Access Control" (2020)
- "Attribute-Based Access Control in Multi-Agent Systems" (2021)

DESIGN PRINCIPLES:
- Subjects: Entities/agents in the planning domain
- Objects: Actions, resources, zones, capabilities
- Relationships: Typed edges (has_capability, is_member_of, controls, etc.)
- Conditions: Contextual constraints (state-dependent, time-dependent)

AUTHORIZATION MODEL:
- Direct: subject → relationship → object
- Indirect: subject → group → relationship → object (transitive)
- Conditional: relationship + condition evaluation

Author(s): Yash Bansod, Ernest Lee
Repository: https://github.com/V-Sekai-fire/IPyHOP-temporal
"""

from copy import deepcopy
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Set, Tuple

# ============================================================================
# Relationship Types
# ============================================================================


class RelationshipType(Enum):
    """Standard relationship types for ReBAC."""

    HAS_CAPABILITY = "has_capability"  # Direct capability assignment
    IS_MEMBER_OF = "is_member_of"  # Group membership
    CONTROLS = "controls"  # Resource control
    OWNS = "owns"  # Ownership
    DELEGATED_TO = "delegated_to"  # Capability delegation
    SUPERVISOR_OF = "supervisor_of"  # Hierarchical authority
    PARTNER_OF = "partner_of"  # Collaborative relationships
    IS_A = "is_a"  # Type / subclass relationship (mirrors Lean RelationType.IS_A)


# ============================================================================
# Condition System
# ============================================================================


@dataclass(frozen=True)
class Condition:
    """
    A condition that must be satisfied for a relationship to be valid.

    Conditions are evaluated in the context of the current planning state.

    Example:
        Condition(
            lambda state, subject, object: state.fuel.get(subject, 0) > 100
        )
    """

    predicate: Callable[[Any, str, str], bool]
    description: str = ""

    def __hash__(self):
        # Hash based on predicate id and description
        return hash((id(self.predicate), self.description))

    def evaluate(self, state: Any, subject: str, object: str) -> bool:
        """
        Evaluate the condition in the given context.

        :param state: Current planning state
        :param subject: Subject entity
        :param object: Object/capability
        :return: True if condition is satisfied
        """
        try:
            return self.predicate(state, subject, object)
        except Exception:
            return False


# ============================================================================
# Relationship Edge
# ============================================================================


@dataclass(frozen=True)
class RelationshipEdge:
    """
    A single relationship edge in the ReBAC graph.

    Represents: subject --[relationship_type]--> object
    """

    subject: str
    relationship_type: RelationshipType
    object: str
    conditions: Tuple[Condition, ...] = field(default_factory=tuple)
    metadata: Tuple[Tuple[str, Any], ...] = field(default_factory=tuple)

    def __post_init__(self):
        # Convert lists to tuples for immutability
        if isinstance(self.conditions, list):
            object.__setattr__(self, "conditions", tuple(self.conditions))
        if isinstance(self.metadata, dict):
            object.__setattr__(self, "metadata", tuple(self.metadata.items()))

    def is_valid(self, state: Any) -> bool:
        """
        Check if all conditions are satisfied.

        :param state: Current planning state
        :return: True if all conditions pass
        """
        return all(cond.evaluate(state, self.subject, self.object) for cond in self.conditions)


# ============================================================================
# ReBAC Authorization Engine
# ============================================================================


class ReBACEngine:
    """
    Relationship-Based Access Control engine for IPyHOP-temporal.

    Implements a graph-based authorization system where:
    - Entities (subjects) have relationships to capabilities/resources (objects)
    - Relationships can be direct or transitive (through groups/roles)
    - Conditions can restrict when relationships are valid

    Usage:
        rebac = ReBACEngine()
        rebac.add_relationship('alice', 'fly', RelationshipType.HAS_CAPABILITY)
        rebac.add_relationship('alice', 'pilots', RelationshipType.IS_MEMBER_OF)
        rebac.add_relationship('pilots', 'fly', RelationshipType.HAS_CAPABILITY)

        # Check direct capability
        rebac.can('alice', 'fly', state)  # True

        # Check transitive capability (alice → pilots → fly)
        rebac.can('alice', 'fly', state)  # True (via group)
    """

    def __init__(self):
        """
        Initialize the ReBAC engine.

        Internal structure:
        - _edges: List of RelationshipEdge objects
        - _subject_index: Dict[subject, Set[edges]] for fast lookup
        - _object_index: Dict[object, Set[edges]] for reverse lookup
        """
        self._edges: List[RelationshipEdge] = []
        self._subject_index: Dict[str, Set[RelationshipEdge]] = {}
        self._object_index: Dict[str, Set[RelationshipEdge]] = {}

    # ******************************        Core Relationship Methods        ****************************************** #
    def add_relationship(
        self,
        subject: str,
        object: str,
        relationship_type: RelationshipType,
        conditions: List[Condition] = None,
        metadata: Dict[str, Any] = None,
    ):
        """
        Add a relationship edge to the graph.

        :param subject: Subject entity (agent, resource)
        :param object: Object/capability/resource
        :param relationship_type: Type of relationship
        :param conditions: Optional list of conditions
        :param metadata: Optional metadata dictionary
        """
        edge = RelationshipEdge(
            subject=subject,
            relationship_type=relationship_type,
            object=object,
            conditions=conditions or (),
            metadata=tuple((metadata or {}).items()),
        )

        self._edges.append(edge)

        # Update indexes
        if subject not in self._subject_index:
            self._subject_index[subject] = set()
        self._subject_index[subject].add(edge)

        if object not in self._object_index:
            self._object_index[object] = set()
        self._object_index[object].add(edge)

    # ******************************        Class Method Declaration        ****************************************** #
    def remove_relationship(self, subject: str, object: str, relationship_type: RelationshipType) -> bool:
        """
        Remove a relationship edge from the graph.

        :return: True if relationship was found and removed
        """
        for edge in self._edges:
            if edge.subject == subject and edge.object == object and edge.relationship_type == relationship_type:
                self._edges.remove(edge)
                self._subject_index[subject].discard(edge)
                self._object_index[object].discard(edge)
                return True
        return False

    # ******************************        Authorization Checks        ****************************************** #
    def can(self, subject: str, capability: str, state: Any = None, max_depth: int = 10) -> Tuple[bool, List[str]]:
        """
        Check if a subject can perform an action/use a capability.

        Uses depth-first search to find valid relationship paths.

        :param subject: Subject entity
        :param capability: Capability/action to check
        :param state: Current planning state (for condition evaluation)
        :param max_depth: Maximum path depth (prevents infinite loops)
        :return: (authorized: bool, path: List[str])
        """
        path = self._find_path(subject, capability, state, set(), max_depth)
        return (len(path) > 0, path)

    # ******************************        Class Method Declaration        ****************************************** #
    def _find_path(self, current: str, target: str, state: Any, visited: Set[str], max_depth: int) -> List[str]:
        """
        Depth-first search for a valid relationship path.

        :return: List of nodes in the path, or empty list if not found
        """
        if max_depth <= 0:
            return []

        if current == target:
            return [current]

        if current in visited:
            return []

        visited.add(current)

        # Get all edges from current subject
        edges = self._subject_index.get(current, set())

        for edge in edges:
            # Skip invalid edges (conditions not met)
            if state is not None and not edge.is_valid(state):
                continue

            # Check if this edge directly reaches the target
            if edge.object == target:
                if edge.relationship_type in [
                    RelationshipType.HAS_CAPABILITY,
                    RelationshipType.CONTROLS,
                    RelationshipType.OWNS,
                ]:
                    return [current, f"[{edge.relationship_type.value}]", target]

            # Recursively search from the object
            sub_path = self._find_path(edge.object, target, state, visited.copy(), max_depth - 1)
            if sub_path:
                return [current, f"[{edge.relationship_type.value}]", edge.object] + sub_path[1:]

        return []

    # ******************************        Query Methods        ****************************************** #
    def get_relationships(self, subject: str) -> List[RelationshipEdge]:
        """Get all relationships for a subject."""
        return list(self._subject_index.get(subject, set()))

    # ******************************        Class Method Declaration        ****************************************** #
    def get_all_subjects(self) -> Set[str]:
        """Get all subjects in the system."""
        return set(self._subject_index.keys())

    # ******************************        Class Method Declaration        ****************************************** #
    def get_all_objects(self) -> Set[str]:
        """Get all objects in the system."""
        return set(self._object_index.keys())

    # ******************************        Bulk Operations        ****************************************** #
    def bulk_add_relationships(self, relationships: List[Tuple[str, str, RelationshipType]]):
        """
        Bulk add relationships.

        :param relationships: List of (subject, object, relationship_type) tuples
        """
        for subject, obj, rel_type in relationships:
            self.add_relationship(subject, obj, rel_type)

    # ******************************        Class Method Declaration        ****************************************** #
    def clear(self):
        """Clear all relationships."""
        self._edges.clear()
        self._subject_index.clear()
        self._object_index.clear()

    # ******************************        String Representation        ****************************************** #
    def __str__(self):
        """String representation of the ReBAC graph."""
        if not self._edges:
            return "ENTITY-CAPABILITIES: (empty)"

        lines = ["ENTITY-CAPABILITIES:"]
        for edge in sorted(self._edges, key=lambda e: (e.subject, e.object)):
            conditions_str = ""
            if edge.conditions:
                conditions_str = f" [conditions: {len(edge.conditions)}]"
            lines.append(f"  {edge.subject}: [{edge.object}]{conditions_str}")

        return "\n".join(lines)

    # ******************************        Class Method Declaration        ****************************************** #
    def copy(self) -> "ReBACEngine":
        """Create a deep copy of the ReBAC engine."""
        new_engine = ReBACEngine()
        new_engine._edges = deepcopy(self._edges)
        new_engine._subject_index = deepcopy(self._subject_index)
        new_engine._object_index = deepcopy(self._object_index)
        return new_engine


# ============================================================================
# Backward Compatibility: EntityCapabilities Wrapper
# ============================================================================


class EntityCapabilities(ReBACEngine):
    """
    Backward-compatible wrapper for EntityCapabilities using ReBAC.

    This class provides the same API as the original EntityCapabilities
    but uses the ReBAC engine internally for more expressive relationships.
    """

    def assign_capability(self, entity: str, capability: str):
        """Assign a capability to an entity (ReBAC: HAS_CAPABILITY relationship)."""
        self.add_relationship(entity, capability, RelationshipType.HAS_CAPABILITY)

    # ******************************        Class Method Declaration        ****************************************** #
    def assign_capabilities(self, entity: str, capabilities: List[str]):
        """Assign multiple capabilities to an entity."""
        for capability in capabilities:
            self.assign_capability(entity, capability)

    # ******************************        Class Method Declaration        ****************************************** #
    def revoke_capability(self, entity: str, capability: str) -> bool:
        """Revoke a capability from an entity."""
        return self.remove_relationship(entity, capability, RelationshipType.HAS_CAPABILITY)

    # ******************************        Class Method Declaration        ****************************************** #
    def has_capability(self, entity: str, capability: str, state: Any = None) -> bool:
        """Check if entity has a capability."""
        authorized, _ = self.can(entity, capability, state)
        return authorized

    # ******************************        Class Method Declaration        ****************************************** #
    def get_entity_capabilities(self, entity: str, state: Any = None) -> Set[str]:
        """Get all capabilities of an entity."""
        capabilities = set()
        for edge in self.get_relationships(entity):
            if edge.relationship_type == RelationshipType.HAS_CAPABILITY:
                if state is None or edge.is_valid(state):
                    capabilities.add(edge.object)
        return capabilities

    # ******************************        Class Method Declaration        ****************************************** #
    def get_entities_with_capability(self, capability: str, state: Any = None) -> Set[str]:
        """Get all entities with a specific capability."""
        entities = set()
        for edge in self._object_index.get(capability, set()):
            if edge.relationship_type == RelationshipType.HAS_CAPABILITY:
                if state is None or edge.is_valid(state):
                    entities.add(edge.subject)
        return entities

    # ******************************        Class Method Declaration        ****************************************** #
    def has_any_capability(self, entity: str, capabilities: List[str], state: Any = None) -> bool:
        """Check if entity has any of the specified capabilities."""
        for cap in capabilities:
            if self.has_capability(entity, cap, state):
                return True
        return False

    # ******************************        Class Method Declaration        ****************************************** #
    def has_all_capabilities(self, entity: str, capabilities: List[str], state: Any = None) -> bool:
        """Check if entity has all of the specified capabilities."""
        for cap in capabilities:
            if not self.has_capability(entity, cap, state):
                return False
        return True

    # ******************************        Class Method Declaration        ****************************************** #
    def bulk_assign(self, assignments: Dict[str, List[str]]):
        """Bulk assign capabilities to entities."""
        for entity, capabilities in assignments.items():
            self.assign_capabilities(entity, capabilities)

    # ******************************        Backward Compatibility Methods        ****************************************** #
    def get_all_entities(self) -> Set[str]:
        """Get all entities (backward compatibility)."""
        return self.get_all_subjects()

    # ******************************        Class Method Declaration        ****************************************** #
    def get_all_capabilities(self) -> Set[str]:
        """Get all capabilities (backward compatibility)."""
        return self.get_all_objects()

    # ******************************        Class Method Declaration        ****************************************** #
    def count_entities_with_capability(self, capability: str, state: Any = None) -> int:
        """Count entities with a capability (backward compatibility)."""
        return len(self.get_entities_with_capability(capability, state))

    # ******************************        Class Method Declaration        ****************************************** #
    def count_capabilities_of_entity(self, entity: str, state: Any = None) -> int:
        """Count capabilities of an entity (backward compatibility)."""
        return len(self.get_entity_capabilities(entity, state))

    # ******************************        Class Method Declaration        ****************************************** #
    def copy(self) -> "EntityCapabilities":
        """Create a copy (backward compatibility)."""
        new_caps = EntityCapabilities()
        new_caps._edges = deepcopy(self._edges)
        new_caps._subject_index = deepcopy(self._subject_index)
        new_caps._object_index = deepcopy(self._object_index)
        return new_caps

    # ******************************        Class Method Declaration        ****************************************** #
    def clear(self):
        """Clear all capabilities (backward compatibility)."""
        super().clear()


# ============================================================================
# Demo / Test
# ============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("ReBAC Entity-Capabilities Demo")
    print("=" * 70)

    # Create ReBAC engine
    rebac = ReBACEngine()

    # Example 1: Direct capability assignment
    print("\n1. Direct Capability Assignment:")
    print("-" * 70)
    rebac.add_relationship("alice", "fly", RelationshipType.HAS_CAPABILITY)
    rebac.add_relationship("bob", "swim", RelationshipType.HAS_CAPABILITY)

    print(f"Alice can fly: {rebac.can('alice', 'fly')}")
    print(f"Bob can fly: {rebac.can('bob', 'fly')}")

    # Example 2: Group-based (transitive) capabilities
    print("\n2. Group-Based Capabilities (Transitive):")
    print("-" * 70)
    rebac.add_relationship("alice", "pilots", RelationshipType.IS_MEMBER_OF)
    rebac.add_relationship("pilots", "operate_drone", RelationshipType.HAS_CAPABILITY)

    print(f"Alice can operate_drone: {rebac.can('alice', 'operate_drone')}")
    path = rebac.can("alice", "operate_drone")[1]
    print(f"  Authorization path: {' → '.join(path)}")

    # Example 3: Conditional capabilities
    print("\n3. Conditional Capabilities:")
    print("-" * 70)

    class MockState:
        def __init__(self):
            self.fuel = {"charlie": 50}  # Charlie has low fuel

    def has_sufficient_fuel(state, subject, obj):
        return state.fuel.get(subject, 0) > 100

    rebac.add_relationship(
        "charlie",
        "fly_long_distance",
        RelationshipType.HAS_CAPABILITY,
        conditions=[Condition(has_sufficient_fuel, "fuel > 100")],
    )

    state = MockState()
    print(f"Charlie can fly_long_distance (fuel=50): {rebac.can('charlie', 'fly_long_distance', state)}")

    state.fuel["charlie"] = 150
    print(f"Charlie can fly_long_distance (fuel=150): {rebac.can('charlie', 'fly_long_distance', state)}")

    # Example 4: Using backward-compatible EntityCapabilities
    print("\n4. Backward-Compatible EntityCapabilities:")
    print("-" * 70)
    caps = EntityCapabilities()
    caps.assign_capability("drone_1", "fly")
    caps.assign_capability("drone_1", "sense")
    caps.assign_capability("boat_1", "swim")

    print(f"drone_1 capabilities: {caps.get_entity_capabilities('drone_1')}")
    print(f"Entities that can fly: {caps.get_entities_with_capability('fly')}")

    print("\n" + str(caps))
    print("\n" + "=" * 70)

"""
Author(s): Yash Bansod, Ernest Lee
Repository: https://github.com/V-Sekai-fire/IPyHOP-temporal
"""
