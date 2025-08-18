"""Jac specific builtins."""

from __future__ import annotations

import json
from abc import abstractmethod
from enum import Enum
from typing import ClassVar, Optional, override

from jaclang.runtimelib.constructs import NodeArchetype, Root
from jaclang.runtimelib.machine import JacMachineInterface as Jac


class AccessLevelEnum(Enum):
    """Access level constants for JAC objects."""

    NO_ACCESS = "NO_ACCESS"
    READ = "READ"
    CONNECT = "CONNECT"
    WRITE = "WRITE"


# Create module level constants for easier access
NoPerm = AccessLevelEnum.NO_ACCESS
ReadPerm = AccessLevelEnum.READ
ConnectPerm = AccessLevelEnum.CONNECT
WritePerm = AccessLevelEnum.WRITE


def printgraph(
    node: Optional[NodeArchetype] = None,
    depth: int = -1,
    traverse: bool = False,
    edge_type: Optional[list[str]] = None,
    bfs: bool = True,
    edge_limit: int = 512,
    node_limit: int = 512,
    file: Optional[str] = None,
    format: str = "dot",
) -> str:
    """Print the graph in different formats."""
    from jaclang.runtimelib.machine import JacMachineInterface as Jac

    fmt = format.lower()
    if fmt == "json":
        return _jac_graph_json(file)

    return Jac.printgraph(
        edge_type=edge_type,
        node=node or Jac.root(),
        depth=depth,
        traverse=traverse,
        bfs=bfs,
        edge_limit=edge_limit,
        node_limit=node_limit,
        file=file,
        format=fmt,
    )


jid = Jac.object_ref
jobj = Jac.get_object
grant = Jac.perm_grant
revoke = Jac.perm_revoke
allroots = Jac.get_all_root
save = Jac.save
commit = Jac.commit


def _jac_graph_json(file: Optional[str] = None) -> str:
    """Get the graph in json string."""
    processed: list[Root | NodeArchetype] = []
    nodes: list[dict] = []
    edges: list[dict] = []
    working_set: list[tuple] = []

    root = Jac.root()
    nodes.append({"id": id(root), "label": "root"})

    processed.append(root)
    working_set = [(root, ref) for ref in Jac.refs(root)]

    while working_set:
        start, end = working_set.pop(0)
        edges.append({"from": id(start), "to": id(end)})
        nodes.append({"id": id(end), "label": repr(end)})
        processed.append(end)
        for ref in Jac.refs(end):
            if ref not in processed:
                working_set.append((end, ref))
    output = json.dumps(
        {
            "version": "1.0",
            "nodes": nodes,
            "edges": edges,
        }
    )
    if file:
        with open(file, "w") as f:
            f.write(output)
    return output


__all__ = [
    "abstractmethod",
    "ClassVar",
    "override",
    "printgraph",
    "jid",
    "jobj",
    "grant",
    "revoke",
    "allroots",
    "save",
    "commit",
    "NoPerm",
    "ReadPerm",
    "ConnectPerm",
    "WritePerm",
]
