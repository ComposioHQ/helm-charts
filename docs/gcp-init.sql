-- Create user with necessary privileges
CREATE USER composio WITH PASSWORD '<DATABASE_PASSWORD>';
ALTER USER composio WITH CREATEROLE CREATEDB;

-- Grant Cloud SQL superuser role (required for GCP managed instances)
GRANT cloudsqlsuperuser TO composio;
GRANT composio TO postgres;

-- Create databases
CREATE DATABASE composiodb;
CREATE DATABASE temporal;
CREATE DATABASE temporal_visibility;
CREATE DATABASE thermosdb;

-- Configure composiodb
\c composiodb
ALTER DATABASE composiodb OWNER TO composio;
GRANT ALL PRIVILEGES ON DATABASE composiodb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Configure temporal
\c temporal
ALTER DATABASE temporal OWNER TO composio;
GRANT ALL PRIVILEGES ON DATABASE temporal TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Configure thermosdb
\c thermosdb
ALTER DATABASE thermosdb OWNER TO composio;
GRANT ALL PRIVILEGES ON DATABASE thermosdb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Configure temporal_visibility
\c temporal_visibility
ALTER DATABASE temporal_visibility OWNER TO composio;
GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;
