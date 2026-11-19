"""A stand-in trackside server for the simulator and the UI tests.

Serves three made-up trains from Clapham Junction (CLJ) to Woking (WOK),
leaving 5, 20 and 35 minutes after it starts, in the same JSON as a real
trackside server. Nothing else: other stations have empty boards, and the
live WebSocket isn't served, so the app just keeps retrying it.

    python3 Tools/stand-in-server.py 18081

Then set the simulator's server to http://127.0.0.1:18081.
"""
import json
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

NOW = datetime.now(timezone.utc).replace(second=0, microsecond=0)


def iso(t):
    return t.isoformat()


def train(i):
    dep = NOW + timedelta(minutes=5 + 15 * i)
    arr = dep + timedelta(minutes=25)
    uid = f"M1000{i}"
    run = dep.date().isoformat()
    op = {"code": "SW", "name": "South Western Railway"}

    # The second train runs a few minutes late, to show delays.
    late = 4 if i == 1 else 0

    def stop(code, name, kind, dep_t=None, arr_t=None, plat="1"):
        s = {"tiploc": code, "crs": code, "name": name, "kind": kind, "cancelled": False,
             "platform": {"planned": plat, "changed": False, "confirmed": True}}
        if dep_t:
            s["departure"] = {"public": iso(dep_t)}
            if late:
                s["departure"].update(estimated=iso(dep_t + timedelta(minutes=late)), delayMinutes=late, delayed=True)
        if arr_t:
            s["arrival"] = {"public": iso(arr_t)}
        return s

    summary = {"uid": uid, "runDate": run, "headcode": f"2W0{i}", "operator": op, "isPassenger": True,
               "status": "scheduled", "plannedCancel": False,
               "origin": [{"tiploc": "CLJ", "crs": "CLJ", "name": "Clapham Junction", "time": iso(dep)}],
               "destination": [{"tiploc": "WOK", "crs": "WOK", "name": "Woking", "time": iso(arr)}]}
    board = dict(summary, stop=stop("CLJ", "Clapham Junction", "origin", dep_t=dep, plat=str(7 + i)))
    detail = dict(summary, source="stand-in", stops=[
        stop("CLJ", "Clapham Junction", "origin", dep_t=dep, plat=str(7 + i)),
        stop("WOK", "Woking", "destination", arr_t=arr, plat="2"),
    ])
    return uid, board, detail


TRAINS = [train(i) for i in range(3)]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % self.path)

    def send(self, body, code=200):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        parts = path.strip("/").split("/")
        if path.endswith("/departures") or path.endswith("/arrivals"):
            code = parts[2]
            services = [b for _, b, _ in TRAINS] if code == "CLJ" else []
            return self.send({"location": {"tiploc": code, "crs": code, "name": code},
                              "from": iso(NOW), "to": iso(NOW + timedelta(hours=2)),
                              "messages": [], "services": services})
        if parts == ["v1", "locations"]:
            # Station search, and the app's check that this is a trackside server.
            return self.send({"locations": [
                {"tiploc": "CLPHMJC", "crs": "CLJ", "name": "Clapham Junction"},
                {"tiploc": "WOKING", "crs": "WOK", "name": "Woking"},
            ]})
        if parts == ["v1", "services"]:
            q = (parse_qs(urlparse(self.path).query).get("q") or [""])[0].upper()
            summaries = [{k: v for k, v in d.items() if k not in ("stops", "source")} for _, _, d in TRAINS]
            return self.send({"services": [t for t in summaries if t["headcode"].startswith(q)]})
        if parts[:2] == ["v1", "services"] and len(parts) == 4:
            for uid, _, detail in TRAINS:
                if uid == parts[2]:
                    return self.send(detail)
            return self.send({"error": "service not found"}, 404)
        return self.send({"error": "not found"}, 404)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
