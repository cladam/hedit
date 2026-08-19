import "probe_a"

fun main() {
  spawn Counter {
    incr() => count = count + 1,
    get() => count
  } with var count = 0 as c1

  c1.incr()
  c1.incr()
  println("c1 = {show(c1.get())}")
}
