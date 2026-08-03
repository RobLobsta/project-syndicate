#!/usr/bin/env python3
"""Shared runner for the fault sweeps in this directory.

A sweep plants one fault, runs the suite, restores the file, and reports whether
anything noticed. All three scripts here had their own copy of that loop; this is
the copy they share, and it carries the three things the hand-written version got
wrong.

**It cannot hang.** `subprocess.run` with no timeout is how a sweep stops
producing output and never returns: a planted fault can leave the runner awaiting
a coroutine that will never resume, and a `SceneTree` script that never reaches
`quit()` idles forever with its output buffered (handoff, engine fact 2). The run
is now started in its own session and killed by process group on a timeout, and a
timeout is reported as CAUGHT-HUNG — a fault that wedges the suite has certainly
been noticed, and the distinction is worth printing rather than hiding.

**It fails fast.** A sweep asks one question — did anything notice — and the
answer is known at the first failing file. `--fail-fast` stops there, which skips
the two ground files that are 57 s of the 78 s a full run costs whenever the
fault is caught before them.

Truncating is safe; **reordering is not**, and there is deliberately no way to do
it. Hoisting one physics file to the front leaves the check count identical and
moves `test_family_duels`' recoil measurement from 1.069 m/s to 0.916, which is
enough to fail an assertion that passes in discovery order. A sweep that reached
its expected file sooner would manufacture failures and report them as faults
being caught.

**It runs several faults at once**, each in its own throwaway copy of the project
under /tmp, sharing the engine binary from the original checkout. The copy is
4.7 MB and the suite is single-threaded and CPU-bound, so this is very close to
a linear speedup in cores. Each worker runs the identical full suite in the
identical order, so parallelism changes no measurement — unlike every other
accelerant that was tried.

Two rules that have not changed:

  * Do not `git add -A` while a sweep is running. It will commit a planted fault.
  * Do not kill one between the write and the restore. Check `git status` after.
    Parallel workers patch their own copies, so this now only applies to `-j1`.

Caught is a non-zero exit, a recorded failure, a timeout, *or* a check count that
differs from the baseline — the last of those is what catches a fault that
truncates the suite into a green partial pass, and it is only meaningful over a
complete run, so it is not applied to a run that stopped early.

**The baseline is measured, not declared.** Every sweep here carried a
hard-coded check count with a comment telling the next person to update it, and
two of the three were stale by hundreds of checks — at which point `checks !=
BASELINE` is true for every fault and the sweep reports CAUGHT for all of them,
including the ones nothing noticed. A number that has to be maintained by hand to
stay honest, in a file that is run once a session, does not stay honest. It is
now taken from a clean run, lazily: nothing pays for it unless some fault records
no failures at all, which is the only case it decides. A declared baseline is
still accepted and is checked against the measured one, so a stale constant now
prints a warning instead of quietly inverting the result.
"""
import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import threading
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))

## Seconds a single suite run is allowed before it is treated as hung. A clean
## run is about 78 s and the slowest fault seen is under two minutes, so this is
## roughly triple the honest worst case and will only fire on a wedge.
RUN_TIMEOUT_S = 420

## Directories whose contents the engine has to reimport before a run sees them.
## A fault planted anywhere else skips the ~14 s import step.
IMPORT_DIRS = ("data/", "assets/")

SUMMARY_RE = re.compile(
    r"run_all_checks: (\d+) checks, (\d+) failures across (\d+)/(\d+) files")
STOPPED_EARLY = "run_all_checks: STOPPED EARLY"


def _copy_project(destination):
    """A throwaway checkout for one worker, sharing the original's engine."""
    shutil.copytree(
        ROOT, destination,
        ignore=shutil.ignore_patterns(".git", ".tooling"),
        symlinks=True,
    )
    return destination


def _run_suite(cwd, extra_args):
    """One suite run, killed by process group if it wedges."""
    env = dict(os.environ)
    env["SYNDICATE_GODOT_DIR"] = os.path.join(ROOT, ".tooling", "godot")
    started = time.monotonic()
    proc = subprocess.Popen(
        ["tools/ci/run_all_checks.sh"] + extra_args,
        cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, start_new_session=True,
    )
    try:
        out, _ = proc.communicate(timeout=RUN_TIMEOUT_S)
        return proc.returncode, out, time.monotonic() - started, False
    except subprocess.TimeoutExpired:
        # The whole group: run_all_checks.sh pipes the engine through tee, so
        # killing the shell alone leaves the engine running and holding a core.
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = proc.communicate()
        return proc.returncode, out or "", time.monotonic() - started, True


class _Baseline:
    """The clean-run check count, measured at most once and only if needed."""

    def __init__(self, declared):
        self._declared = declared
        self._value = None
        self._lock = threading.Lock()

    def value(self, cwd):
        with self._lock:
            if self._value is not None:
                return self._value
            print("sweep: measuring the clean-run check count "
                  "(some fault recorded no failures)", flush=True)
            _rc, out, _s, hung = _run_suite(cwd, ["--no-import"])
            m = None if hung else SUMMARY_RE.search(out)
            if m is None:
                print("sweep: WARNING could not measure a baseline; "
                      "check-count comparison disabled", flush=True)
                self._value = -1
            else:
                self._value = int(m.group(1))
                if self._declared is not None and self._declared != self._value:
                    print(f"sweep: WARNING declared baseline {self._declared} but a clean "
                          f"run has {self._value}; using the measured value", flush=True)
            return self._value


