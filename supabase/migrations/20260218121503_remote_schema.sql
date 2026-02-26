-- bootstrap-safe no-op (schema snapshot already represented by previous migrations in this branch)
begin;
select 1;
commit;
