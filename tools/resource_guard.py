"""Run a disposable QA subprocess with fail-closed resource monitoring on macOS."""
import ctypes
import os
import resource
import shutil
import signal
import subprocess
import time


class Usage(ctypes.Structure):
    # SDK sys/resource.h, rusage_info_v0. phys_footprint includes compressed memory.
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user_time", "system_time", "pkg_idle", "interrupts", "pageins",
            "wired", "resident", "footprint", "start", "exit")
    ]


def footprint(pid):
    lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    usage = Usage()
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    lib.proc_pid_rusage.restype = ctypes.c_int
    if lib.proc_pid_rusage(pid, 0, ctypes.byref(usage)) != 0:
        raise RuntimeError("Cannot measure child memory; refusing unmonitored QA")
    return usage.footprint


def violation(memory, free, elapsed, limit, minimum, timeout):
    if memory >= limit:
        return "Child memory limit reached"
    if free < minimum:
        return "Startup disk reserve reached"
    if elapsed >= timeout:
        return "QA wall-clock limit reached"
    return None


def run(command, *, cwd, output, limit=256 * 1024**2,
        minimum=10 * 1024**3, timeout=120):
    if shutil.disk_usage("/").free < minimum:
        raise RuntimeError("Insufficient startup disk reserve; QA not started")

    def child_limits():
        os.nice(10)
        resource.setrlimit(resource.RLIMIT_CPU, (90, 90))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    peak = 0
    started = time.monotonic()
    with open(output, "w") as log:
        process = subprocess.Popen(command, cwd=cwd, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True,
                                   preexec_fn=child_limits)
        try:
            while process.poll() is None:
                try:
                    memory = footprint(process.pid)
                except RuntimeError:
                    if process.poll() is not None:
                        break
                    raise
                peak = max(peak, memory)
                reason = violation(memory, shutil.disk_usage("/").free,
                                   time.monotonic() - started, limit, minimum, timeout)
                if reason:
                    raise RuntimeError(reason)
                time.sleep(0.05)
            if process.wait() != 0:
                raise RuntimeError("QA child failed; inspect its external log")
        finally:
            # This new session contains only this QA child and its descendants.
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
    return {"peak_footprint_bytes": peak, "memory_limit_bytes": limit,
            "startup_reserve_bytes": minimum,
            "seconds": round(time.monotonic() - started, 3)}
