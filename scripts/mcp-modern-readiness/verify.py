#!/usr/bin/env python3
"""Validate actual request/response evidence; task20 deliberate RED boundary."""
import json
import sys


def verify(trace, *, installed=False, required_surfaces=()):
    raise NotImplementedError("task21 readiness trace verification not implemented")


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as stream:
        trace = json.load(stream)
    verify(trace)
