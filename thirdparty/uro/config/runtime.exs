import Config

# CockroachDB TLS client-cert auth.
# CRDB_*_B64 hold base64-encoded PEM values so no cert files need to be
# present on the filesystem. When the variables are set, Postgrex connects
# over TLS using the decoded certs; when absent, it falls back to the plain
# DATABASE_URL (useful for CI/test environments that accept connections without TLS).
crdb_ca_b64     = System.get_env("CRDB_CA_CERT_B64")
crdb_cert_b64   = System.get_env("CRDB_CLIENT_CERT_B64")
crdb_key_b64    = System.get_env("CRDB_CLIENT_KEY_B64")

ssl_opts =
  if crdb_ca_b64 && crdb_cert_b64 && crdb_key_b64 do
    ca_pem   = Base.decode64!(crdb_ca_b64)
    cert_pem = Base.decode64!(crdb_cert_b64)
    key_pem  = Base.decode64!(crdb_key_b64)

    [{:Certificate, ca_der, _}  | _] = :public_key.pem_decode(ca_pem)
    [{:Certificate, cert_der, _}| _] = :public_key.pem_decode(cert_pem)
    [{key_type, key_der, _}     | _] = :public_key.pem_decode(key_pem)

    [
      cacerts: [ca_der],
      cert: cert_der,
      key: {key_type, key_der},
      verify: :verify_peer
    ]
  else
    false
  end

db_url_key = if config_env() == :test, do: "TEST_DATABASE_URL", else: "DATABASE_URL"

if database_url = System.get_env(db_url_key) do
  repo_config =
    [url: database_url, migration_lock: false]
    |> then(fn cfg ->
      if ssl_opts, do: Keyword.merge(cfg, ssl: true, ssl_opts: ssl_opts), else: cfg
    end)

  config :uro, Uro.Repo, repo_config
end

# OpenTelemetry OTLP endpoint — read at runtime so the same release works
# with and without an agent.  When OTEL_EXPORTER_OTLP_ENDPOINT is set (e.g.
# http://jaeger:4318 inside Docker), spans are shipped; otherwise no-op.
if otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: otlp_endpoint
end

if service_name = System.get_env("OTEL_SERVICE_NAME") do
  config :opentelemetry, resource: %{service: %{name: service_name}}
end
