import zipfile, glob, re, os, shutil, sys
exe, cache, dst = sys.argv[1:4]
zipfile.ZipFile(exe).extractall(os.path.join(dst, "par"))
for f in glob.glob(os.path.join(cache, "*.pm")):
    m = re.search(r"^\s*package\s+([\w:]+)\s*;", open(f, encoding="latin-1").read(), re.M)
    if not m: continue
    rel = os.path.join(dst, "par", "lib", *m.group(1).split("::")) + ".pm"
    if not os.path.exists(rel):
        os.makedirs(os.path.dirname(rel), exist_ok=True); shutil.copy(f, rel)
