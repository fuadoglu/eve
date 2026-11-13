-- D34: extend the media enum in its own committed migration.
-- PostgreSQL requires a newly added enum label to commit before use in DDL.
alter type app_private.media_classification add value if not exists 'private_inventory';
