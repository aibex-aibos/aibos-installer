"""client.py: talk to a running installer in test mode (tests only).

usage: client.py <test-url-file> get [lang=de]
       client.py <test-url-file> post step=<s> choice=<c> [field=value ...]
       client.py <test-url-file> raw <method> <path> [header=value ...]   (for checks of the server)

Prints the HTTP status in the first line and the body after it.
"""
import sys
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main():
    url_file, mode, *rest = sys.argv[1:]
    url = open(url_file).read().strip()
    parts = urllib.parse.urlsplit(url)
    base = f"{parts.scheme}://{parts.netloc}"
    token = urllib.parse.parse_qs(parts.query)["t"][0]
    opener = urllib.request.build_opener(NoRedirect)
    fields = dict(f.split("=", 1) for f in rest if "=" in f and mode != "raw")
    if mode == "get":
        query = {"t": token, **fields}
        req = urllib.request.Request(f"{base}/?{urllib.parse.urlencode(query)}")
    elif mode == "post":
        data = urllib.parse.urlencode({"t": token, **fields}).encode()
        req = urllib.request.Request(f"{base}/decision?t={token}", data=data, method="POST")
        req.add_header("Origin", base)
    elif mode == "raw":
        method, path, *headers = rest
        path = path.replace("TOKEN", token)
        data = b"" if method == "POST" else None
        req = urllib.request.Request(f"{base}{path}", data=data, method=method)
        for h in headers:
            k, v = h.split("=", 1)
            req.add_header(k, v.replace("BASE", base))
    else:
        sys.exit(f"unknown mode {mode}")
    try:
        with opener.open(req, timeout=60) as resp:
            print(resp.status)
            print(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(e.code)
        print(e.read().decode(errors="replace"))
    except (urllib.error.URLError, ConnectionError) as e:
        print("000")
        print(e)


if __name__ == "__main__":
    main()
