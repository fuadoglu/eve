-- D46: commit the import-only media classification before constraint use.
alter type app_private.media_classification add value if not exists 'private_import';
