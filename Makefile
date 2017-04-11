EXTENSION = pg_audit_tools
DATA = sql/pg_audit_tools--*.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
