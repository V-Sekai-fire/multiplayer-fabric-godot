defmodule Uro.WebTransport.Supervisor do
  @moduledoc """
  Starts the wtransport-elixir server under the Uro supervision tree.

  If WT_CERT / WT_KEY point to existing files those are used; otherwise a
  fresh P-256 ECDSA cert is generated at startup and written to tmp files.
  """

  def child_spec(_opts) do
    config = Application.get_env(:uro, Uro.WebTransport, [])
    {cert_path, key_path} = resolve_cert(config)

    %{
      id: __MODULE__,
      start:
        {Wtransport.Supervisor, :start_link,
         [
           [
             host: Keyword.get(config, :host, "0.0.0.0"),
             port: Keyword.get(config, :port, 4433),
             certfile: cert_path,
             keyfile: key_path,
             connection_handler: Uro.WebTransport.ConnectionHandler,
             stream_handler: Uro.WebTransport.StreamHandler
           ]
         ]},
      type: :supervisor
    }
  end

  defp resolve_cert(config) do
    cert = Keyword.get(config, :cert)
    key = Keyword.get(config, :key)

    if cert && File.exists?(cert) && key && File.exists?(key) do
      {cert, key}
    else
      generate_temp_cert()
    end
  end

  defp generate_temp_cert do
    {:ok, cert_pem, key_pem, _hash} =
      Uro.WebTransport.Cert.generate(["localhost"], ["127.0.0.1", "::1"])

    dir = System.tmp_dir!()
    cert_path = Path.join(dir, "uro_wt_cert.pem")
    key_path = Path.join(dir, "uro_wt_key.pem")
    File.write!(cert_path, cert_pem)
    File.write!(key_path, key_pem)
    {cert_path, key_path}
  end
end
