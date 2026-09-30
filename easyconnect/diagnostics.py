"""Attach processing stages to errors without changing their original types."""

from contextvars import ContextVar
import sys


verbose = ContextVar("easyconnect_verbose", default=False)


def step(label, action, *args, **kwargs):
    if verbose.get():
        print("[EasyConnect] " + label, file=sys.stderr)
    try:
        return action(*args, **kwargs)
    except (ValueError, OSError) as error:
        error.easyconnect_stages = [label] + getattr(error, "easyconnect_stages", [])
        raise


def describe(error):
    stages = getattr(error, "easyconnect_stages", [])
    return "Stage: {}\nReason: {}".format(" -> ".join(stages) if stages else "command setup", error)


def fail(label, message):
    error = ValueError(message)
    error.easyconnect_stages = [label]
    raise error
