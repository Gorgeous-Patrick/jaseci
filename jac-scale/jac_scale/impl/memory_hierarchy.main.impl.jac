"""ScaleTieredMemory Implementation - Multi-tier storage coordination.

Storage configuration comes from environment variables or jac.toml.
"""

"""Initialize ScaleTieredMemory with distributed backends."""
impl ScaleTieredMemory.postinit -> None {
    # L1: Initialize volatile memory (inherited from VolatileMemory via TieredMemory)
    import threading;
    self.__mem__ = {};
    self.__raw__ = {};
    self._raw_lock = threading.Lock();
    self.__gc__ = set();
    # L2: Try to initialize Redis cache (replaces LocalCacheMemory)
    redis_backend = RedisBackend();
    self._cache_available = redis_backend.is_available();
    if self._cache_available and self.use_cache {
        self.l2 = redis_backend;
        logger.debug("Redis cache backend initialized");
    } else {
        self.l2 = None;
        logger.debug("Redis not available, running without distributed cache");
    }
    # L3: Try MongoDB first (replaces SqliteMemory), fall back to SqliteMemory
    mongo_backend = MongoBackend();
    if mongo_backend.is_available() {
        self.l3 = mongo_backend;
        # Give MongoDB access to L1 memory for sync()
        mongo_backend.set_memory_ref(self.__mem__);
        # Give MongoDB access to L2 cache so quarantine ops can invalidate Redis
        mongo_backend.set_cache_ref(self.l2);
        self._persistence_type = PersistenceType.MONGODB;
        logger.debug("MongoDB persistence backend initialized");
        # Show subtle message (optional - uncomment to enable)
        try {
            import from jaclang.cli.console { console }
            logger.debug("  ✔ Using MongoDB for persistence", style="muted");
        } except Exception { }
    } else {
        # Fall back to jaclang's SqliteMemory using configured path
        self.l3 = SqliteMemory(
            path=get_scale_config().get_database_config()['shelf_db_path']
        );
        self._persistence_type = PersistenceType.SQLITE;
        logger.debug("MongoDB not available, using SqliteMemory for persistence");
        # Show subtle message
        try {
            import from jaclang.cli.console { console }
            logger.debug("  ✔ Using SQLite for persistence", style="muted");
        } except Exception { }
    }
}


"""Commit changes: delegate to L3's sync() which handles change detection
and merge-aware atomic writes."""
impl ScaleTieredMemory.commit(anchor: (Anchor | None) = None) -> None {
    if self.l3 is None {
        return;
    }
    # Both single-anchor and batch commits go through sync() to ensure
    # all writes use merge-aware paths (no direct L3 put bypass).
    # Capture L2-pending anchors BEFORE L3 sync (which updates hashes).
    if self.l3 {
        try {
            l2_pending = [];
            if self.l2 {
                l2_pending = [
                    mem_anchor
                    for (_, mem_anchor) in list(self.__mem__.items())
                    if mem_anchor.persistent
                    and Serializer._compute_hash(mem_anchor) != mem_anchor.hash
                    and Jac.check_write_access(mem_anchor)
                ];
            }
            atomic_ids = self.l3.sync() or set();
            if self.l2 {
                for mem_anchor in l2_pending {
                    if mem_anchor.id in atomic_ids {
                        continue;
                    }
                    try {
                        self.l2.put(mem_anchor);
                    } except Exception as l2_err {
                        logger.warning(f"L2 cache update failed: {l2_err}");
                    }
                }
            }
        } except Exception as e {
            logger.warning(f"ScaleTieredMemory.commit sync failed: {e}");
        }
    }
}

