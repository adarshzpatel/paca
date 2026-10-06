#!/usr/bin/env python3
"""Rewrite SVG path arcs with packed flags ("a1 1 0 01-2 2") into spaced form ("a1 1 0 0 1 -2 2").

macOS's SVG reader (CoreSVG) rejects packed arc flags, which minified SVGs use, and draws
nothing. Reads stdin, writes stdout."""
import re
import sys

NUMBER = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


def expand(d: str) -> str:
    out, i = [], 0
    for match in re.finditer(r"([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)", d):
        command, args = match.groups()
        if command not in "Aa":
            out.append(command + args)
            continue
        params, rest = [], args
        while True:
            rest = rest.lstrip(" ,")
            if not rest:
                break
            # Positions 3 and 4 of each 7-value arc are single-character flags.
            if len(params) % 7 in (3, 4):
                params.append(rest[0])
                rest = rest[1:]
                continue
            number = re.match(NUMBER, rest)
            if not number:
                break
            params.append(number.group(0))
            rest = rest[number.end():]
        out.append(command + " ".join(params))
    return "".join(out)


svg = sys.stdin.read()
sys.stdout.write(re.sub(r'\bd="([^"]*)"', lambda m: 'd="%s"' % expand(m.group(1)), svg))
