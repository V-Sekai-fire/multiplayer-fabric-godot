import Config

# Tests run against the Oxide CockroachDB 22.1 fork served by the
# docker-compose.yml `database` service. Bring it up before `mix test`:
#
#   docker compose -f thirdparty/uro/docker-compose.yml up -d database
#
# Set TEST_DATABASE_URL to the CockroachDB connection string, e.g.:
#   TEST_DATABASE_URL=postgresql://vsekai@127.0.0.1:26257/vsekai_test
#
# TLS client-cert auth is applied at runtime via CRDB_CA_CERT_B64,
# CRDB_CLIENT_CERT_B64, and CRDB_CLIENT_KEY_B64 (same as production).
# See config/runtime.exs for details.
config :uro, Uro.Repo,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
