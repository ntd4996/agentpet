#!/usr/bin/env python3
"""AgentPet bubble resize self-test.

Drives a running AgentPet through scripted jcode hook scenarios and analyses
~/.agentpet/metrics.log, which the app writes only when launched with
AGENTPET_METRICS=1:

  AGENTPET_METRICS=1 /Applications/AgentPet.app/Contents/MacOS/agentpet &
  scripts/bubble_selftest.py

  content w=.. h=..  -> SwiftUI measured a new content size
  window  w=.. h=..  -> the NSPanel was actually resized

Clip metric: for every content change that is WIDER or TALLER than the
current window, the time until a window line catches up. While that gap is
open, the bubble is drawn wider than its window, i.e. visibly clipped.
One display frame at 60 Hz = 16.7 ms.

The scenarios create and end throwaway sessions (ids prefixed `st-`).

Usage: bubble_selftest.py [--agentpet PATH] [--rounds N] [--step-delay S]
"""
import argparse, os, re, subprocess, sys, time, statistics

LOG = os.path.expanduser("~/.agentpet/metrics.log")
FRAME_MS = 1000 / 60


def hook(binary, event, sid, **env):
    e = dict(os.environ)
    e.update({"JCODE_HOOK_EVENT": event, "JCODE_HOOK_SESSION_ID": sid,
              "JCODE_HOOK_CWD": env.pop("cwd", f"/tmp/{sid}")})
    for k, v in env.items():
        e["JCODE_HOOK_" + k.upper()] = v
    subprocess.run([binary, "hook", "--agent", "jcode"], env=e,
                   stdin=subprocess.DEVNULL, check=False)


def read_log(since):
    out = []
    try:
        for line in open(LOG):
            m = re.match(r"([\d.]+) (content|window) w=(\d+) h=(\d+)", line)
            if not m:
                continue
            t = float(m.group(1))
            if t >= since:
                out.append((t, m.group(2), int(m.group(3)), int(m.group(4))))
    except FileNotFoundError:
        pass
    return out


def uptime():
    # Anchor on AgentPet's own clock: the last timestamp it logged. Scenario
    # windows are then "everything logged after this point", no clock math.
    last = 0.0
    try:
        for line in open(LOG):
            m = re.match(r"([\d.]+) ", line)
            if m:
                last = float(m.group(1))
    except FileNotFoundError:
        pass
    return last + 1e-4


def clip_gaps(events):
    """Per content change larger than the window: ms until the window grows."""
    gaps = []
    win_w = win_h = None
    pending = None
    for t, kind, w, h in events:
        if kind == "window":
            if pending and w >= pending[1] and h >= pending[2]:
                gaps.append((t - pending[0]) * 1000)
                pending = None
            win_w, win_h = w, h
        else:  # content (reported size excludes the 4pt pad the window adds)
            if win_w is None:
                continue
            if w + 4 > win_w + 1 or h + 4 > win_h + 1:
                if pending is None:
                    pending = (t, w + 4, h + 4)
    return gaps


SCENARIOS = {
    # Width change: short -> long -> short activity lines on one session.
    "width": [
        ("session_start", "st-w", {}),
        ("post_tool", "st-w", {"tool_name": "bash"}),
        ("post_tool", "st-w", {"tool_name": "a_really_long_tool_name_for_width_test"}),
        ("post_tool", "st-w", {"tool_name": "read"}),
        ("post_tool", "st-w", {"tool_name": "another_extremely_long_tool_name_here_ok"}),
        ("session_end", "st-w", {}),
    ],
    # Height change: add/remove sessions (carousel dots row appears/disappears).
    "sessions": [
        ("turn_start", "st-s1", {}),
        ("turn_start", "st-s2", {}),
        ("turn_start", "st-s3", {}),
        ("session_end", "st-s3", {}),
        ("session_end", "st-s2", {}),
        ("session_end", "st-s1", {}),
    ],
    # Waiting conversation: question turn_end, then more activity elsewhere.
    "waiting": [
        ("turn_start", "st-q", {"cwd": "/tmp/st-question"}),
        ("turn_end", "st-q", {"status": "ok",
                              "last_assistant_text": "I found two options. Which one should I use?"}),
        ("turn_start", "st-q2", {}),
        ("post_tool", "st-q2", {"tool_name": "a_really_long_tool_name_for_width_test"}),
        ("session_end", "st-q2", {}),
        ("session_end", "st-q", {}),
    ],
}


def run(binary, rounds, step_delay):
    results = {}
    for name, steps in SCENARIOS.items():
        gaps_all = []
        for _ in range(rounds):
            t0 = uptime()
            for event, sid, env in steps:
                hook(binary, event, sid, **dict(env))
                time.sleep(step_delay)
            time.sleep(0.6)
            gaps_all += clip_gaps(read_log(t0))
        results[name] = gaps_all
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--agentpet", default="/Applications/AgentPet.app/Contents/MacOS/agentpet")
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--step-delay", type=float, default=0.7)
    a = ap.parse_args()
    if not os.path.exists(LOG):
        sys.exit("metrics.log missing: launch AgentPet with AGENTPET_METRICS=1")
    res = run(a.agentpet, a.rounds, a.step_delay)
    worst = 0.0
    for name, gaps in res.items():
        if gaps:
            frames = [g / FRAME_MS for g in gaps]
            worst = max(worst, max(gaps))
            print(f"{name:9s} grow-events={len(gaps):3d}  clip ms: median={statistics.median(gaps):5.1f} "
                  f"max={max(gaps):5.1f}  (~{statistics.median(frames):.1f} / {max(frames):.1f} frames)")
        else:
            print(f"{name:9s} grow-events=  0")
    print(f"WORST_CLIP_MS={worst:.1f}")


if __name__ == "__main__":
    main()
