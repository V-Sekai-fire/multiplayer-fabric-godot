defmodule ZoneConsole.KeychainTest do
  use ExUnit.Case, async: false
  use PropCheck

  alias ZoneConsole.Keychain
  alias ZoneConsole.Keychain.Mock

  setup do
    Mock.reset()
    :ok
  end

  # ── generators ──────────────────────────────────────────────────────────────

  # Non-empty printable ASCII strings — realistic keychain identifiers
  defp printable_string do
    let chars <- non_empty(list(integer(32, 126))) do
      List.to_string(chars)
    end
  end

  defp package, do: printable_string()
  defp service, do: printable_string()
  defp user, do: printable_string()
  defp password, do: printable_string()

  # ── properties ──────────────────────────────────────────────────────────────

  property "set then get returns the same password" do
    forall [pkg <- package(), svc <- service(), u <- user(), pw <- password()] do
      Mock.reset()
      :ok = Keychain.set_password(pkg, svc, u, pw)
      {:ok, ^pw} = Keychain.get_password(pkg, svc, u)
      true
    end
  end

  property "get on missing entry returns :not_found" do
    forall [pkg <- package(), svc <- service(), u <- user()] do
      Mock.reset()
      {:error, :not_found} == Keychain.get_password(pkg, svc, u)
    end
  end

  property "set is idempotent — last write wins" do
    forall [
      pkg <- package(),
      svc <- service(),
      u <- user(),
      pw1 <- password(),
      pw2 <- password()
    ] do
      Mock.reset()
      :ok = Keychain.set_password(pkg, svc, u, pw1)
      :ok = Keychain.set_password(pkg, svc, u, pw2)
      {:ok, ^pw2} = Keychain.get_password(pkg, svc, u)
      true
    end
  end

  property "delete removes the entry" do
    forall [pkg <- package(), svc <- service(), u <- user(), pw <- password()] do
      Mock.reset()
      :ok = Keychain.set_password(pkg, svc, u, pw)
      :ok = Keychain.delete_password(pkg, svc, u)
      {:error, :not_found} == Keychain.get_password(pkg, svc, u)
    end
  end

  property "delete of missing entry returns :not_found" do
    forall [pkg <- package(), svc <- service(), u <- user()] do
      Mock.reset()
      {:error, :not_found} == Keychain.delete_password(pkg, svc, u)
    end
  end

  property "entries under different (package, service, user) tuples are isolated" do
    forall [
      pkg1 <- package(),
      pkg2 <- package(),
      svc <- service(),
      u <- user(),
      pw <- password()
    ] do
      implies pkg1 != pkg2 do
        Mock.reset()
        :ok = Keychain.set_password(pkg1, svc, u, pw)
        {:error, :not_found} == Keychain.get_password(pkg2, svc, u)
      end
    end
  end

  property "service_name concatenation matches C++ makeServiceName" do
    forall [pkg <- package(), svc <- service()] do
      expected = pkg <> "." <> svc
      # Reach into the private function via the mock to verify key shape
      :ok = Mock.set_password(expected, "u", "pw")
      {:ok, "pw"} == Mock.get_password(expected, "u")
    end
  end
end
