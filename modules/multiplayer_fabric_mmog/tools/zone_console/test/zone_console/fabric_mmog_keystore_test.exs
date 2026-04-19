defmodule ZoneConsole.FabricMMOGKeyStoreTest do
  use ExUnit.Case, async: false
  use PropCheck

  alias ZoneConsole.FabricMMOGKeyStore, as: KS
  alias ZoneConsole.Keychain.Mock

  setup do
    Mock.reset()
    :ok
  end

  # ── generators ──────────────────────────────────────────────────────────────

  defp uuid do
    let segs <- vector(4, integer(0, 0xFFFF)) do
      Enum.map_join(segs, "-", &Integer.to_string(&1, 16))
    end
  end

  defp aes_key, do: binary(KS.aes_key_bytes())
  defp aes_iv, do: binary(KS.aes_iv_bytes())

  # ── properties ──────────────────────────────────────────────────────────────

  property "put then get within TTL returns the same key and iv" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      now = System.os_time(:second)
      {:ok, ^key, ^iv} = KS.get_with_clock(id, now)
      true
    end
  end

  property "get on missing uuid returns :not_found" do
    forall id <- uuid() do
      Mock.reset()
      {:error, :not_found} == KS.get(id)
    end
  end

  property "put overwrites existing entry — last write wins" do
    forall [id <- uuid(), k1 <- aes_key(), iv1 <- aes_iv(),
            k2 <- aes_key(), iv2 <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, k1, iv1)
      :ok = KS.put(id, k2, iv2)
      now = System.os_time(:second)
      {:ok, ^k2, ^iv2} = KS.get_with_clock(id, now)
      true
    end
  end

  property "expired entry returns :expired" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      # Advance clock past TTL
      future = System.os_time(:second) + KS.key_ttl_seconds() + 1
      {:error, :expired} == KS.get_with_clock(id, future)
    end
  end

  property "entry stored exactly at TTL boundary is still valid" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      now = System.os_time(:second)
      at_boundary = now + KS.key_ttl_seconds()
      # at exactly TTL seconds old — should still be valid (> not >=)
      match?({:ok, _, _}, KS.get_with_clock(id, at_boundary))
    end
  end

  property "entry one second past TTL is expired" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      now = System.os_time(:second)
      past = now + KS.key_ttl_seconds() + 1
      {:error, :expired} == KS.get_with_clock(id, past)
    end
  end

  property "remove then get returns :not_found" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      :ok = KS.remove(id)
      {:error, :not_found} == KS.get(id)
    end
  end

  property "remove of missing uuid is idempotent — returns :ok" do
    forall id <- uuid() do
      Mock.reset()
      :ok == KS.remove(id)
    end
  end

  property "key and iv lengths match C++ AES_KEY_BYTES and AES_IV_BYTES" do
    forall [id <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      Mock.reset()
      :ok = KS.put(id, key, iv)
      now = System.os_time(:second)

      case KS.get_with_clock(id, now) do
        {:ok, r_key, r_iv} ->
          byte_size(r_key) == KS.aes_key_bytes() and
            byte_size(r_iv) == KS.aes_iv_bytes()

        _ ->
          false
      end
    end
  end

  property "entries for different uuids are isolated" do
    forall [id1 <- uuid(), id2 <- uuid(), key <- aes_key(), iv <- aes_iv()] do
      implies id1 != id2 do
        Mock.reset()
        :ok = KS.put(id1, key, iv)
        {:error, :not_found} == KS.get(id2)
      end
    end
  end

  # ── unit tests ──────────────────────────────────────────────────────────────

  test "constants match C++ definitions" do
    assert KS.aes_key_bytes() == 16
    assert KS.aes_iv_bytes() == 12
    assert KS.key_ttl_seconds() == 86_400
    assert KS.package() == "org.v-sekai.godot"
    assert KS.service() == "multiplayer_fabric_mmog.asset_key"
  end

  test "put rejects key of wrong length" do
    assert_raise FunctionClauseError, fn ->
      KS.put("uuid", <<1, 2, 3>>, :crypto.strong_rand_bytes(12))
    end
  end

  test "put rejects iv of wrong length" do
    assert_raise FunctionClauseError, fn ->
      KS.put("uuid", :crypto.strong_rand_bytes(16), <<1, 2, 3>>)
    end
  end
end
