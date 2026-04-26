import Lake
open Lake DSL

package «http3» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib «WebTransport» where
  srcDir := "."

