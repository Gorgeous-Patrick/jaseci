"""SQLite-backed identity storage (declaration).

Kept in a separate module from the abstract IdentityStorage / Mongo backend
so that SQLAlchemy is only imported when this module is loaded. This matters
on free-threaded CPython, where SQLAlchemy 2.0's Cython extensions re-enable
the GIL on import. Mongo-only deployments never load this module and keep
the GIL disabled.
"""
import from sqlalchemy {
    create_engine,
    Engine,
    MetaData,
    Table,
    Column,
    String,
    Integer,
    JSON,
    ForeignKey,
    PrimaryKeyConstraint,
    select,
    delete,
    update
}
import from sqlalchemy.exc { IntegrityError }
import from datetime { datetime, UTC }
import from jac_scale.identity_storage { IdentityStorage, IdentityTakenError }
import from jaclang.jac0core.constant { Constants as Con }

"""SQLite-backed identity storage."""
obj SqliteIdentityStorage(IdentityStorage) {
    has db_path: str,
        _engine: Engine by postinit,
        _table: Table by postinit,
        _identity_lookups: Table by postinit,
        _sso_lookups: Table by postinit;

    def postinit -> None;
    # Abstract primitives
    def _store_user(user_doc: dict[str, any]) -> None;
    def _update_fields(user_id: str, fields: dict[str, any]) -> bool;
    def _get_credentials(user_id: str) -> list[dict[str, any]];
    def _update_credentials(user_id: str, credentials: list[dict[str, any]]) -> None;
    def _get_identities(user_id: str) -> list[dict[str, any]];
    def _add_identity(user_id: str, identity: dict[str, any]) -> bool;
    def _remove_sso_identity(user_id: str, platform: str) -> bool;
    def _find_sso_link(platform: str, external_id: str) -> dict[str, any] | None;
    def _set_identity_verified(user_id: str, value_normalized: str) -> bool;
    def ensure_indexes -> None;
    # Public methods implemented directly
    def get_user_by_id(user_id: str) -> dict[str, any] | None;
    def delete_user(user_id: str) -> bool;
    def find_user_by_identity(value: str) -> dict[str, any] | None;
    def identity_taken(value: str) -> bool;
    def list_all_users(limit: int = 100, offset: int = 0) -> list[dict[str, any]];
    def get_user_by_sso(platform: str, external_id: str) -> dict[str, any] | None;
}
