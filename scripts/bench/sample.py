#!/usr/bin/env python3
"""Samples CPU time and memory of every process of an app until killed, for report.py and chart.py.
Usage: sample.py <path part, e.g. "/Mattermost.app/"> <out.jsonl> [interval s, default 0.25]
Each line: {"t": unix time, "cpu": CPU seconds used so far by all its processes (user + system, counted per process,
so helpers that come and go are included), "mb": summed physical footprint (Activity Monitor's Memory), "n": processes,
"th": threads}. Reads the kernel's per-process accounting (proc_pid_rusage, proc_pidinfo), the numbers Activity Monitor
shows. snapshot() gives the same numbers once, for the drivers."""
import ctypes, json, signal, sys, time

lib = ctypes.CDLL("/usr/lib/libproc.dylib")
libc = ctypes.CDLL("/usr/lib/libSystem.dylib")


class RUsage(ctypes.Structure):  # rusage_info_v2
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size", "resident_size",
        "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time", "child_system_time",
        "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins", "child_elapsed_abstime",
        "diskio_bytesread", "diskio_byteswritten")]


class TaskInfo(ctypes.Structure):  # proc_taskinfo, PROC_PIDTASKINFO
    _fields_ = [(n, ctypes.c_uint64) for n in ("virtual_size", "resident_size", "total_user", "total_system",
                                                 "threads_user", "threads_system")] + \
               [(n, ctypes.c_int32) for n in ("policy", "faults", "pageins", "cow_faults", "messages_sent",
                                               "messages_received", "syscalls_mach", "syscalls_unix", "csw",
                                               "threadnum", "numrunning", "priority")]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


tb = Timebase(); libc.mach_timebase_info(ctypes.byref(tb))
TICK = tb.numer / tb.denom / 1e9  # rusage times are in mach absolute time units
PROC_PIDTASKINFO = 4


def processes(part):
    buf = (ctypes.c_int * 8192)()
    n = lib.proc_listallpids(buf, ctypes.sizeof(buf))
    path = ctypes.create_string_buffer(4096)
    for pid in buf[:max(0, n)]:
        if pid > 0 and lib.proc_pidpath(pid, path, 4096) > 0 and part in path.value.decode(errors="replace"):
            yield pid


def measure(pid):
    """(CPU seconds, physical footprint MB, threads) of one process, or None if it is gone."""
    r = RUsage()
    if lib.proc_pid_rusage(pid, 2, ctypes.byref(r)) != 0: return None
    ti = TaskInfo()
    threads = ti.threadnum if lib.proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ctypes.byref(ti), ctypes.sizeof(ti)) > 0 else 0
    return (r.user_time + r.system_time) * TICK, r.phys_footprint / 1048576, threads


def snapshot(part):
    """Summed footprint MB, process count and thread count of the app right now."""
    mb, n, th = 0.0, 0, 0
    for pid in processes(part):
        m = measure(pid)
        if m is None: continue
        mb += m[1]; th += m[2]; n += 1
    return {"mb": round(mb), "processes": n, "threads": th}


def main():
    part, out = sys.argv[1], sys.argv[2]
    interval = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    seen = {}  # pid -> CPU seconds at the last sample
    total = 0.0
    with open(out, "w") as f:
        while True:
            mb, n, th = 0.0, 0, 0
            for pid in processes(part):
                m = measure(pid)
                if m is None: continue
                total += m[0] - seen.get(pid, 0.0)
                seen[pid] = m[0]
                mb += m[1]; th += m[2]; n += 1
            f.write(json.dumps({"t": round(time.time(), 3), "cpu": round(total, 3), "mb": round(mb), "n": n, "th": th}) + "\n")
            f.flush()
            time.sleep(interval)


if __name__ == "__main__":
    main()
