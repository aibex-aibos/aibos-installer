"""aios_installer.py: entry of the AIBOS installer (spec 01–06 in @Spec/Installer of AA-AIbex-AIOS).

usage: aios_installer.py start "distribution-<name>==<version>" <commit> [--cleanup <dir>]
       aios_installer.py serve "distribution-<name>==<version>" <commit> --home <home> [--cleanup <dir>] [--ready-fd <fd>]
       aios_installer.py tui   "distribution-<name>==<version>" <commit> --home <home> [--cleanup <dir>]

start runs the dialog server detached and returns as soon as it runs (spec 02, step 6).
"""
import os
import secrets
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import webbrowser
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # -I leaves the script folder out

import server  # noqa: E402
import steps   # noqa: E402

VERSION = "0.1.0"
BASE = Path(__file__).resolve().parent.parent      # installer/, i18n/, legal/
TIMEOUT = 30 * 60                                  # seconds without a request (spec 03)
FALLBACK = 20                                      # seconds until the switch to the terminal (spec 03)


def parse(argv: list) -> dict:
    opts = {"cleanup": "", "home": str(Path.home()), "ready_fd": -1}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--cleanup", "--home", "--ready-fd") and i + 1 < len(argv):
            opts[a[2:].replace("-", "_")] = argv[i + 1]
            i += 2
            continue
        pos.append(a)
        i += 1
    if len(pos) != 2:
        raise SystemExit(__doc__)
    opts["dist"], opts["commit"] = pos
    opts["ready_fd"] = int(opts["ready_fd"])
    return opts


def test_seconds(name: str, default: int, test: bool) -> float:
    if test and os.environ.get(name):
        return float(os.environ[name])
    return default


def cleanup_dir(path: str) -> None:
    """Remove the temporary folder of the formula, and only that (spec 02, step 5)."""
    if not path:
        return
    real = os.path.realpath(path)
    roots = [os.path.realpath(tempfile.gettempdir()), "/private/tmp", "/private/var/folders"]
    if os.path.basename(real).startswith("aios-installer.") and any(real.startswith(r.rstrip("/") + "/") for r in roots):
        shutil.rmtree(real, ignore_errors=True)


# --- start ---------------------------------------------------------------------------------------------------

def cmd_start(o: dict) -> int:
    home = Path(o["home"])
    try:
        steps.test_mode(home)
    except SystemExit as e:
        print(e)
        return 2
    if not steps.DIST_RE.match(o["dist"]) or not steps.COMMIT_RE.match(o["commit"]):
        print(f"AIBOS installer: bad arguments: {o['dist']} {o['commit']}")
        return 2
    r, w = os.pipe()
    args = [sys.executable, "-I", os.path.abspath(__file__), "serve", o["dist"], o["commit"],
            "--home", str(home), "--ready-fd", str(w)]
    if o["cleanup"]:
        args += ["--cleanup", o["cleanup"]]
    subprocess.Popen(args, pass_fds=(w,), start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=str(home))
    os.close(w)
    ready, _, _ = select.select([r], [], [], 30)
    line = os.read(r, 4096).decode(errors="replace").strip() if ready else ""
    os.close(r)
    if line == "READY":
        return 0
    print(f"AIBOS installer: {line or 'no answer from the dialog'}")
    return 6


# --- serve ---------------------------------------------------------------------------------------------------

def report(fd: int, text: str) -> None:
    if fd >= 0:
        try:
            os.write(fd, (text + "\n").encode())
            os.close(fd)
        except OSError:
            pass


def open_browser(url: str) -> bool:
    try:
        if subprocess.run(["open", url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, timeout=20).returncode == 0:
            return True
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        return webbrowser.open(url)
    except webbrowser.Error:
        return False


def private_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)


