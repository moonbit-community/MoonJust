///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
test "portable host normalizes launcher architecture aliases" {
  assert_eq(portable_architecture(Some("arm64")), "aarch64")
  assert_eq(portable_architecture(Some("AMD64")), "x86_64")
  assert_eq(portable_architecture(Some("riscv64")), "riscv64")
  assert_eq(portable_architecture(None), "wasm32")
}
