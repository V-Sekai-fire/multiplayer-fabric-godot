defmodule Mix.Tasks.Uro.CrdbGenCerts do
  @shortdoc "Generate CockroachDB TLS certs and print CRDB_*_B64 env lines"

  @moduledoc """
  Generates CockroachDB CA, node, and client certs via the cockroach binary
  inside a running database container, then prints the base64-encoded env
  variable lines ready to paste into your .env file.

  ## Usage

      mix uro.crdb_gen_certs [--container <name>] [--user <db-user>] [--nodes <host,...>]

  ## Options

    * `--container` — Docker container name (default: `uro-database-1`)
    * `--user`      — CockroachDB SQL user to generate a client cert for (default: `vsekai`)
    * `--nodes`     — Comma-separated hostnames/IPs for the node cert (default: `localhost,127.0.0.1,database`)

  ## Example

      mix uro.crdb_gen_certs
      mix uro.crdb_gen_certs --container my-crdb --user myuser --nodes localhost,127.0.0.1,myhost

  The printed lines can be appended directly to your .env:

      mix uro.crdb_gen_certs >> .env
  """

  use Mix.Task

  @tmp_dir "/tmp/uro-crdb-certs-#{:os.getpid()}"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [container: :string, user: :string, nodes: :string]
      )

    container = Keyword.get(opts, :container, "uro-database-1")
    user      = Keyword.get(opts, :user, "vsekai")
    nodes     = Keyword.get(opts, :nodes, "localhost,127.0.0.1,database") |> String.split(",")

    Mix.shell().info("Generating CockroachDB certs via container: #{container}")

    with :ok <- docker_exec(container, ["mkdir", "-p", @tmp_dir]),
         :ok <- cockroach_cert(container, ["create-ca", "--certs-dir=#{@tmp_dir}", "--ca-key=#{@tmp_dir}/ca.key"]),
         :ok <- cockroach_cert(container, ["create-node" | nodes] ++ ["--certs-dir=#{@tmp_dir}", "--ca-key=#{@tmp_dir}/ca.key"]),
         :ok <- cockroach_cert(container, ["create-client", user, "--certs-dir=#{@tmp_dir}", "--ca-key=#{@tmp_dir}/ca.key"]),
         {:ok, ca_b64}   <- read_b64(container, "#{@tmp_dir}/ca.crt"),
         {:ok, cert_b64} <- read_b64(container, "#{@tmp_dir}/client.#{user}.crt"),
         {:ok, key_b64}  <- read_b64(container, "#{@tmp_dir}/client.#{user}.key") do

      IO.puts("")
      IO.puts("# CockroachDB TLS client-cert auth — paste into .env")
      IO.puts("DATABASE_URL=postgresql://#{user}@localhost:26257/vsekai")
      IO.puts("CRDB_CA_CERT_B64=#{ca_b64}")
      IO.puts("CRDB_CLIENT_CERT_B64=#{cert_b64}")
      IO.puts("CRDB_CLIENT_KEY_B64=#{key_b64}")

      docker_exec(container, ["rm", "-rf", @tmp_dir])
    else
      {:error, msg} ->
        Mix.raise("cert generation failed: #{msg}")
    end
  end

  defp docker_exec(container, cmd) do
    case System.cmd("docker", ["exec", container | cmd], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, "exit #{code}: #{String.trim(out)}"}
    end
  end

  defp cockroach_cert(container, cert_args) do
    docker_exec(container, ["/cockroach/cockroach", "cert" | cert_args])
  end

  defp read_b64(container, path) do
    case System.cmd("docker", ["exec", container, "base64", path], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.replace(out, "\n", "")}
      {out, code} -> {:error, "exit #{code}: #{String.trim(out)}"}
    end
  end
end
