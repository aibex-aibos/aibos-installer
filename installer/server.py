"""server.py: local server of the dialog (spec 03, Dialog — Server)."""
import hmac
import html
import http.server
import urllib.parse
from pathlib import Path

MAX_BODY = 64 * 1024


class App:
    """Connects the HTTP handler with the run: token, port, activity."""

    def __init__(self, run, token: str, templates: Path):
        self.run = run
        self.token = token
        self.port = 0
        self.active = True          # False after the switch to the terminal
        self.got_get = False
        self.last = 0.0
        self.end_served = False
        self.page_html = (templates / "page.html").read_text(encoding="utf-8")
        self.style = (templates / "style.css").read_text(encoding="utf-8")

    def render(self) -> str:
        run = self.run
        p = run.page()
        t = run.t
        e = html.escape
        body = []
        if p["banner"]:
            body.append(f'<p class="banner">{e(p["banner"])}</p>')
        if p["error"]:
            body.append(f'<p class="error">{e(p["error"])}</p>')
        body.extend(f"<p>{e(x)}</p>" for x in p["paras"])
        if p["phases"]:
            marks = {"done": "☑", "run": "◐", "todo": "☐"}
            items = []
            for label, state, secs in p["phases"]:
                extra = f' <span class="time">{secs // 60}:{secs % 60:02d}</span>' if secs is not None else ""
                items.append(f'<li class="{state}">{marks[state]} {e(label)}{extra}</li>')
            body.append('<ul class="phases">' + "".join(items) + "</ul>")
            body.append('<div class="bar"><span></span></div>')
        if p["pre"]:
            body.append(f'<pre>{e(p["pre"])}</pre>')
        if p["choices"] or p["form"]:
            body.append(f'<form method="post" action="/decision?t={e(self.token)}">')
            body.append(f'<input type="hidden" name="t" value="{e(self.token)}">')
            body.append(f'<input type="hidden" name="step" value="{e(p["step"])}">')
            if p["form"] == "agree":
                body.append(f'<p class="check"><label><input type="checkbox" name="agree" value="on"> {e(t("p2_check"))}</label></p>')
            elif p["form"] == "workspace":
                body.append(self.workspace_form())
            body.append('<p class="buttons">')
            for value, label in p["choices"]:
                body.append(f'<button type="submit" name="choice" value="{e(value)}">{e(label)}</button>')
            body.append(f'<button type="submit" name="choice" value="abort" class="secondary">{e(t("abort"))}</button>')
            body.append("</p></form>")
        other = "en" if run.lang == "de" else "de"
        switch = f'<a href="/?t={e(self.token)}&amp;lang={other}">{e(t("switch"))}</a>'
        refresh = '<meta http-equiv="refresh" content="2">' if p["refresh"] else ""
        return (self.page_html
                .replace("{{lang}}", run.lang)
                .replace("{{refresh}}", refresh)
                .replace("{{style}}", self.style)
                .replace("{{title}}", e(t("title")))
                .replace("{{subtitle}}", e(t("subtitle")))
                .replace("{{switch}}", switch)
                .replace("{{head}}", e(p["head"]))
                .replace("{{body}}", "\n".join(body)))

    def workspace_form(self) -> str:
        run, t, e = self.run, self.run.t, html.escape
        f = run.form
        existing = f.get("mode") == "existing"
        rows = [f'<fieldset><legend><label><input type="radio" name="mode" value="new"{"" if existing else " checked"}> {e(t("p3_new"))}</label></legend>',
                f'<label>{e(t("p3_name"))} <input name="name" autocomplete="off" value="{e(f.get("name", ""))}"></label>',
                f'<label>{e(t("p3_parent"))} <input name="parent" value="{e(f.get("parent") or "~")}"></label></fieldset>',
                f'<fieldset><legend><label><input type="radio" name="mode" value="existing"{" checked" if existing else ""}> {e(t("p3_existing"))}</label></legend>']
        vaults = run.known_vaults()
        options = "".join(f'<option value="{e(path)}">{e(path)} — {e(kind)}</option>' for path, kind in vaults)
        rows.append(f'<label>{e(t("p3_list"))} <select name="known"><option value="">{e(t("p3_none"))}</option>{options}</select></label>')
        rows.append(f'<label>{e(t("p3_path"))} <input name="path" autocomplete="off" value="{e(f.get("path", ""))}"></label></fieldset>')
        return "\n".join(rows)


def make_handler(app: App):
    import time

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "AIBOS-Installer"
        sys_version = ""

        def log_message(self, *args):          # nothing on stdout or stderr (IN3)
            pass

        def _deny(self, code: int = 403) -> None:
            self.send_response(code)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def _token_ok(self, value: str) -> bool:
            return app.active and hmac.compare_digest(value or "", app.token)

        def _host_ok(self) -> bool:
            return self.headers.get("Host") == f"127.0.0.1:{app.port}"

        def do_GET(self):
            url = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(url.query)
            if url.path != "/" or not self._host_ok() or not self._token_ok(query.get("t", [""])[0]):
                return self._deny()
            app.got_get = True
            app.last = time.time()
            lang = query.get("lang", [""])[0]
            with app.run.lock:
                if lang in ("de", "en"):
                    app.run.lang = lang
                body = app.render().encode("utf-8")
                if app.run.step == "end":
                    app.end_served = True
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'")
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            url = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(url.query)
            if url.path != "/decision" or not self._host_ok() or not self._token_ok(query.get("t", [""])[0]):
                return self._deny()
            if self.headers.get("Origin") != f"http://127.0.0.1:{app.port}":
                return self._deny()
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return self._deny(400)
            if length > MAX_BODY:
                return self._deny(413)
            form = urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", "replace"), keep_blank_values=True)
            fields = {k: v[0] for k, v in form.items()}
            if not self._token_ok(fields.get("t", "")):
                return self._deny()
            app.last = time.time()
            app.run.decide(fields.get("step", ""), fields.get("choice", ""), fields)
            self.send_response(303)
            self.send_header("Location", f"/?t={app.token}")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_PUT(self):
            self._deny(405)

        do_DELETE = do_PATCH = do_PUT

    return Handler
