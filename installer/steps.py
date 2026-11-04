"""steps.py: the run of the installer — pages, decisions, workspace, kernel, result (spec 03, 05)."""
import datetime
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

import consent

KERNEL_REPO = "https://github.com/aibex-aios/aibex-aios"
MANIFEST_URL = "https://raw.githubusercontent.com/aibex-aios/{dist}/v{dv}/manifest.yaml"
DIST_RE = re.compile(r"^(distribution-[a-z0-9][a-z0-9-]*)==([0-9]+\.[0-9]+\.[0-9]+(?:-rc[0-9]+)?)$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
KERNEL_RE = re.compile(r'^kernel:\s*"?==\s*([0-9]+\.[0-9]+\.[0-9]+(?:-rc[0-9]+)?)"?\s*$', re.M)
VAULT_LINE_RE = re.compile(r"^\s*(aios \S+|alt \S+|legacy|none)\s+(/.+?)\s+\(([^)]*)\)\s*$")


def now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def test_mode(home: Path) -> bool:
    """True with AIOS_INSTALLER_TEST=1; raises if the test switch is used outside a sandbox (spec 06)."""
    if os.environ.get("AIOS_INSTALLER_TEST") != "1":
        return False
    roots = {os.path.realpath(tempfile.gettempdir()), "/private/tmp", "/private/var/folders"}
    real = os.path.realpath(home)
    if not any(real == r or real.startswith(r.rstrip("/") + "/") for r in roots):
        raise SystemExit("AIBOS installer: test mode needs a HOME below the temporary folder. Nothing has been installed.")
    if not os.environ.get("AIOS_HUBS"):
        raise SystemExit("AIBOS installer: test mode needs AIOS_HUBS. Nothing has been installed.")
    return True


def system_language() -> str:
    """de if the first language of macOS (else LANG) starts with de, otherwise en (F116)."""
    try:
        out = subprocess.run(["defaults", "read", "-g", "AppleLanguages"], capture_output=True,
                             text=True, timeout=5).stdout
        first = re.search(r'"?([A-Za-z]{2})[-_A-Za-z]*"?', out.split("(", 1)[-1])
        if first:
            return "de" if first.group(1).lower() == "de" else "en"
    except (OSError, subprocess.SubprocessError):
        pass
    return "de" if os.environ.get("LANG", "").lower().startswith("de") else "en"


class Run:
    """State of one run: step, decisions, workspace, kernel, result."""

    def __init__(self, base: Path, home: Path, dist_spec: str, commit: str, version: str,
                 test: bool, way: str, python: str = ""):
        m = DIST_RE.match(dist_spec)
        if not m or not COMMIT_RE.match(commit):
            raise SystemExit(f"AIBOS installer: bad arguments: {dist_spec} {commit}")
        self.base, self.home = base, home
        self.aios = home / ".aios"
        self.dist, self.dv, self.commit = m.group(1), m.group(2), commit
        self.version, self.test, self.way = version, test, way
        self.python = python                     # the python3 the formula found (B25, Memo 32)
        self.lang = system_language()
        self.texts = {l: json.loads((base / "i18n" / f"{l}.json").read_text(encoding="utf-8")) for l in ("de", "en")}
        self.legal = consent.legal_version(base)
        self.step = "1"              # 1, 2, 3, 3-run, 4a, 4a-run, 4b, 5, end
        self.error = ""
        self.status = ""
        self.message = ""
        self.ended_step = ""
        self.vault: Path | None = None
        self.vault_new = False
        self.vault_created = False
        self.parent_new: Path | None = None     # missing parent folder, created after the final consent (Memo 27)
        self.parent_created = False
        self.offer_parent = ""                  # parent the user may agree to create (page 3)
        self.form: dict = {}                    # last input on page 3, shown again after an error
        self.phases: list[str] = []             # progress (Memo 27): keys in order
        self.phase_state: dict = {}             # key -> todo, run, done
        self.phase_t0: dict = {}
        self.run_t0 = 0.0
        self.kernel = ""
        self.plan = ""
        self.progress: list[str] = []
        self.busy = False
        self.consent_file: Path | None = None
        self.started_at = now_iso()
        self.ended_at_time = 0.0
        self.stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        self.log: list[str] = [f"{self.started_at} start {self.dist}=={self.dv} commit {self.commit} installer {self.version}"]
        self.lock = threading.RLock()
        self.workdir = Path(tempfile.mkdtemp(prefix="aios-installer-work."))

    # --- texts -------------------------------------------------------------------------------------------

    def t(self, key: str, **kw) -> str:
        text = self.texts[self.lang].get(key) or self.texts["en"].get(key, key)
        return text.format(dist=self.dist, dv=self.dv, version=self.legal, kernel=self.kernel,
                           dist_line=self.dist_line, **kw)

    @property
    def dist_line(self) -> str:
        """Capricorn V0.4 (distribution-capricorn @ v0.4.0) — name, version line and exact tag (Memo 25)."""
        name = " ".join(w.capitalize() for w in self.dist.removeprefix("distribution-").split("-"))
        major, minor = self.dv.split(".")[:2]
        return f"{name} V{major}.{minor} ({self.dist} @ v{self.dv})"

    def note(self, line: str) -> None:
        self.log.append(f"{now_iso()} {line}")

    # --- environment of aios -----------------------------------------------------------------------------

    def env(self) -> dict:
        e = dict(os.environ)
        e["HOME"] = str(self.home)
        e["GIT_TERMINAL_PROMPT"] = "0"     # never ask for credentials, also not in the terminal dialog
        if self.python:                    # the kernel looks for python3 in PATH only (B25)
            first = os.path.dirname(os.path.abspath(self.python))
            e["PATH"] = first + os.pathsep + e.get("PATH", "")
        return e

    def run_cmd(self, args: list, cwd: Path | None = None, stream: bool = False) -> tuple[int, str]:
        """Run a command with a list of arguments (no shell); stream lines into progress if asked."""
        self.note("$ " + " ".join(str(a) for a in args))
        try:
            p = subprocess.Popen([str(a) for a in args], cwd=str(cwd or self.home), env=self.env(),
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        except OSError as e:
            self.note(f"error: {e}")
            return 127, str(e)
        lines = []
        for line in p.stdout:
            line = line.rstrip("\n")
            lines.append(line)
            if stream:
                with self.lock:
                    self.progress.append(line)
        rc = p.wait()
        out = "\n".join(lines)
        self.log.extend(lines)
        self.note(f"exit {rc}")
        return rc, out

    @property
    def forwarder(self) -> Path:
        return self.aios / "bin" / "aios"

    def kernel_installed(self) -> bool:
        prefix = Path(os.environ.get("AIOS_PREFIX", "/opt/aios"))
        return (self.aios / "versions" / f"v{self.kernel}").is_dir() or (prefix / f"v{self.kernel}").is_dir()

    def kernel_ready(self) -> bool:
        """Version installed, forwarder executable and its hooks in settings.json (B28: after --uninstall)."""
        if not self.kernel_installed() or not os.access(self.forwarder, os.X_OK):
            return False
        claude = Path(os.environ.get("AIOS_CLAUDE_DIR", str(self.home / ".claude")))
        try:
            return str(self.forwarder) in (claude / "settings.json").read_text(encoding="utf-8")
        except OSError:
            return False

    # --- decisions (spec 03, Server: only for the current step) ----------------------------------------

    def decide(self, step: str, choice: str, fields: dict) -> None:
        with self.lock:
            if self.busy or step != self.step or self.step == "end":
                return
            self.error = ""
            if choice == "abort":
                self.finish("aborted", f"cancelled on page {step}")
                return
            if step == "1" and choice == "next":
                self.step = "3" if consent.has_consent(self.home, self.legal) else "2"
            elif step == "2" and choice == "agree":
                if fields.get("agree") != "on":
                    self.error = self.t("p2_need_check")
                    return
                self.consent_file = consent.write_consent(self.home, self.base, self.legal, self.lang, self.way,
                                                          self.version, self.dist)
                self.note(f"consent {self.consent_file}")
                self.step = "3"
            elif step == "3" and choice in ("next", "create"):
                if self.choose_workspace(fields, create=(choice == "create")):
                    self.start_worker(self.prepare_plans, "3-run")
            elif step == "4a" and choice == "install":
                self.start_worker(self.install_kernel, "4a-run")
            elif step == "4b" and choice == "install":
                self.start_worker(self.install_distribution, "5")

    def start_worker(self, target, step: str) -> None:
        self.busy = True
        self.step = step
        self.progress = []
        self.run_t0 = time.time()
        threading.Thread(target=self._work, args=(target,), daemon=True).start()

    def _work(self, target) -> None:
        try:
            target()
        except Exception as e:  # noqa: BLE001 - every failure ends the run with a result
            with self.lock:
                self.finish("failed", f"internal error: {e}")
        finally:
            with self.lock:
                self.busy = False

    # --- progress: phases with state and time (Memo 27) -------------------------------------------------

    def set_phases(self, kernel_needed: bool) -> None:
        keys = (["clone", "plan_kernel", "install_kernel"] if kernel_needed else []) + ["plan_dist"]
        keys += (["mkdir"] if self.vault_new else []) + ["install_dist"]
        self.phases = keys
        self.phase_state = {k: "todo" for k in keys}

    def phase(self, key: str) -> None:
        with self.lock:
            for k, v in self.phase_state.items():
                if v == "run":
                    self.phase_state[k] = "done"
            if key in self.phase_state:
                self.phase_state[key] = "run"
                self.phase_t0[key] = time.time()

    def phase_done(self) -> None:
        with self.lock:
            for k, v in self.phase_state.items():
                if v == "run":
                    self.phase_state[k] = "done"

    # --- page 3: workspace (spec 05, Arbeitsbereich) ----------------------------------------------------

    def known_vaults(self) -> list[tuple[str, str]]:
        if not os.access(self.forwarder, os.X_OK):
            return []
        try:
            out = subprocess.run([str(self.forwarder), "--vaults"], capture_output=True, text=True,
                                 env=self.env(), cwd=str(self.home), stdin=subprocess.DEVNULL, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            return []
        vaults = []
        for line in out.splitlines():
            m = VAULT_LINE_RE.match(line)
            if m:
                vaults.append((m.group(2), m.group(1)))
        return vaults

    def readable(self, path: Path) -> bool:
        try:
            os.listdir(path)
            return True
        except OSError:
            return False

    def creatable_parent(self, parent: Path) -> bool:
        """A missing parent may be created below ~, outside ~/.aios and vaults, under a readable folder."""
        if not parent.is_absolute():
            return False
        existing = parent
        while not existing.exists():
            existing = existing.parent
        home = os.path.realpath(self.home)
        real = os.path.realpath(existing)
        if not (real == home or real.startswith(home + "/")) or not existing.is_dir() or not self.readable(existing):
            return False
        return not any(part.startswith("§") for part in parent.parts)

    def choose_workspace(self, fields: dict, create: bool = False) -> bool:
        mode = fields.get("mode", "new")
        self.form = {k: fields.get(k, "") for k in ("mode", "name", "parent", "path", "known")}
        self.parent_new = None
        if mode != "new":
            self.offer_parent = ""
        if mode == "new":
            name = fields.get("name", "").strip()
            parent = Path(os.path.expanduser(fields.get("parent", "~").strip() or "~"))
            if not name or not all(c.isalpha() or c.isdigit() or c in "-_" for c in name):
                self.error = self.t("err_name")
                return False
            if not parent.is_dir():
                if self.creatable_parent(parent):
                    if create and self.offer_parent == str(parent):
                        self.parent_new = Path(os.path.normpath(parent))
                    else:
                        self.offer_parent = str(parent)
                        self.error = self.t("err_parent_create", parent=parent)
                        return False
                else:
                    outer = next((q for q in [parent, *parent.parents] if q.name.startswith("§")), None)
                    self.error = (self.t("err_in_vault", path=parent / f"§{name}", vault=outer) if outer
                                  else self.t("err_parent", parent=parent))
                    return False
            elif not self.readable(parent):
                self.error = self.t("err_unreadable", path=parent)
                return False
            self.offer_parent = ""
            base = self.parent_new if self.parent_new else Path(os.path.realpath(parent))
            target = base / f"§{name}"
            if self.inside_aios(target):
                self.error = self.t("err_in_aios", path=target)
                return False
            outer = next((p for p in target.parents if p.name.startswith("§")), None)
            if outer:
                self.error = self.t("err_in_vault", path=target, vault=outer)
                return False
            if target.exists() and (not target.is_dir() or not self.readable(target) or any(target.iterdir())):
                self.error = self.t("err_not_empty", path=target)
                return False
            self.vault, self.vault_new = target, True
        else:
            raw = (fields.get("path") or fields.get("known") or "").strip()
            path = Path(os.path.expanduser(raw)) if raw else Path("")
            if not raw or not path.is_dir():
                self.error = self.t("err_missing", path=raw or "—")
                return False
            if not self.readable(path):
                self.error = self.t("err_unreadable", path=path)
                return False
            path = Path(os.path.realpath(path))
            if not path.name.startswith("§"):
                self.error = self.t("err_no_section", path=path)
                return False
            if self.inside_aios(path):
                self.error = self.t("err_in_aios", path=path)
                return False
            self.vault, self.vault_new = path, False
        self.note(f"workspace {self.vault} new={self.vault_new}")
        return True

    def inside_aios(self, path: Path) -> bool:
        aios = os.path.realpath(self.aios)
        return str(path) == aios or str(path).startswith(aios + "/")

    # --- pages 4a, 4b: kernel and plans (spec 05, Kernel) ---------------------------------------------

    def read_kernel_version(self) -> str:
        if self.test and os.environ.get("AIOS_INSTALLER_MANIFEST"):
            text = Path(os.environ["AIOS_INSTALLER_MANIFEST"]).read_text(encoding="utf-8")
        else:
            url = MANIFEST_URL.format(dist=self.dist, dv=self.dv)
            with urllib.request.urlopen(url, timeout=30) as r:
                text = r.read().decode("utf-8")
        m = KERNEL_RE.search(text)
        if not m:
            raise RuntimeError(f"{self.dist} {self.dv} names no kernel (kernel:); installer 0.1.0 needs one")
        return m.group(1)

    def kernel_repo(self) -> str:
        if self.test and os.environ.get("AIOS_INSTALLER_KERNEL_REPO"):
            return os.environ["AIOS_INSTALLER_KERNEL_REPO"]
        return KERNEL_REPO

    def checkout_checked(self, clone: Path) -> bool:
        """Check out v<k> and require that it is the commit of the line (IN9)."""
        rc, _ = self.run_cmd(["git", "-C", clone, "checkout", "-q", "--detach", f"v{self.kernel}"])
        if rc != 0:
            self.finish("failed", f"tag v{self.kernel} not found in the kernel repository")
            return False
        rc, head = self.run_cmd(["git", "-C", clone, "rev-parse", "HEAD"])
        if rc != 0 or head.strip() != self.commit:
            self.finish("failed", f"tag v{self.kernel} points to {head.strip()[:12]}, not to {self.commit[:12]} "
                                  "(the commit of the install line); nothing installed")
            return False
        return True

    def prepare_plans(self) -> None:
        try:
            self.kernel = self.read_kernel_version()
        except Exception as e:  # noqa: BLE001
            self.finish("failed", f"cannot read the manifest of {self.dist} {self.dv}: {e}")
            return
        self.note(f"kernel {self.kernel}, installed={self.kernel_installed()}, ready={self.kernel_ready()}")
        self.set_phases(not self.kernel_ready())
        if self.kernel_ready():
            self.plan_distribution()
            return
        clone = self.workdir / "aibex-aios"
        self.phase("clone")
        if not clone.is_dir():
            rc, out = self.run_cmd(["git", "clone", "-q", self.kernel_repo(), clone])
            if rc != 0:
                self.finish("failed", f"cannot clone the kernel from {self.kernel_repo()} (not reachable or not "
                                      f"public): {last_line(out)}")
                return
        if not self.checkout_checked(clone):
            return
        self.phase("plan_kernel")
        rc, out = self.run_cmd([clone / "bin" / "aios", "--install", f"v{self.kernel}", "--plan"], cwd=self.home)
        if rc != 0:
            self.finish("failed", f"the plan of the kernel failed: {last_line(out)}")
            return
        self.plan = out
        self.phase_done()
        self.step = "4a"

    def plan_distribution(self) -> None:
        if not os.access(self.forwarder, os.X_OK):
            self.finish("failed", f"kernel {self.kernel} is installed, but {self.forwarder} is missing")
            return
        self.phase("plan_dist")
        rc, out = self.run_cmd([self.forwarder, "--install", f"{self.dist}=={self.dv}", self.vault, "--plan"],
                               cwd=self.home)
        if rc != 0:
            self.finish("failed", f"the plan of the distribution failed: {last_line(out)}")
            return
        self.plan = out
        self.phase_done()
        self.step = "4b"

    def install_kernel(self) -> None:
        self.phase("install_kernel")
        target = self.aios / "installer" / "aibex-aios"
        if target.is_dir():
            rc, out = self.run_cmd(["git", "-C", target, "fetch", "-q", "--tags"], stream=True)
            if rc != 0:
                with self.lock:
                    self.finish("failed", f"cannot update the kernel clone: {last_line(out)}")
                return
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(self.workdir / "aibex-aios"), str(target))
        with self.lock:
            if not self.checkout_checked(target):
                return
        rc, out = self.run_cmd([target / "bin" / "aios", "--install", f"v{self.kernel}", "--yes"], stream=True)
        with self.lock:
            if rc != 0:
                self.finish("failed", f"the kernel was not installed: {last_line(out)}")
                return
            self.plan_distribution()

    def install_distribution(self) -> None:
        if self.vault_new and not self.vault.exists():
            self.phase("mkdir")
            if self.parent_new and not self.parent_new.exists():
                os.makedirs(self.parent_new)
                self.parent_created = True
                self.note(f"created {self.parent_new}")
            os.mkdir(self.vault)
            self.vault_created = True
            self.note(f"created {self.vault}")
        self.phase("install_dist")
        rc, out = self.run_cmd([self.forwarder, "--install", f"{self.dist}=={self.dv}", self.vault, "--yes"],
                               cwd=self.home, stream=True)
        with self.lock:
            if rc != 0:
                self.finish("failed", f"the distribution was not installed: {last_line(out)}")
            else:
                self.finish("done", f"{self.dist} {self.dv} installed into {self.vault}")

    # --- end and result (spec 05, Ergebnis) -------------------------------------------------------------

    def finish(self, status: str, message: str) -> None:
        with self.lock:
            self._finish(status, message)

    def _finish(self, status: str, message: str) -> None:
        if self.step == "end":
            return
        self.phase_done()
        self.ended_step = self.step
        self.status, self.message = status, message
        self.step = "end"
        self.ended_at_time = time.time()
        self.note(f"end {status}: {message}")
        self.write_result()

    def write_result(self) -> None:
        folder = self.aios / "install"
        folder.mkdir(parents=True, exist_ok=True)
        log = folder / f"{self.stamp}.log"
        log.write_text("\n".join(self.log) + "\n", encoding="utf-8")
        result = {
            "status": self.status,
            "step": self.ended_step,
            "distribution": self.dist,
            "version": self.dv,
            "kernel": self.kernel,
            "kernel_installed": bool(self.kernel) and self.kernel_installed(),
            "vault": str(self.vault) if self.vault else "",
            "vault_created": self.vault_created,
            "parent_created": self.parent_created,
            "consent": str(consent.consent_path(self.home, self.legal)) if consent.has_consent(self.home, self.legal) else "",
            "installer": self.version,
            "started_at": self.started_at,
            "ended_at": now_iso(),
            "log": str(log),
            "message": self.message,
        }
        tmp = folder / "result.json.tmp"
        tmp.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, folder / "result.json")

    def close(self) -> None:
        shutil.rmtree(self.workdir, ignore_errors=True)

    # --- what a page shows (used by the browser and the terminal) --------------------------------------

    def page(self) -> dict:
        s = self.step
        p = {"step": s, "head": "", "paras": [], "pre": "", "error": self.error, "choices": [], "form": None,
             "banner": "", "refresh": False, "phases": [], "offer_parent": self.offer_parent if s == "3" else ""}
        if s == "1":
            p.update(head=self.t("p1_head"), paras=[self.t(f"p1_{i}") for i in range(1, 7)],
                     choices=[("next", self.t("next"))])
        elif s == "2":
            p.update(head=self.t("p2_head"), pre=consent.agreement_text(self.base, self.lang),
                     banner=self.t("p2_draft") if consent.is_draft(self.legal) else "",
                     form="agree", choices=[("agree", self.t("p2_agree"))])
        elif s == "3":
            choices = [("create", self.t("p3_create"))] if self.offer_parent else []
            p.update(head=self.t("p3_head"), paras=[self.t("p3_intro")], form="workspace",
                     choices=choices + [("next", self.t("next"))])
        elif s == "4a":
            p.update(head=self.t("p4a_head"), paras=[self.t("p4a_intro")], pre=self.plan,
                     choices=[("install", self.t("p4a_button"))])
        elif s == "4b":
            paras = [self.t("p4b_intro")]
            if self.parent_new:
                paras.append(self.t("p4b_create", path=self.parent_new))
            if self.vault_new:
                paras.append(self.t("p4b_create", path=self.vault))
            p.update(head=self.t("p4b_head"), paras=paras, pre=self.plan, choices=[("install", self.t("p4b_button"))])
        elif s in ("3-run", "4a-run", "5"):
            now = time.time()
            phases = []
            for k in self.phases:
                st = self.phase_state.get(k, "todo")
                secs = int(now - self.phase_t0[k]) if st == "run" and k in self.phase_t0 else None
                phases.append((self.t(f"ph_{k}"), st, secs))
            p.update(head=self.t({"3-run": "run_prepare", "4a-run": "run_kernel", "5": "run_dist"}[s]),
                     paras=[self.t("run_total", t=fmt_secs(int(now - self.run_t0)))],
                     phases=phases, pre="\n".join(self.progress[-20:]), refresh=True)
        else:
            key = {"done": "end_done", "aborted": "end_aborted", "failed": "end_failed",
                   "timeout": "end_timeout"}.get(self.status, "end_failed")
            p.update(head=self.t("end_head"), paras=[self.t(key, vault=self.vault, message=self.message),
                                                     self.t("end_text")])
        return p


def fmt_secs(n: int) -> str:
    return f"{n // 60}:{n % 60:02d}"


def last_line(out: str) -> str:
    lines = [l for l in out.strip().splitlines() if l.strip()]
    return lines[-1].strip() if lines else "(no output)"
