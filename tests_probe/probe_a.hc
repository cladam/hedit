pub effect Counter {
  fun incr()
  fun get() : int
}

// Dummy usage to see if a same-file `spawn` changes the emitted Koka
// effect kind (named vs plain) for cross-module consumers.
fun probe_spawn_here() {
  spawn Counter {
    incr() => count = count + 1,
    get() => count
  } with var count = 0 as c0
  c0.incr()
}
