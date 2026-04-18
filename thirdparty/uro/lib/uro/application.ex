defmodule Uro.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:uro, :repo])
    OpentelemetryLoggerMetadata.setup()

    wt_children =
      if Mix.env() == :test, do: [], else: [Uro.WebTransport.Supervisor]

    children =
      if System.get_env("MINIMAL_START") == "true",
        do: [],
        else:
          [
            Uro.Telemetry.SpanStore,
            Uro.Telemetry,
            Uro.Repo,
            Uro.Acl,
            Uro.Manifest,
            Uro.Keys,
            {Phoenix.PubSub, [name: Uro.PubSub, adapter: Phoenix.PubSub.PG2]},
            Uro.Endpoint,
            Uro.VSekai.ShardJanitor,
            Pow.Store.Backend.MnesiaCache,
            ExMarcel.TableWrapper,
            {Task, fn -> Uro.Helpers.Validation.init_extra_extensions() end},
            {Registry, keys: :unique, name: Uro.WebTransport.ZoneRegistry},
            Uro.WebTransport.ZoneSupervisor
          ] ++ wt_children

    opts = [strategy: :one_for_one, name: Uro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    Uro.Endpoint.config_change(changed, removed)
    :ok
  end
end
