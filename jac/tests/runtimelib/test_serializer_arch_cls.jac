"""Tests for arch_cls preservation through JSON serialization round-trips."""

import from jaclang.runtimelib.serializer { Serializer }
import from jaclang.jac0core.archetype {
    NodeAnchor,
    EdgeAnchor,
    Permission,
    TypeRef,
    build_type_chain
}
import from uuid { uuid4 }

# --- _serialize_arch_cls / _deserialize_arch_cls ---

test "_serialize_arch_cls returns None when no arch_cls" {
    stub = EdgeAnchor.__new__(EdgeAnchor);
    stub.id = uuid4();
    assert Serializer._serialize_arch_cls(stub) is None;
}

test "_serialize_arch_cls round-trips through _deserialize_arch_cls" {
    refs = frozenset([
        TypeRef(module='a.b', qualname='Edge1'),
        TypeRef(module='c.d', qualname='Edge2')
    ]);
    stub = EdgeAnchor.__new__(EdgeAnchor);
    stub.id = uuid4();
    stub.__dict__['arch_cls'] = refs;

    serialized = Serializer._serialize_arch_cls(stub);
    assert serialized is not None;
    assert len(serialized) == 2;

    deserialized = Serializer._deserialize_arch_cls(serialized);
    assert deserialized == refs;
}

# --- _id_to_stub with arch_cls ---

test "_id_to_stub with arch_cls_data sets arch_cls on stub" {
    arch_data = [
        {'module': 'test.mod', 'qualname': 'MyEdge'},
        {'module': 'test.mod', 'qualname': 'BaseEdge'}
    ];
    eid = uuid4();
    stub = Serializer._id_to_stub(EdgeAnchor, str(eid), arch_data);
    assert stub is not None;
    assert stub.id == eid;
    assert 'arch_cls' in stub.__dict__;
    assert len(stub.__dict__['arch_cls']) == 2;
    assert TypeRef(module='test.mod', qualname='MyEdge') in stub.__dict__['arch_cls'];
}

test "_id_to_stub without arch_cls_data has no arch_cls" {
    eid = uuid4();
    stub = Serializer._id_to_stub(EdgeAnchor, str(eid));
    assert stub is not None;
    assert 'arch_cls' not in stub.__dict__;
}

# --- Anchor-level arch_cls serialize/deserialize ---

test "serialize and deserialize arch_cls on NodeAnchor" {
    refs = frozenset([
        TypeRef(module='test.mod', qualname='MyNode'),
        TypeRef(module='test.mod', qualname='BaseNode')
    ]);
    nd = NodeAnchor.__new__(NodeAnchor);
    nd.id = uuid4();
    nd.root = uuid4();
    nd.persistent = False;
    nd.access = Permission();
    nd.edges = [];
    nd.__dict__['arch_cls'] = refs;

    serialized = Serializer.serialize(nd, include_type=True);
    deserialized = Serializer.deserialize(serialized);

    assert 'arch_cls' in deserialized.__dict__;
    assert deserialized.__dict__['arch_cls'] == refs;
}

# --- Edge list new dict format ---

test "NodeAnchor edges with arch_cls restored from new dict format" {
    refs = [{'module': 'test.mod', 'qualname': 'MyEdge'}];
    e1_id = uuid4();
    e2_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'NodeAnchor',
            'id': str(uuid4()),
            'root': str(uuid4()),
            'edges': [
                {'id': str(e1_id), 'arch_cls': refs},
                {'id': str(e2_id)}
            ]
        }
    );
    assert len(anchor.edges) == 2;
    # Edge with arch_cls
    assert anchor.edges[0].id == e1_id;
    assert 'arch_cls' in anchor.edges[0].__dict__;
    expected_ref = TypeRef(module='test.mod', qualname='MyEdge');
    assert expected_ref in anchor.edges[0].__dict__['arch_cls'];
    # Edge without arch_cls
    assert anchor.edges[1].id == e2_id;
    assert 'arch_cls' not in anchor.edges[1].__dict__;
}

# --- Edge list backward compat (old bare-string format) ---

test "NodeAnchor edges backward compat with old bare-string format" {
    e1_id = uuid4();
    e2_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'NodeAnchor',
            'id': str(uuid4()),
            'root': str(uuid4()),
            'edges': [str(e1_id), str(e2_id)]
        }
    );
    assert len(anchor.edges) == 2;
    assert anchor.edges[0].id == e1_id;
    assert anchor.edges[1].id == e2_id;
    assert 'arch_cls' not in anchor.edges[0].__dict__;
}

# --- EdgeAnchor source/target new dict format ---

test "EdgeAnchor source/target with arch_cls from new dict format" {
    src_id = uuid4();
    tgt_id = uuid4();
    src_refs = [{'module': 'test.mod', 'qualname': 'SrcNode'}];
    tgt_refs = [{'module': 'test.mod', 'qualname': 'TgtNode'}];
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'EdgeAnchor',
            'id': str(uuid4()),
            'source': {'id': str(src_id), 'arch_cls': src_refs},
            'target': {'id': str(tgt_id), 'arch_cls': tgt_refs}
        }
    );
    assert anchor.source.id == src_id;
    assert 'arch_cls' in anchor.source.__dict__;
    assert TypeRef(module='test.mod', qualname='SrcNode') in anchor.source.__dict__['arch_cls'];
    assert anchor.target.id == tgt_id;
    assert 'arch_cls' in anchor.target.__dict__;
    assert TypeRef(module='test.mod', qualname='TgtNode') in anchor.target.__dict__['arch_cls'];
}

