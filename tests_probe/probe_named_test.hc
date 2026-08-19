import "probe_named_lib"

// Never calls Counter ops directly, never spawns Counter — only calls
// the fully-discharging `run_three()`. If hica's test-mode auto panic
// handler still tries (and fails) to install a Counter guard, that
// proves the bug is unrelated to Buffer's specific op shapes.
test "run_three returns 3" {
  assert(run_three() == 3)
}
