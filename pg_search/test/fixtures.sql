CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_bm25;
CREATE EXTENSION IF NOT EXISTS pg_search;

CREATE TABLE mock_items AS SELECT * FROM paradedb.mock_items;