# --- EdgeAnchor source/target backward compat ---

test "EdgeAnchor source/target backward compat with old bare-string format" {
    src_id = uuid4();
    tgt_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'EdgeAnchor',
            'id': str(uuid4()),
            'source': str(src_id),
            'target': str(tgt_id)
        }
    );
    assert anchor.source.id == src_id;
    assert 'arch_cls' not in anchor.source.__dict__;
    assert anchor.target.id == tgt_id;
    assert 'arch_cls' not in anchor.target.__dict__;
}

# --- Full round-trip: serialize then deserialize preserves everything ---

test "full NodeAnchor serialize-deserialize preserves edge arch_cls" {
    node_refs = frozenset([TypeRef(module='test.mod', qualname='MyNode')]);
    edge_refs = frozenset([TypeRef(module='test.mod', qualname='MyEdge')]);

    e1 = EdgeAnchor.__new__(EdgeAnchor);
    e1.id = uuid4();
    e1.__dict__['arch_cls'] = edge_refs;

    e2 = EdgeAnchor.__new__(EdgeAnchor);
    e2.id = uuid4();

    nd = NodeAnchor.__new__(NodeAnchor);
    nd.id = uuid4();
    nd.root = uuid4();
    nd.persistent = False;
    nd.access = Permission();
    nd.edges = [e1, e2];
    nd.__dict__['arch_cls'] = node_refs;

    serialized = Serializer.serialize(nd, include_type=True);
    deserialized = Serializer.deserialize(serialized);

    # Anchor arch_cls preserved
    assert deserialized.__dict__['arch_cls'] == node_refs;
    # Edge with arch_cls preserved
    assert 'arch_cls' in deserialized.edges[0].__dict__;
    assert deserialized.edges[0].__dict__['arch_cls'] == edge_refs;
    # Edge without arch_cls stays clean
    assert 'arch_cls' not in deserialized.edges[1].__dict__;
}

# --- Direction shortcircuit: source_id / target_id on edge stubs ---

test "edge stub stores source_id and target_id via __dict__" {
    src_id = uuid4();
    tgt_id = uuid4();
    e = EdgeAnchor.__new__(EdgeAnchor);
    e.id = uuid4();
    e.__dict__['source_id'] = src_id;
    e.__dict__['target_id'] = tgt_id;

    assert e.__dict__['source_id'] == src_id;
    assert e.__dict__['target_id'] == tgt_id;
}

test "NodeAnchor edges with source_id/target_id from new dict format" {
    src_id = uuid4();
    tgt_id = uuid4();
    e1_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'NodeAnchor',
            'id': str(uuid4()),
            'root': str(uuid4()),
            'edges': [
                {
                    'id': str(e1_id),
                    'source_id': str(src_id),
                    'target_id': str(tgt_id)
                }
            ]
        }
    );
    assert len(anchor.edges) == 1;
    assert anchor.edges[0].id == e1_id;
    assert anchor.edges[0].__dict__['source_id'] == src_id;
    assert anchor.edges[0].__dict__['target_id'] == tgt_id;
}

test "NodeAnchor edges backward compat without source_id/target_id" {
    e1_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'NodeAnchor',
            'id': str(uuid4()),
            'root': str(uuid4()),
            'edges': [{'id': str(e1_id)}]
        }
    );
    assert len(anchor.edges) == 1;
    assert 'source_id' not in anchor.edges[0].__dict__;
    assert 'target_id' not in anchor.edges[0].__dict__;
}

test "EdgeAnchor deserialize stores source_id/target_id from dict format" {
    src_id = uuid4();
    tgt_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'EdgeAnchor',
            'id': str(uuid4()),
            'source': {'id': str(src_id)},
            'target': {'id': str(tgt_id)}
        }
    );
    assert anchor.__dict__['source_id'] == src_id;
    assert anchor.__dict__['target_id'] == tgt_id;
}

test "EdgeAnchor deserialize stores source_id/target_id from bare-string format" {
    src_id = uuid4();
    tgt_id = uuid4();
    anchor = Serializer._deserialize_anchor(
        {
            '__type__': 'EdgeAnchor',
            'id': str(uuid4()),
            'source': str(src_id),
            'target': str(tgt_id)
        }
    );
    assert anchor.__dict__['source_id'] == src_id;
    assert anchor.__dict__['target_id'] == tgt_id;
}

test "full NodeAnchor serialize-deserialize preserves edge source_id/target_id" {
    src_id = uuid4();
    tgt_id = uuid4();
    edge_refs = frozenset([TypeRef(module='test.mod', qualname='MyEdge')]);

    e1 = EdgeAnchor.__new__(EdgeAnchor);
    e1.id = uuid4();
    e1.__dict__['arch_cls'] = edge_refs;
    e1.__dict__['source_id'] = src_id;
    e1.__dict__['target_id'] = tgt_id;

    nd = NodeAnchor.__new__(NodeAnchor);
    nd.id = uuid4();
    nd.root = uuid4();
    nd.persistent = False;
    nd.access = Permission();
    nd.edges = [e1];

    serialized = Serializer.serialize(nd, include_type=True);
    deserialized = Serializer.deserialize(serialized);

    # source_id / target_id preserved on edge stub
    assert deserialized.edges[0].__dict__['source_id'] == src_id;
    assert deserialized.edges[0].__dict__['target_id'] == tgt_id;
    # arch_cls also preserved
    assert deserialized.edges[0].__dict__['arch_cls'] == edge_refs;
}
