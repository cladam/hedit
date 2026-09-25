/// Unit and host-tolerant integration tests for OS clipboard support.

import "../src/clipboard"

test "clipboard tool selection prefers macOS then Wayland then X11" {
  let all = ["xsel", "xclip", "wl-paste", "wl-copy", "pbpaste", "pbcopy"]
  assert(choose_clipboard_tool(all) == Some(("pbcopy", "pbpaste")))

  let linux = ["xsel", "xclip", "wl-paste", "wl-copy"]
  assert(choose_clipboard_tool(linux) == Some(("wl-copy", "wl-paste -n")))

  let x11 = ["xsel", "xclip"]
  assert(choose_clipboard_tool(x11) == Some(("xclip -selection clipboard -i", "xclip -selection clipboard -o")))
}

test "clipboard tool selection requires complete command pairs" {
  assert(choose_clipboard_tool(["pbcopy", "wl-copy", "xsel"]) == Some(("xsel -b -i", "xsel -b -o")))
  assert(choose_clipboard_tool(["pbcopy", "wl-paste"]) == None)
  assert(choose_clipboard_tool([]) == None)
}

test "clipboard helpers preserve the in-memory fallback without a tool" {
  assert(os_clipboard_set(None, "outside") == false)
  assert_eq(os_clipboard_get(None, "inside\nwith trailing space "), "inside\nwith trailing space ")
}

test "detected OS clipboard round-trips exact plain text" {
  match detect_clipboard_tool() {
    None => assert(true),
    Some(tool) => {
      let original = os_clipboard_get(Some(tool), "")
      let sample = "hedit M25 clipboard\nsecond line\n"
      let wrote = os_clipboard_set(Some(tool), sample)
      let actual = os_clipboard_get(Some(tool), "clipboard read failed")
      let _ = os_clipboard_set(Some(tool), original)
      assert(wrote)
      assert_eq(actual, sample)
    }
  }
}
