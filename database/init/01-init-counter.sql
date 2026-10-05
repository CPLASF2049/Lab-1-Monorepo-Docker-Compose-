-- Lab 1 shared counter: schema and first-time initialization.
-- Executed once by the postgres image entrypoint on an EMPTY data directory
-- (docker-entrypoint-initdb.d). The backend also runs the same statements on
-- every start, so an existing volume is never re-initialized by this script.

CREATE TABLE IF NOT EXISTS counter (
  id         INTEGER     PRIMARY KEY,
  value      BIGINT      NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the single shared counter only when it is missing. ON CONFLICT DO NOTHING
-- guarantees an existing value is never overwritten by a restart.
INSERT INTO counter (id, value)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;