"""Batch get with full tiered read-through: L1 → L2 MGET → L3 $in."""
impl ScaleTieredMemory.batch_get(ids: list[UUID]) -> dict[UUID, Anchor] {
    import from jaclang.runtimelib.memory { _tiered_access_log }
    import os as _os;
    result: dict[UUID, Anchor] = {};
    l1_misses: list[UUID] = [];
    for id in ids {
        if (anchor := self.__mem__.get(id)) {
            result[id] = anchor;
            _tiered_access_log(id, "L1", anchor);
        } else {
            anchor = self.promote_raw(id);
            if anchor is not None {
                result[id] = anchor;
                _tiered_access_log(id, "L1", anchor);
                continue;
            }
            l1_misses.append(id);
        }
    }
    if not l1_misses {
        return result;
    }
    # --- Hybrid TTG-Prefetcher wait -----------------------------------------
    # If a TTG plan is being populated in the background, wait briefly for
    # the plan to land bytes for the in-plan IDs we still need, then
    # re-check `__raw__` via `promote_raw`.  IDs not in the plan fall
    # through to the L2/L3 batch path immediately — preserves baseline
    # behaviour when TTG is disabled or a request is outside the plan.
    _pf_done = self?._prefetch_done;
    _pf_ids = self?._prefetch_ids;
    if _pf_done is not None and _pf_ids is not None {
        _in_plan: list[UUID] = [];
        _not_in_plan: list[UUID] = [];
        for id in l1_misses {
            if id in _pf_ids {
                _in_plan.append(id);
            } else {
                _not_in_plan.append(id);
            }
        }
        if _in_plan and not _pf_done.is_set() {
            try {
                _wait_ms = int(_os.environ.get('JAC_PREFETCH_WAIT_MS', '50'));
            } except (TypeError, ValueError) {
                _wait_ms = 50;
            }
            if _wait_ms > 0 {
                _pf_done.wait(timeout=_wait_ms / 1000.0);
            }
        }
        _still_missing: list[UUID] = [];
        for id in _in_plan {
            anchor = self.promote_raw(id);
            if anchor is not None {
                result[id] = anchor;
                _tiered_access_log(id, "L1", anchor);
            } else {
                _still_missing.append(id);
            }
        }
        l1_misses = _still_missing + _not_in_plan;
        if not l1_misses {
            return result;
        }
    }
    # --- end hybrid wait -----------------------------------------------------
    # L2: Redis MGET for L1 misses
    l2_misses: list[UUID] = [];
    if self.l2 and hasattr(self.l2, 'batch_get') {
        l2_results = self.l2.batch_get(l1_misses);
        for id in l1_misses {
            if id in l2_results {
                anchor = l2_results[id];
                self.__mem__[id] = anchor;
                result[id] = anchor;
                _tiered_access_log(id, "L2", anchor);
            } else {
                l2_misses.append(id);
            }
        }
    } else {
        l2_misses = l1_misses;
    }
    # L3: MongoDB $in (or SqliteMemory fallback) for L2 misses
    if l2_misses and self.l3 {
        l3_results: dict[UUID, Anchor] = {};
        if hasattr(self.l3, 'batch_get') {
            l3_results = self.l3.batch_get(l2_misses);
        } else {
            for mid in l2_misses {
                if (a := self.l3.get(mid)) {
                    l3_results[mid] = a;
                }
            }
        }
        for (id, anchor) in l3_results.items() {
            self.__mem__[id] = anchor;
            if self.l2 {
                try {
                    self.l2.put(anchor);
                } except Exception { }
            }
            result[id] = anchor;
            _tiered_access_log(id, "L3", anchor);
        }
        for mid in l2_misses {
            if mid not in l3_results {
                _tiered_access_log(mid, "MISS");
            }
        }
    }
    return result;
}

"""Async commit: offload to thread so delta-merge and L2 update are correct.

MongoBackend.acommit uses a plain bulk_write (last-writer-wins), which
bypasses the delta-merge _put_node_atomic path in sync(). Using
asyncio.to_thread(self.commit) keeps the event loop free while still
running the correct merge-aware sync() + L2 update.
"""
impl ScaleTieredMemory.acommit(anchor: (Anchor | None) = None) -> None {
    import asyncio;
    if anchor is None and self._committed {
        return;
    }
    await asyncio.to_thread(self.commit, anchor);
    if anchor is None {
        self._committed = True;
    }
}

"""Prefetch anchors into L1. Skips field-hash snapshotting — unmodified
anchors are skipped at commit via _compute_hash; modified ones fall back
to a full document write (correct, just not partial-field optimized)."""
impl ScaleTieredMemory.prefetch(ids: Iterable[UUID]) -> None {
    super.prefetch(ids);
}

"""Close all backends."""
impl ScaleTieredMemory.close -> None {
    self.commit();
    if self.l3 {
        self.l3.close();
    }
    if self.l2 {
        self.l2.close();
    }
    self.__mem__.clear();
    self.__raw__.clear();
    self.__gc__.clear();
}
