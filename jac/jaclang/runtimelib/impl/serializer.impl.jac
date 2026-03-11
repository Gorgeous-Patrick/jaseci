"""Helper: get type metadata dict."""
impl Serializer._type_info(`obj: object, `include: bool) -> dict[str, object] {
    return {
        '__type__': type(`obj).__name__,
        '__module__': type(`obj).__module__
    }
        if `include
        else {};
}

"""Helper: serialize object attributes (non-private, non-callable)."""
impl Serializer._serialize_attrs(
    `obj: object, include_type: bool, api_mode: bool
) -> dict[str, object] {
    return {
        a: Serializer._serialize_value(getattr(`obj, a), include_type, api_mode)
        for a in dir(`obj)
        if not a.startswith('_') and not callable(getattr(`obj, a, None))
    };
}

"""Serialize any object to JSON-compatible format."""
impl Serializer.serialize(
    `obj: object, include_type: bool = False, api_mode: bool = False
) -> object {
    return Serializer._serialize_value(`obj, include_type, api_mode);
}

"""Serialize a value recursively."""
impl Serializer._serialize_value(
    val: object, include_type: bool, api_mode: bool = False
) -> object {
    # Primitives & UUID & Enum
    if val is None or isinstance(val, (str, int, float, bool)) {
        return val;
    }
    if isinstance(val, UUID) {
        return str(val);
    }
    if isinstance(val, Enum) {
        return val.value;
    }
    # Collections
    if isinstance(val, (list, tuple)) {
        return [Serializer._serialize_value(v, include_type, api_mode) for v in val];
    }
    if isinstance(val, dict) {
        return {
            str(k): Serializer._serialize_value(v, include_type, api_mode)
            for (k, v) in val.items()
        };
    }
    # Access types
    if isinstance(val, Access) {
        return {'anchors': {str(k): v.value for (k, v) in val.anchors.items()}};
    }
    if isinstance(val, Permission) {
        return {
            'all': val.all.value,
            'roots': Serializer._serialize_value(val.roots, include_type, api_mode)
        };
    }
    # Anchor (NodeAnchor, EdgeAnchor)
    if isinstance(val, Anchor) {
        result = Serializer._type_info(val, include_type);
        result |= {
            'id': str(val.id),
            'root': str(val.root) if val.root else None,
            'persistent': val.persistent,
            'access': Serializer._serialize_value(val.access, include_type, api_mode)
        };
        # Serialize arch_cls for type-aware shortcircuit filtering.
        arch_cls_data = Serializer._serialize_arch_cls(val);
        if arch_cls_data is not None {
            result['arch_cls'] = arch_cls_data;
        }
        if val.is_populated() {
            arch = val.archetype;
            result['archetype'] = Serializer._type_info(arch, include_type) | Serializer._serialize_attrs(
                arch, include_type, api_mode
            );
        }
        if isinstance(val, NodeAnchor) {
            edges_out: list = [];
            for e in val.edges {
                entry: dict = {'id': str(e.id)};
                e_arch_cls = Serializer._serialize_arch_cls(e);
                if e_arch_cls is not None {
                    entry['arch_cls'] = e_arch_cls;
                }
                if (sid := e.__dict__.get('source_id')) {
                    entry['source_id'] = str(sid);
                }
                if (tid := e.__dict__.get('target_id')) {
                    entry['target_id'] = str(tid);
                }
                edges_out.append(entry);
            }
            result['edges'] = edges_out;
        }
        if isinstance(val, EdgeAnchor) {
            source_data: (dict | None) = None;
            target_data: (dict | None) = None;
            if val.source {
                source_data = {'id': str(val.source.id)};
                s_arch_cls = Serializer._serialize_arch_cls(val.source);
                if s_arch_cls is not None {
                    source_data['arch_cls'] = s_arch_cls;
                }
            }
            if val.target {
                target_data = {'id': str(val.target.id)};
                t_arch_cls = Serializer._serialize_arch_cls(val.target);
                if t_arch_cls is not None {
                    target_data['arch_cls'] = t_arch_cls;
                }
            }
            result |= {
                'source': source_data,
                'target': target_data,
                'is_undirected': val.is_undirected
            };
        }
        return result;
    }
    # Archetype (standalone)
    if isinstance(val, Archetype) {
        result = Serializer._type_info(val, include_type);
        if api_mode {
            result |= {
                '_jac_type': type(val).__name__,
                '_jac_id': val.__jac__.id.hex if val?.__jac__ else None,
                '_jac_archetype': 'node'
                    if isinstance(val, NodeArchetype)
                    else 'walker' if isinstance(val, WalkerArchetype) else 'archetype'
            };
        }
        return result | Serializer._serialize_attrs(val, include_type, api_mode);
    }
    # Generic object with __dict__
    if val?.__dict__ {
        result = Serializer._type_info(val, include_type);
        for (k, v) in val.__dict__.items() {
            if not k.startswith('_') {
                result[k] = Serializer._serialize_value(v, include_type, api_mode);
            }
        }
        return result;
    }
    logger.warning(
        f"Falling back to str() for {type(val).__module__}.{type(val).__name__}"
    );
    return str(val);
}

"""Deserialize data back to original object type."""
impl Serializer.deserialize(data: dict[str, object]) -> (object | None) {
    if not isinstance(data, dict) {
        return data;
    }
    type_name = data.get('__type__');
    if not type_name {
        return {k: Serializer._deserialize_value(v) for (k, v) in data.items()};
    }
    dispatch = {
        'Anchor': Serializer._deserialize_anchor,
        'NodeAnchor': Serializer._deserialize_anchor,
        'EdgeAnchor': Serializer._deserialize_anchor,
        'Permission': Serializer._deserialize_permission,
        'Access': Serializer._deserialize_access
    };
    if (handler := dispatch.get(type_name)) {
        return handler(data);
    }
    # Reconstruct from registry
    if (cls := Serializer._get_class(data.get('__module__'), type_name)) {
        try {
            instance = cls.__new__(cls);
            for (k, v) in data.items() {
                if not k.startswith('__') {
                    setattr(instance, k, Serializer._deserialize_value(v));
                }
            }
            return instance;
        } except Exception as e {
            logger.error(f"Failed to deserialize {type_name}: {e}");
        }
    }
    return None;
}

"""Deserialize a value recursively."""
impl Serializer._deserialize_value(val: object) -> object {
    if val is None or isinstance(val, (str, int, float, bool)) {
        return val;
    }
    if isinstance(val, list) {
        return [Serializer._deserialize_value(v) for v in val];
    }
    if isinstance(val, dict) {
        return Serializer.deserialize(val)
            if '__type__' in val
            else {k: Serializer._deserialize_value(v) for (k, v) in val.items()};
    }
    return val;
}

"""Register a class for safe deserialization."""
impl Serializer.register(cls: type) -> None {
    Serializer._registry[f"{cls.__module__}.{cls.__name__}"] = cls;
}

"""Look up a class by module.name (only registered classes for security)."""
impl Serializer._get_class(module_name: str, class_name: str) -> (type | None) {
    if not module_name or not class_name {
        return None;
    }
    key = f"{module_name}.{class_name}";
    if not (cls := Serializer._registry.get(key)) {
        logger.warning(f"Refused to deserialize unregistered class: {key}");
    }
    return cls;
}

"""Helper: Convert string ID to unpopulated anchor stub, optionally restoring arch_cls."""
impl Serializer._id_to_stub(
    anchor_cls: type, id_str: str,
    arch_cls_data: (list | None) = None
) -> (Anchor | None) {
    try {
        stub = anchor_cls.__new__(anchor_cls);
        stub.id = UUID(id_str);
        if arch_cls_data is not None {
            stub.__dict__['arch_cls'] = Serializer._deserialize_arch_cls(arch_cls_data);
        }
        return stub;
    } except Exception as e {
        logger.error(
            f"Failed to create stub for {anchor_cls.__name__} with id {id_str}: {e}"
        );
        return None;
    }
}

"""Serialize arch_cls frozenset[TypeRef] to JSON-compatible list."""
impl Serializer._serialize_arch_cls(anchor: Anchor) -> (list | None) {
    arch_cls = anchor.__dict__.get('arch_cls');
    if arch_cls is None {
        return None;
    }
    return [{'module': ref.module, 'qualname': ref.qualname} for ref in arch_cls];
}

"""Deserialize arch_cls list of dicts back to frozenset[TypeRef]."""
impl Serializer._deserialize_arch_cls(data: list) -> frozenset[TypeRef] {
    return frozenset(
        TypeRef(module=item['module'], qualname=item['qualname'])
        for item in data
        if isinstance(item, dict) and 'module' in item and 'qualname' in item
    );
}

"""Deserialize Anchor (Node/Edge)."""
impl Serializer._deserialize_anchor(data: dict[str, object]) -> (Anchor | None) {
    anchor_cls = {'NodeAnchor': NodeAnchor, 'EdgeAnchor': EdgeAnchor}.get(
        data.get('__type__', ''), Anchor
    );
    try {
        anchor = anchor_cls.__new__(anchor_cls);
        anchor.id = UUID(data['id']) if data.get('id') else None;
        anchor.root = UUID(data['root']) if data.get('root') else None;
        anchor.persistent = data.get('persistent', False);
        anchor.access = Serializer._deserialize_permission(data.get('access'));

        # Restore arch_cls on the anchor itself.
        if (arch_cls_data := data.get('arch_cls')) {
            anchor.__dict__['arch_cls'] = Serializer._deserialize_arch_cls(arch_cls_data);
        }

        if (arch_data := data.get('archetype')) {
            anchor.archetype = Serializer._deserialize_archetype(arch_data, anchor);
            # For populated anchors, compute arch_cls from the live class if not already set.
            if 'arch_cls' not in anchor.__dict__ {
                chain = build_type_chain(type(anchor.archetype));
                if chain is not None {
                    anchor.__dict__['arch_cls'] = chain;
                }
            }
        }
        if isinstance(anchor, NodeAnchor) {
            # Restore edges — supports both new dict format and old bare-string format.
            raw_edges = data.get('edges');
            if not raw_edges {
                anchor.edges = [];
            } else {
                edges = [];
                for entry in raw_edges {
                    if isinstance(entry, dict) {
                        # New format: {"id": "...", "arch_cls": [...], "source_id": "...", "target_id": "..."}
                        eid = entry.get('id', '');
                        e_arch = entry.get('arch_cls');
                        if (stub := Serializer._id_to_stub(EdgeAnchor, eid, e_arch)) {
                            if (sid := entry.get('source_id')) {
                                stub.__dict__['source_id'] = UUID(sid);
                            }
                            if (tid := entry.get('target_id')) {
                                stub.__dict__['target_id'] = UUID(tid);
                            }
                            edges.append(stub);
                        }
                    } elif isinstance(entry, str) {
                        # Old format: bare UUID string
                        if (stub := Serializer._id_to_stub(EdgeAnchor, entry)) {
                            edges.append(stub);
                        }
                    }
                }
                anchor.edges = edges;
            }
        }
        if isinstance(anchor, EdgeAnchor) {
            anchor.is_undirected = data.get('is_undirected', False);
            # Restore source — supports both new dict format and old bare-string format.
            source_raw = data.get('source');
            if source_raw is not None {
                if isinstance(source_raw, dict) {
                    s_id = source_raw.get('id', '');
                    s_arch = source_raw.get('arch_cls');
                    anchor.source = Serializer._id_to_stub(NodeAnchor, s_id, s_arch);
                    anchor.__dict__['source_id'] = UUID(s_id);
                } elif isinstance(source_raw, str) {
                    anchor.source = Serializer._id_to_stub(NodeAnchor, source_raw);
                    anchor.__dict__['source_id'] = UUID(source_raw);
                }
            }
            # Restore target — supports both new dict format and old bare-string format.
            target_raw = data.get('target');
            if target_raw is not None {
                if isinstance(target_raw, dict) {
                    t_id = target_raw.get('id', '');
                    t_arch = target_raw.get('arch_cls');
                    anchor.target = Serializer._id_to_stub(NodeAnchor, t_id, t_arch);
                    anchor.__dict__['target_id'] = UUID(t_id);
                } elif isinstance(target_raw, str) {
                    anchor.target = Serializer._id_to_stub(NodeAnchor, target_raw);
                    anchor.__dict__['target_id'] = UUID(target_raw);
                }
            }
        }
        return anchor;
    } except Exception as e {
        logger.error(f"Failed to deserialize anchor: {e}");
        return None;
    }
}

"""Deserialize Permission."""
impl Serializer._deserialize_permission(data: object) -> Permission {
    if not isinstance(data, dict) {
        return Permission();
    }
    perm = Permission();
    perm.all = AccessLevel(data.get('all', -1));
    if (roots := data.get('roots')) {
        perm.roots = Serializer._deserialize_access(roots);
    }
    return perm;
}

"""Deserialize Access."""
impl Serializer._deserialize_access(data: object) -> Access {
    if not isinstance(data, dict) {
        return Access();
    }
    access = Access();
    if (anchors := data.get('anchors')) {
        access.anchors = {k: AccessLevel(v) for (k, v) in anchors.items()};
    }
    return access;
}

"""Deserialize Archetype."""
impl Serializer._deserialize_archetype(
    data: dict[str, object], anchor: Anchor
) -> (object | None) {
    type_name = data.get('__type__');
    module_name = data.get('__module__');
    if not type_name or not module_name {
        return None;
    }
    cls = Serializer._get_class(module_name, type_name);
    if not cls {
        return None;
    }
    try {
        arch = cls.__new__(cls);
        for (k, v) in data.items() {
            if not k.startswith('__') {
                setattr(arch, k, Serializer._deserialize_value(v));
            }
        }
        arch.__jac__ = anchor;
        return arch;
    } except Exception as e {
        logger.error(f"Failed to deserialize archetype {type_name}: {e}");
        return None;
    }
}