def to_terminal(run, o: dict) -> None:
    """Switch to the dialog in a Terminal window (spec 03, Ausweg Terminal)."""
    if not o["cleanup"]:                   # started without the formula: own folder, removed by tui
        o["cleanup"] = tempfile.mkdtemp(prefix="aios-installer.")
    script = Path(o["cleanup"]) / "AIBOS-Installer.command"
    lines = ["#!/bin/sh", 'printf "\\033]0;AIBOS-Installer\\007"']
    cmd = [sys.executable, "-I", os.path.abspath(__file__), "tui", o["dist"], o["commit"], "--home", o["home"]]
    if o["cleanup"]:
        cmd += ["--cleanup", o["cleanup"]]
    lines.append("exec " + " ".join("'" + c.replace("'", "'\\''") + "'" for c in cmd))
    script.write_text("\n".join(lines) + "\n")
    os.chmod(script, 0o700)
    run.note(f"terminal: open -a Terminal {script}")
    if run.test and os.environ.get("AIOS_INSTALLER_TERMINAL") == "log":
        private_write(run.aios / "install" / "test-terminal", f"open -a Terminal {script}\n")
        return
    subprocess.run(["open", "-a", "Terminal", str(script)], stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # open -a does not bring Terminal in front of the app that started us (probe, Memo 28): activate it
    try:                                   # may need the macOS permission "control Terminal"; best effort
        subprocess.run(["osascript", "-e", 'tell application "Terminal"', "-e", "delay 1",
                        "-e", 'set index of (first window whose name contains "AIBOS-Installer") to 1',
                        "-e", "activate", "-e", "end tell"], stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    except (OSError, subprocess.SubprocessError):
        pass


class Terminated(Exception):
    """SIGTERM or SIGHUP: the run ends like "Abbrechen" (H23)."""


def on_signal(signum, frame):
    raise Terminated(signal.Signals(signum).name)


def catch_signals() -> None:
    for s in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, on_signal)


def cmd_serve(o: dict) -> int:
    home = Path(o["home"])
    fd = o["ready_fd"]
    try:
        test = steps.test_mode(home)
        run = steps.Run(BASE, home, o["dist"], o["commit"], VERSION, test, "test" if test else "browser")
        app = server.App(run, secrets.token_urlsafe(32), BASE / "installer" / "templates")
        srv = server.http.server.HTTPServer(("127.0.0.1", 0), server.make_handler(app))
    except (SystemExit, OSError) as e:
        report(fd, f"ERROR {e}")
        return 6
    app.port = srv.server_address[1]
    srv.timeout = 0.5
    url = f"http://127.0.0.1:{app.port}/?t={app.token}"
    timeout = test_seconds("AIOS_INSTALLER_TIMEOUT", TIMEOUT, test)
    fallback = test_seconds("AIOS_INSTALLER_FALLBACK", FALLBACK, test)
    report(fd, "READY")
    handed_over = False
    if test:
        private_write(home / ".aios" / "install" / "test-url", url + "\n")
        opened = True
    else:
        opened = open_browser(url)
    start = app.last = time.time()
    catch_signals()
    try:
        while True:
            if not opened or (not app.got_get and time.time() - start > fallback):
                app.active = False                 # the token is no longer valid
                to_terminal(run, o)
                handed_over = True
                break
            srv.handle_request()
            now = time.time()
            if run.step == "end":
                if app.end_served or now - run.ended_at_time > 5:
                    break
            elif not run.busy and now - app.last > timeout:
                with run.lock:
                    run.finish("timeout", "no answer within the time limit")
    except Terminated as e:
        with run.lock:
            run.finish("aborted", f"ended by {e} on page {run.step}")
    finally:
        srv.server_close()
        run.close()
        if not handed_over:
            cleanup_dir(o["cleanup"])
    return 0


# --- tui -----------------------------------------------------------------------------------------------------

def cmd_tui(o: dict) -> int:
    home = Path(o["home"])
    test = steps.test_mode(home)
    run = steps.Run(BASE, home, o["dist"], o["commit"], VERSION, test, "terminal")
    print("\033]0;AIBOS-Installer\007", end="")
    catch_signals()
    try:
        while True:
            p = run.page()
            print("\n" + "=" * 72)
            print(f"{run.t('title')} — {run.t('subtitle')}")
            print(p["head"])
            print("=" * 72)
            if p["banner"]:
                print(f"!! {p['banner']}")
            if p["error"]:
                print(f"** {p['error']}")
            for para in p["paras"]:
                print("\n" + para)
            marks = {"done": "[x]", "run": "[~]", "todo": "[ ]"}
            for label, state, secs in p["phases"]:
                print(f"   {marks[state]} {label}" + (f"  {secs // 60}:{secs % 60:02d}" if secs is not None else ""))
            if p["pre"]:
                print("\n" + p["pre"])
            if run.step == "end":
                return 0
            if p["refresh"]:
                time.sleep(2)
                continue
            fields = {}
            if p["offer_parent"]:
                if input(run.t("tui_create")).strip().lower() in ("j", "y", "ja", "yes"):
                    run.decide("3", "create", dict(run.form))
                    continue
            if p["form"] == "agree":
                fields["agree"] = "on" if input(f"\n{run.t('p2_check')}? [j/y/N] ").strip().lower() in ("j", "y", "ja", "yes") else ""
            elif p["form"] == "workspace":
                existing = input(f"\n1 {run.t('p3_new')}\n2 {run.t('p3_existing')}\n{run.t('tui_choice')}: ").strip() == "2"
                if existing:
                    for i, (path, kind) in enumerate(run.known_vaults(), 1):
                        print(f"   {path}  ({kind})")
                    fields.update(mode="existing", path=input(f"{run.t('p3_path')}: ").strip())
                else:
                    fields.update(mode="new", name=input(f"{run.t('p3_name')}: ").strip(),
                                  parent=input(f"{run.t('p3_parent')} [~]: ").strip() or "~")
            choices = p["choices"] + [("abort", run.t("abort"))]
            print()
            for i, (_, label) in enumerate(choices, 1):
                print(f"{i} {label}")
            answer = input(f"{run.t('tui_choice')}: ").strip()
            if answer.isdigit() and 1 <= int(answer) <= len(choices):
                run.decide(run.step, choices[int(answer) - 1][0], fields)
    except (EOFError, KeyboardInterrupt, Terminated):
        with run.lock:
            run.finish("aborted", f"terminal closed on page {run.step}")
        return 0
    finally:
        run.close()
        cleanup_dir(o["cleanup"])


def main(argv: list) -> int:
    if not argv or argv[0] not in ("start", "serve", "tui"):
        print(__doc__)
        return 2
    o = parse(argv[1:])
    return {"start": cmd_start, "serve": cmd_serve, "tui": cmd_tui}[argv[0]](o)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
