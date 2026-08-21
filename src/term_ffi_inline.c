// term_ffi_inline.c — C FFI for raw terminal I/O.
// Called from term_ffi.kk via Koka's extern import mechanism.
// Koka adds kklib.h to the include path automatically.
//
// Adapted from hica-ecosystem's programs/myeon/term_raw_ffi.c.

#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <errno.h>
#include <stdio.h>

// Read a single key from stdin.
// Returns:
//   printable chars: ASCII value (32-126)
//   Enter: 10, Backspace: 127, Tab: 9, Esc: 27
//   Arrow Up: 1001, Down: 1002, Right: 1003, Left: 1004
//   decoded multi-byte UTF-8 input (åäö, etc.): the Unicode codepoint (>=128)
//   read timeout (no key within ~200ms): -2 — lets the caller re-poll
//     get_dimensions() and redraw periodically (e.g. after a terminal
//     resize) without blocking indefinitely on the next keystroke
//   error/EOF: -1
static int hedit_read_byte_blocking(unsigned char* out) {
    int n;
    do { n = (int)read(0, out, 1); } while (n < 0 && errno == EINTR);
    return n;
}

kk_integer_t hedit_read_key(void) {
    kk_context_t* ctx = kk_get_context();

    // Poll with a short timeout so the event loop wakes up periodically
    // even with no keyboard input — this is what lets a terminal resize
    // (which doesn't interrupt a blocking read()) get picked up promptly
    // instead of only on the next real keypress.
    fd_set wait_fds;
    struct timeval wait_tv = {0, 200000};  // 200ms
    FD_ZERO(&wait_fds);
    FD_SET(0, &wait_fds);
    int ready = select(1, &wait_fds, NULL, NULL, &wait_tv);
    if (ready == 0) {
        return kk_integer_from_int(-2, ctx);  // timeout — no key available
    }

    unsigned char c;
    int n = hedit_read_byte_blocking(&c);
    if (n != 1) return kk_integer_from_int(-1, ctx);
    int key = (int)c;

    if (key == 27) {  // ESC or escape sequence
        fd_set fds;
        struct timeval tv = {0, 100000};  // 100ms — enough to catch a real sequence
        FD_ZERO(&fds);
        FD_SET(0, &fds);
        if (select(1, &fds, NULL, NULL, &tv) > 0) {
            unsigned char c2;
            if (read(0, &c2, 1) == 1 && c2 == 91) {  // ESC [
                unsigned char c3;
                if (read(0, &c3, 1) == 1) {
                    if      (c3 == 65) key = 1001;  // Up
                    else if (c3 == 66) key = 1002;  // Down
                    else if (c3 == 67) key = 1003;  // Right
                    else if (c3 == 68) key = 1004;  // Left
                    else               key = -1;
                }
            }
        }
        // else: plain ESC, key stays 27
    } else if (key >= 0xC0) {
        // UTF-8 multi-byte leader byte — decode the sequence into a single
        // Unicode codepoint (hica's `char`/`string` are codepoint-based,
        // not byte-based, so this is the representation the rest of the
        // pipeline expects; see decode_key in src/keys.hc).
        int extra;
        int cp;
        if      ((key & 0xE0) == 0xC0) { extra = 1; cp = key & 0x1F; }
        else if ((key & 0xF0) == 0xE0) { extra = 2; cp = key & 0x0F; }
        else if ((key & 0xF8) == 0xF0) { extra = 3; cp = key & 0x07; }
        else { extra = 0; cp = key; }  // not a valid leader byte, pass through
        int i;
        for (i = 0; i < extra; i++) {
            unsigned char cont;
            int m = hedit_read_byte_blocking(&cont);
            if (m != 1 || (cont & 0xC0) != 0x80) { cp = -1; break; }
            cp = (cp << 6) | (cont & 0x3F);
        }
        key = cp;
    }
    return kk_integer_from_int(key, ctx);
}


// Return terminal column count (default 80).
kk_integer_t hedit_term_cols(void) {
    kk_context_t* ctx = kk_get_context();
    struct winsize ws;
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0)
        return kk_integer_from_int((int)ws.ws_col, ctx);
    return kk_integer_from_int(80, ctx);
}

// Return terminal row count (default 24).
kk_integer_t hedit_term_rows(void) {
    kk_context_t* ctx = kk_get_context();
    struct winsize ws;
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0)
        return kk_integer_from_int((int)ws.ws_row, ctx);
    return kk_integer_from_int(24, ctx);
}

// Flush stdout.
kk_unit_t hedit_flush_stdout(void) {
    fflush(stdout);
    return kk_Unit;
}
