import Config
require Logger

Code.require_file("config/helpers.exs")
Code.ensure_loaded!(Uro.Config.Helpers)
alias Uro.Config.Helpers

compile_phase? = System.get_env("COMPILE_PHASE") != "false"

get_env = fn key, example ->
  case compile_phase? do
    true ->
      example

    false ->
      System.get_env(key) ||
        raise """
        Environment variable "#{key}" is required but not set.
        """
  end
end

get_optional_env = fn key ->
  System.get_env(key)
end

config :uro,
  compile_phase?: System.get_env("COMPILE_PHASE") != "false"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

url =
  "URL"
  |> get_env.("https://vsekai.local/api/v1/")
  |> URI.new!()

root_origin =
  "ROOT_ORIGIN"
  |> get_env.("https://vsekai.local")
  |> URI.new!()

config :uro,
  ecto_repos: [Uro.Repo],
  url: url,
  frontend_url:
    "FRONTEND_URL"
    |> Helpers.get_env("https://vsekai.local/")
    |> URI.new!(),
  root_origin: root_origin

config :uro, Uro.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: Helpers.get_env("DATABASE_URL", "postgresql://vsekai@database:26257/vsekai"),
  pool_size: 10,
  migration_lock: false

config :uro, Uro.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: Map.take(url, [:scheme, :host, :path]),
  # url:
  #   "URL"
  #   |> Helpers.get_env("https://example.com/api/")
  #   |> URI.new!()
  #   |> Map.take([:scheme, :host, :path]),

  http: [
    port:
      "PORT"
      |> Helpers.get_env("4000")
      |> String.to_integer()
  ],
  secret_key_base:
    Helpers.get_env(
      "PHOENIX_KEY_BASE",
      "bNDe+pg86uL938fQA8QGYCJ4V7fE5RAxoQ8grq9drPpO7mZ0oEMSNapKLiA48smR"
    )

# pubsub_server: Uro.PubSub,
# live_view: [signing_salt: "0dBPUwA2"]

root_origin =
  "ROOT_ORIGIN"
  |> Helpers.get_env("https://example.com")
  |> URI.new!()

config :cors_plug,
  origin: [URI.to_string(root_origin)],
  max_age: 86400

config :joken, default_signer: Helpers.get_env("JOKEN_SIGNER", "gqawCOER09ZZjaN8W2QM9XT9BeJSZ9qc")

config :uro, :stale_shard_cutoff,
  amount: 3,
  calendar_type: "month"

config :uro, :stale_shard_interval, 30 * 24 * 60 * 60 * 1000

config :uro, Uro.Turnstile,
  secret_key:
    get_optional_env.("TURNSTILE_SECRET_KEY") ||
      Logger.warning(
        "Turnstile (a reCaptcha alternative) is disabled because the environment variable TURNSTILE_SECRET_KEY is not set. For more information, see https://developers.cloudflare.com/turnstile/get-started/."
      )

config :uro, :pow,
  user: Uro.Accounts.User,
  users_context: Uro.Accounts,
  repo: Uro.Repo,
  web_module: Uro,
  extensions: [PowPersistentSession],
  controller_callbacks: Pow.Extension.Phoenix.ControllerCallbacks,
  routes_backend: Uro.Pow.Routes,
  cache_store_backend: Pow.Store.Backend.MnesiaCache

config :uro, :pow_assent,
  user_identities_context: Uro.UserIdentities,
  providers:
    (case(compile_phase?) do
       true ->
         []

       false ->
         System.get_env()
         |> Map.filter(fn {k, _} -> String.match?(k, ~r/^OAUTH2_.+_STRATEGY/) end)
         |> Enum.map(fn {key, module_name} ->
           key =
             key
             |> String.replace("OAUTH2_", "")
             |> String.replace("_STRATEGY", "")

           {
             key
             |> String.downcase()
             |> String.to_atom(),
             [
               client_id: get_env.("OAUTH2_#{key}_CLIENT_ID", nil),
               client_secret: get_env.("OAUTH2_#{key}_CLIENT_SECRET", nil),
               strategy: Module.concat([module_name])
             ]
           }
         end)
     end)

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :uro, Uro.WebTransport,
  host: Helpers.get_env("WT_HOST", "0.0.0.0"),
  port: "WT_PORT" |> Helpers.get_env("4433") |> String.to_integer(),
  cert: Helpers.get_env("WT_CERT", "/run/secrets/wt_cert.pem"),
  key: Helpers.get_env("WT_KEY", "/run/secrets/wt_key.pem")

# Zone supervisor: path to the Godot project root and binary.
# GODOT_BIN  – executable name or absolute path (default: "godot")
# GODOT_PROJECT – absolute path to the Godot project directory so the
#                 zone script can be resolved as a relative path from it.

config :waffle,
  storage: Waffle.Storage.Local

# storage_dir: "uploads"

# OpenTelemetry — exports traces via OTLP to OTEL_EXPORTER_OTLP_ENDPOINT.
# When that env var is absent the SDK runs with a no-op exporter; no errors
# are raised and no spans are dropped. Wire in an agent by setting the variable.
config :opentelemetry,
  processors: [
    # Batch-export to OTLP (no-op when OTEL_EXPORTER_OTLP_ENDPOINT is unset)
    {:otel_batch_processor, %{exporter: {:opentelemetry_exporter, %{}}}},
    # Mirror every completed span into the in-app ETS span store
    {Uro.Telemetry.SpanProcessor, %{}}
  ]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf

# SpanStore time window — keep spans for this many minutes in the ETS buffer.
# Increase if you want a longer trace history at the cost of memory.
config :uro, Uro.Telemetry.SpanStore,
  ttl_ms: :timer.minutes(5),
  sweep_interval_ms: :timer.seconds(30)

import_config "#{Mix.env()}.exs"

if Mix.env() == "dev" do
  import_config "local.exs"
end
