import os, socket, subprocess, sys
def p(k, v): print(f"PROBE {k}: {v}", flush=True)
which = sys.argv[1]
OUT = r"@OUTSIDE_WIN@"
SECRET = os.path.join(OUT, "secret.txt")
if which == "read":
    try: open(SECRET).read(); p("read", "READ-OK")
    except Exception as e: p("read", f"denied ({type(e).__name__}: {e.strerror if hasattr(e,'strerror') else e})")
elif which == "write":
    try: open(os.path.join(OUT, "pwned_py.txt"), "w").write("x"); p("write", "WRITE-OK")
    except Exception as e: p("write", f"denied ({type(e).__name__})")
elif which == "net":
    for host, port in [("example.com", 80), ("93.184.215.14", 80), ("1.1.1.1", 443), ("127.0.0.1", 47123)]:
        try:
            s = socket.create_connection((host, port), timeout=6); s.close(); p(f"tcp {host}:{port}", "CONNECTED")
        except Exception as e: p(f"tcp {host}:{port}", f"blocked ({type(e).__name__}: {e})")
    try: s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(); p("listen 127.0.0.1", "LISTEN-OK (bind allowed)")
    except Exception as e: p("listen 127.0.0.1", f"blocked ({e})")
elif which == "mem":
    chunks = []
    try:
        for i in range(64): chunks.append(bytearray(64 * 1024 * 1024))
        p("mem", f"ALLOCATED {len(chunks)*64} MB")
    except MemoryError: p("mem", f"MemoryError after {len(chunks)*64} MB")
elif which == "procs":
    ok, fail = 0, 0; ps = []
    for i in range(20):
        try: ps.append(subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(4)"])); ok += 1
        except OSError as e: fail += 1; err = e
    p("procs", f"started {ok}, failed {fail}" + (f" ({err})" if fail else ""))
    for x in ps: x.wait()
elif which == "breakaway":
    try:
        subprocess.Popen(["cmd", "/c", "echo x"], creationflags=0x01000000)  # CREATE_BREAKAWAY_FROM_JOB
        p("breakaway", "STARTED")
    except OSError as e: p("breakaway", f"refused ({e})")
elif which == "spin":
    while True: pass
