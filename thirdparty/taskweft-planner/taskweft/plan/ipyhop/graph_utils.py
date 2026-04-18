#!/usr/bin/env python
"""
File Description: Pure Python stdlib-based graph utilities to replace networkx.
Provides DiGraph-like class and graph algorithms using only stdlib.
"""

from typing import Dict, List, Set, Any, Iterator


class DiGraph:
    """
    Directed Graph implementation using pure Python stdlib.
    Mimics the basic API of networkx.DiGraph for compatibility.
    """

    def __init__(self):
        """Initialize an empty directed graph."""
        self._nodes: Dict[Any, Dict[str, Any]] = {}
        self._edges: Dict[Any, List[Any]] = {}
        self._predecessors: Dict[Any, List[Any]] = {}

    def add_node(self, node_id: Any, **attrs) -> None:
        """Add a node with optional attributes."""
        if node_id not in self._nodes:
            self._nodes[node_id] = {}
            self._edges[node_id] = []
            self._predecessors[node_id] = []
        # Update or add attributes
        self._nodes[node_id].update(attrs)

    def add_edge(self, u: Any, v: Any) -> None:
        """Add an edge from node u to node v."""
        if u not in self._nodes:
            self.add_node(u)
        if v not in self._nodes:
            self.add_node(v)
        if v not in self._edges[u]:
            self._edges[u].append(v)
        if u not in self._predecessors[v]:
            self._predecessors[v].append(u)

    def remove_nodes_from(self, nodes: List[Any]) -> None:
        """Remove multiple nodes from the graph."""
        for node in nodes:
            self.remove_node(node)

    def remove_node(self, node: Any) -> None:
        """Remove a node from the graph."""
        if node not in self._nodes:
            return

        # Remove edges from this node
        for successor in self._edges[node]:
            if node in self._predecessors[successor]:
                self._predecessors[successor].remove(node)

        # Remove edges to this node
        for predecessor in self._predecessors[node]:
            if node in self._edges[predecessor]:
                self._edges[predecessor].remove(node)

        # Remove the node itself
        del self._nodes[node]
        del self._edges[node]
        del self._predecessors[node]

    def successors(self, node: Any) -> Iterator[Any]:
        """Return an iterator of successor nodes."""
        if node in self._edges:
            return iter(self._edges[node])
        return iter([])

    def predecessors(self, node: Any) -> Iterator[Any]:
        """Return an iterator of predecessor nodes."""
        if node in self._predecessors:
            return iter(self._predecessors[node])
        return iter([])

    def subgraph(self, nodes: List[Any]) -> "DiGraph":
        """Return a subgraph containing only the specified nodes."""
        node_set = set(nodes)
        new_graph = DiGraph()

        # Add nodes with their attributes
        for node in nodes:
            if node in self._nodes:
                new_graph.add_node(node, **self._nodes[node])

        # Add edges that exist between nodes in the subgraph
        for u in nodes:
            if u in self._edges:
                for v in self._edges[u]:
                    if v in node_set:
                        new_graph.add_edge(u, v)

        return new_graph

    @property
    def nodes(self) -> Dict[Any, Dict[str, Any]]:
        """Return a dict-like view of nodes with their attributes."""
        return self._nodes

    def __iter__(self):
        """Iterate over nodes."""
        return iter(self._nodes)


def dfs_preorder_nodes(graph: DiGraph, source: Any) -> Iterator[Any]:
    """
    Perform depth-first search from source, returning nodes in preorder.
    Mimics networkx.dfs_preorder_nodes.
    """
    visited: Set[Any] = set()
    stack: List[Any] = [source]

    while stack:
        node = stack.pop()
        if node not in visited:
            visited.add(node)
            yield node
            # Add successors to stack in reverse order for correct DFS order
            successors = list(graph.successors(node))
            stack.extend(reversed(successors))


def descendants(graph: DiGraph, node: Any) -> Set[Any]:
    """
    Return all descendants of a node in the graph.
    Mimics networkx.descendants.
    """
    visited: Set[Any] = set()
    stack: List[Any] = list(graph.successors(node))

    while stack:
        current = stack.pop()
        if current not in visited:
            visited.add(current)
            stack.extend(graph.successors(current))

    return visited


def is_tree(graph: DiGraph) -> bool:
    """
    Check if the graph is a tree (connected acyclic directed graph).
    Mimics networkx.is_tree.

    A directed graph is a tree if:
    - It is weakly connected (connected if edges were undirected)
    - It has no cycles
    - It has n-1 edges for n nodes (for a connected DAG)
    """
    if not graph.nodes:
        return True

    n_nodes = len(graph.nodes)
    n_edges = sum(len(list(graph.successors(node))) for node in graph.nodes)

    # A tree must have exactly n-1 edges
    if n_edges != n_nodes - 1:
        return False

    # Check for cycles using DFS
    if _has_cycle(graph):
        return False

    return True


def _has_cycle(graph: DiGraph) -> bool:
    """Check if a directed graph has a cycle using DFS."""
    visited: Set[Any] = set()
    rec_stack: Set[Any] = set()

    def _dfs_cycle(node: Any) -> bool:
        visited.add(node)
        rec_stack.add(node)

        for neighbor in graph.successors(node):
            if neighbor not in visited:
                if _dfs_cycle(neighbor):
                    return True
            elif neighbor in rec_stack:
                return True

        rec_stack.remove(node)
        return False

    for node in graph.nodes:
        if node not in visited:
            if _dfs_cycle(node):
                return True

    return False


# ******************************************    Demo / Test Routine         ****************************************** #
if __name__ == "__main__":
    # Simple test
    g = DiGraph()
    g.add_node(0, info="root", type="D")
    g.add_node(1, info="task1", type="T")
    g.add_node(2, info="task2", type="T")
    g.add_edge(0, 1)
    g.add_edge(0, 2)

    print("Nodes:", list(g.nodes.keys()))
    print("Successors of 0:", list(g.successors(0)))
    print("DFS preorder:", list(dfs_preorder_nodes(g, 0)))
    print("Descendants of 0:", descendants(g, 0))
    print("Is tree:", is_tree(g))
