import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from RTLGraph import mask_comments, tokenize

target = Path(__file__).resolve().parents[1] / "brk4" / "TOP.v"
raw = target.read_bytes()
text = raw.decode("utf-8-sig")
print("bytes:", len(raw), "chars:", len(text), "lines:", text.count("\n") + 1)
print("tail repr:", repr(text[-90:]))
masked = mask_comments(text)
print("masked len equal:", len(masked) == len(text))
print("masked tail repr:", repr(masked[-90:]))
opens = [t for t in tokenize(masked) if t.value in "([{"]
closes = [t for t in tokenize(masked) if t.value in ")]}"]
print("openers:", len(opens), "closers:", len(closes))
print("last opener:", repr(opens[-1].value), opens[-1].start if opens else None)
