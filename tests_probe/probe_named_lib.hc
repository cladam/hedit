// Minimal repro: a named effect (promoted via a local spawn) used
// internally by a `pub fun` that fully discharges it before returning.
pub effect Counter {
  fun incr()
  fun get() : int
}

// Local spawn promotes Counter to a Koka "named effect".
pub fun run_three() {
  spawn Counter {
    incr() => count = count + 1,
    get() => count
  } with var count = 0 as c
  c.incr()
  c.incr()
  c.incr()
  c.get()
}
