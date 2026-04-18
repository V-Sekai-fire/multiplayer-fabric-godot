defmodule Uro.WebTransport.Cert do
  @moduledoc """
  Generates a short-lived P-256 ECDSA self-signed certificate using
  pure OTP :public_key / :crypto.

  Returns {:ok, cert_pem, key_pem, cert_hash_base64}.
  cert_hash_base64 is base64(SHA-256(DER)) for WebTransport serverCertificateHashes.
  """

  require Record

  Record.defrecordp :ec_private_key, :"ECPrivateKey",
    Record.extract(:"ECPrivateKey", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :otp_tbs_certificate, :"OTPTBSCertificate",
    Record.extract(:"OTPTBSCertificate", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :otp_spki, :"OTPSubjectPublicKeyInfo",
    Record.extract(:"OTPSubjectPublicKeyInfo", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :pubkey_algo, :"PublicKeyAlgorithm",
    Record.extract(:"PublicKeyAlgorithm", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :sig_algo, :"SignatureAlgorithm",
    Record.extract(:"SignatureAlgorithm", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :validity, :"Validity",
    Record.extract(:"Validity", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :extension, :"Extension",
    Record.extract(:"Extension", from_lib: "public_key/include/public_key.hrl")

  Record.defrecordp :attr_type_val, :"AttributeTypeAndValue",
    Record.extract(:"AttributeTypeAndValue", from_lib: "public_key/include/public_key.hrl")

  @curve :secp256r1
  @curve_oid {1, 2, 840, 10045, 3, 1, 7}
  @ec_pub_oid {1, 2, 840, 10045, 2, 1}
  @ecdsa_sha256_oid {1, 2, 840, 10045, 4, 3, 2}
  @validity_days 13

  def generate(san_dns \\ [], san_ips \\ []) do
    {pub_bytes, priv_bytes} = :crypto.generate_key(:ecdh, @curve)

    ec_priv =
      ec_private_key(
        version: 1,
        privateKey: priv_bytes,
        parameters: {:namedCurve, @curve_oid},
        publicKey: pub_bytes
      )

    now = DateTime.utc_now()
    not_after = DateTime.add(now, @validity_days * 86_400, :second)

    tbs =
      otp_tbs_certificate(
        version: :v3,
        serialNumber: serial(),
        signature: sig_algo(algorithm: @ecdsa_sha256_oid, parameters: :asn1_NOVALUE),
        issuer: rdn("uro"),
        validity: validity(notBefore: {:generalTime, fmt_time(now)}, notAfter: {:generalTime, fmt_time(not_after)}),
        subject: rdn("uro"),
        subjectPublicKeyInfo:
          otp_spki(
            algorithm: pubkey_algo(algorithm: @ec_pub_oid, parameters: {:namedCurve, @curve_oid}),
            subjectPublicKey: {:ECPoint, pub_bytes}
          ),
        extensions: [san_extension(san_dns, san_ips)]
      )

    cert_der = :public_key.pkix_sign(tbs, ec_priv)
    cert_pem = :public_key.pem_encode([{:Certificate, cert_der, :not_encrypted}])

    {:ok, key_der} = :public_key.der_encode(:"ECPrivateKey", ec_priv)
    key_pem = :public_key.pem_encode([{:"ECPrivateKey", key_der, :not_encrypted}])

    cert_hash = cert_der |> :crypto.hash(:sha256) |> Base.encode64()

    {:ok, cert_pem, key_pem, cert_hash}
  end

  defp serial do
    <<n::128>> = :crypto.strong_rand_bytes(16)
    n
  end

  defp fmt_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y%m%d%H%M%SZ")

  defp rdn(cn) do
    {:rdnSequence, [[attr_type_val(type: {2, 5, 4, 3}, value: {:utf8String, cn})]]}
  end

  defp san_extension(dns_names, ip_addrs) do
    entries =
      Enum.map(dns_names, &{:dNSName, String.to_charlist(&1)}) ++
        Enum.map(ip_addrs, fn ip ->
          {:ok, addr} = :inet.parse_address(String.to_charlist(ip))
          {:iPAddress, ip_to_bytes(addr)}
        end)

    {:ok, san_der} = :public_key.der_encode(:"SubjectAltName", entries)

    extension(extnID: {2, 5, 29, 17}, critical: false, extnValue: san_der)
  end

  defp ip_to_bytes({a, b, c, d}), do: [a, b, c, d]

  defp ip_to_bytes({a, b, c, d, e, f, g, h}) do
    <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
    |> :erlang.binary_to_list()
  end
end
