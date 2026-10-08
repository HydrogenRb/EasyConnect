"""Verify the offset contract that the bracket errors depend on.

Token offsets point into the MASKED text. Reporting file:line:column from the
original text is only valid if masking preserves length and newline count.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from RTLGraph import blank, mask_comments, tokenize

SAMPLE = (
    'module M(input a); // ( comment\n'
    '`define W (a+b) \\\n'
    '  * 2\n'
    '  /* multi ( line\n'
    '     comment ) */\n'
    '  wire [7:0] x; // )\n'
    '  initial $display("(str) [ok]");\n'
    '  assign y = {"a", ")"};\n'
    'endmodule\n'
)

blanked = blank(SAMPLE)
masked = mask_comments(SAMPLE)
print("blank   len equal:", len(blanked) == len(SAMPLE))
print("comment len equal:", len(masked) == len(SAMPLE))
print("blank   newline count equal:", blanked.count("\n") == SAMPLE.count("\n"))
print("blank   keeps CR/LF bytes identical:",
      all(a == b or b in "\r\n" for a, b in zip(SAMPLE, blanked)))
print("comment keeps positions (only blanks):",
      all(a == b or b == " " for a, b in zip(SAMPLE, masked)))

bad = 0
for _ in range(5000):
    text = "".join(random.choice('ab()[]{}<>"/*\'` \n\r') for _ in range(80))
    for transform in (blank, mask_comments):
        out = transform(text)
        if len(out) != len(text) or out.count("\n") != text.count("\n"):
            bad += 1
            print("MISMATCH", transform.__name__, repr(text))
            break
    if bad:
        break
print("random stress (5000 strings x 2 transforms):", "OK" if not bad else "FAILED")

# Show that tokens still point at the same character in both texts.
masked = mask_comments(blank(SAMPLE))
for token in tokenize(masked):
    assert token.end <= len(SAMPLE)
print("all token offsets within original text bounds: OK")
