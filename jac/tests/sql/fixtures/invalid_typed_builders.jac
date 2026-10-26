"""Constructor argument contracts enforced by the static checker."""
import jaclang.sql as s;

with entry {
    optional = s.param(s.nullable(s.int64_type()), None);
    optional_text = s.param(s.nullable(s.text_type()), None);
    source = s.table('people', [s.field('n', s.int64_type())]);
    s.add(s.text('a'), s.text('b'));  # invalid
    s.sub(s.text('a'), s.int64(1));  # invalid
    s.and_([s.int64(1)]);  # invalid
    s.or_([s.int64(1)]);  # invalid
    s.and_nullable([s.int64(1)]);  # invalid
    s.or_nullable([s.int64(1)]);  # invalid
    s.not_(s.text('a'));  # invalid
    s.not_nullable(s.boolean(True));  # invalid
    s.is_null(s.int64(1));  # invalid
    s.eq_nullable(optional, optional_text);  # invalid
    s.coalesce(optional, s.text('a'));  # invalid
    s.sum_(s.int64(1));  # invalid
    s.sum_int32(s.int64(1));  # invalid
    s.sum_int64(s.text('a'));  # invalid
    s.sum_numeric(s.int64(1));  # invalid
    s.bool_and(s.int64(1));  # invalid
    s.bool_or(s.int64(1));  # invalid
    s.string_agg(s.int64(1), s.text(','));  # invalid
    s.inner_join(source, s.int64(1));  # invalid
    s.select([s.named('n', s.int64(1))], having=s.int64(1));  # invalid
    s.named('n', s.select([s.named('n', s.int64(1))]));  # invalid
}
