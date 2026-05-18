# PTY Implementation Plan (Fixing Garbage Output)

This document outlines the required changes to `src/pty.zig` and `src/main.zig` to resolve the issue where spawned processes (like `btop` or `echo`) return garbage data (`0xAA` bytes) or trigger `POLLERR`.

## Root Cause Analysis
Current implementation uses `openpty()` but fails to properly initialize the child process's terminal session. Without `setsid()` and `TIOCSCTTY`, the child process remains attached to the parent's terminal or has no controlling terminal at all, causing TUI applications to fail or output uninitialized memory.

## Required Changes

### 1. Robust Child Session Initialization (`src/pty.zig`)
In the child process (after `fork()` but before `execvp()`):
- **Call `setsid()`**: Create a new session and detach from the parent's controlling terminal.
- **Set Controlling Terminal**: Use `ioctl(slave_fd, TIOCSCTTY, 0)` to make the slave PTY the controlling terminal for the new session.
- **Signal Mask Reset**: Use `std.posix.sigprocmask` with `SIG_SETMASK` and an empty set to clear any inherited signal blocks.
- **Signal Handler Reset**: Reset critical signals (SIGINT, SIGTERM, SIGHUP, SIGPIPE) to `SIG_DFL`.

### 2. Master FD Management (`src/pty.zig`)
- **Strict `FD_CLOEXEC`**: Ensure the master file descriptor has the `O_CLOEXEC` flag set immediately after opening to prevent leaking the PTY master into unrelated subprocesses.
- **Non-blocking Mode**: Set the master FD to `O_NONBLOCK`. This ensures that `posix.read()` in the main loop returns `error.WouldBlock` instead of hanging, which is required for our `poll()` based event loop.

### 3. Environment Variables
Ensure the following are set in the child process:
- `TERM=xterm-256color` (or `vt100` for basic testing).
- `COLORTERM=truecolor` (to enable 24-bit color support).

### 4. Implementation Reference (Cross-Comparison)

| Feature | Vtui Current | Ghostty Reference | Foot Reference | Action |
| :--- | :--- | :--- | :--- | :--- |
| **Session** | Inherited | `setsid()` | `setsid()` | **Add `setsid()`** |
| **TTY Control** | None | `TIOCSCTTY` | Inherited Slave | **Add `TIOCSCTTY`** |
| **Signals** | Inherited | Reset All | Reset Mask | **Reset Mask** |
| **Non-blocking** | Poll-only | `O_NONBLOCK` | `O_NONBLOCK` | **Set `O_NONBLOCK`** |

## Verification Steps
1. **Basic Output**: `vtui --run "echo hello"` should print `hello` (no hex garbage).
2. **Interactive TUI**: `vtui btop` should render the UI correctly.
3. **Resize**: Ensure `TIOCSWINSZ` works after the process has started.