def _judge(name, rel_path, old, new, cwd, baseline, full):
    path = os.path.join(cwd, rel_path)
    src = open(path).read()
    if old not in src:
        # Not a failure of the code: a fault that no longer applies is a defence
        # that has been removed without anybody deciding to remove it. It is
        # reported loudly for that reason -- see the note in the handoff about
        # a sweep script rotting in the direction of testing less.
        return f"{name}: PATCH-MISS (the code it defends has changed)", None

    args = []
    if not full:
        args.append("--fail-fast")
    if not rel_path.startswith(IMPORT_DIRS):
        args.append("--no-import")

    open(path, "w").write(src.replace(old, new, 1))
    try:
        rc, out, seconds, hung = _run_suite(cwd, args)
    finally:
        open(path, "w").write(src)

    if hung:
        return (f"{name}: CAUGHT-HUNG rc={rc} after {seconds:.0f}s "
                f"(no summary; the suite never finished)"), out

    m = SUMMARY_RE.search(out)
    if m is None:
        return f"{name}: NO-SUMMARY rc={rc} in {seconds:.0f}s (crash or parse error)", out

    checks, failures, _bad, _files = m.groups()
    stopped_early = STOPPED_EARLY in out
    # The check-count comparison is only meaningful over a complete run. A
    # fail-fast run that stopped early is short by construction, and reading that
    # as a truncation fault would call every caught fault caught twice over.
    #
    # It is also only consulted when nothing else caught the fault, which is what
    # keeps the baseline measurement lazy.
    count_moved = False
    if not stopped_early and rc == 0 and int(failures) == 0:
        measured = baseline.value(cwd)
        count_moved = measured >= 0 and int(checks) != measured
    caught = rc != 0 or int(failures) > 0 or count_moved
    verdict = "CAUGHT" if caught else "SURVIVED"
    note = " check-count moved" if count_moved and int(failures) == 0 else ""
    return (f"{name}: {verdict} rc={rc} checks={checks} failures={failures} "
            f"in {seconds:.0f}s{note}"), out


def run_sweep(faults, baseline=None, description=""):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("only", nargs="*", help="fault names; default is all")
    parser.add_argument("-j", "--jobs", type=int, default=0,
                        help="parallel workers; 0 picks one per core, capped at 4")
    parser.add_argument("--full", action="store_true",
                        help="run every file rather than stopping at the first failure")
    parser.add_argument("--list", action="store_true", help="print the fault names and exit")
    args = parser.parse_args()

    if args.list:
        for name, *_ in faults:
            print(name)
        return 0

    selected = [f for f in faults if not args.only or f[0] in args.only]
    if not selected:
        print("no matching faults", file=sys.stderr)
        return 2

    unknown = set(args.only) - {f[0] for f in faults}
    if unknown:
        print(f"unknown fault names: {', '.join(sorted(unknown))}", file=sys.stderr)
        return 2

    jobs = args.jobs or min(4, os.cpu_count() or 1)
    jobs = max(1, min(jobs, len(selected)))

    print(f"sweep: {len(selected)} faults, {jobs} worker(s), "
          f"{'full' if args.full else 'fail-fast'}", flush=True)
    baseline = _Baseline(baseline)

    workspaces = []
    tmp = None
    try:
        if jobs == 1:
            # In-place, so a single named fault behaves exactly as it always has
            # and `git status` still shows a planted fault if this is killed.
            workspaces = [ROOT]
        else:
            tmp = tempfile.mkdtemp(prefix="syndicate-sweep-")
            for i in range(jobs):
                workspaces.append(_copy_project(os.path.join(tmp, f"w{i}")))

        results = [None] * len(selected)
        logs = [None] * len(selected)
        lanes = [[] for _ in range(jobs)]
        for i, fault in enumerate(selected):
            lanes[i % jobs].append(i)

        def work(lane_index):
            for i in lanes[lane_index]:
                name, rel_path, old, new = selected[i]
                line, out = _judge(name, rel_path, old, new,
                                   workspaces[lane_index], baseline, args.full)
                results[i] = line
                logs[i] = out
                print(line, flush=True)

        with ThreadPoolExecutor(max_workers=jobs) as pool:
            list(pool.map(work, range(jobs)))
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)

    # Reported a second time in declaration order. The live lines above arrive in
    # whatever order the workers finish, which is not the order anybody wrote the
    # faults in or will read them in.
    print("\n== sweep summary ==", flush=True)
    survived = 0
    for i, line in enumerate(results):
        print(line or f"{selected[i][0]}: NOT RUN")
        if line and " SURVIVED " in line:
            survived += 1
        if line and (" CAUGHT " in line or "CAUGHT-HUNG" in line):
            out = logs[i] or ""
            for entry in out.splitlines():
                if "FAIL" in entry or entry.strip().startswith("test_"):
                    print("    " + entry.strip())
    print(f"\n{len(selected)} faults, {survived} survived", flush=True)
    return 0
