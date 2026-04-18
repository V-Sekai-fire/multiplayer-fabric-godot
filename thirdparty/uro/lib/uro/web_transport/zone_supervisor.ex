defmodule Uro.WebTransport.ZoneSupervisor do
  @moduledoc """
  DynamicSupervisor for Godot fabric-zone processes.

  Usage:
    Uro.WebTransport.ZoneSupervisor.start_zone(shard_id, port)
    Uro.WebTransport.ZoneSupervisor.stop_zone(shard_id, port)
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_zone(shard_id, port) do
    DynamicSupervisor.start_child(__MODULE__, {Uro.WebTransport.Zone, shard_id: shard_id, port: port})
  end

  def stop_zone(shard_id, port) do
    case Registry.lookup(Uro.WebTransport.ZoneRegistry, {shard_id, port}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
