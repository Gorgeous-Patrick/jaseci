from dataclasses import dataclass
from typing import Optional
import re

# --- Dataclasses for the structured result ---

@dataclass
class ThreadScheduler:
    breakdown_dma: int = 0
    breakdown_etc: int = 0
    breakdown_run: int = 0

@dataclass
class Logic:
    active_tasklets_0: int = 0
    active_tasklets_1: int = 0
    logic_cycle: int = 0
    num_instructions: int = 0

@dataclass
class CycleRule:
    cycle_rule: int = 0

@dataclass
class MemoryController:
    memory_cycle: int = 0

@dataclass
class MemoryScheduler:
    num_fcfs: int = 0

@dataclass
class RowBuffer:
    num_reads: int = 0
    read_bytes: int = 0
    num_activations: int = 0
    num_precharges: int = 0
    num_writes: int = 0
    write_bytes: int = 0

@dataclass
class SimStats:
    thread_scheduler: ThreadScheduler
    logic: Logic
    cycle_rule: CycleRule
    memory_controller: MemoryController
    memory_scheduler: MemoryScheduler
    row_buffer: RowBuffer


# --- Parser ---

_LINE_RE = re.compile(
    r'^(?P<section>[A-Za-z]+)\[[^\]]*\]_(?P<metric>[A-Za-z0-9_]+):\s*(?P<value>-?\d+)\s*$'
)

def parse_sim_stats(text: str) -> SimStats:
    """
    Parse lines like 'ThreadScheduler[0_0_0]_breakdown_dma: 362' into a SimStats dataclass.
    The bracketed token (e.g., [0_0_0]) is ignored.
    Unknown sections/metrics are ignored safely.
    """
    # temp holders
    ts = ThreadScheduler()
    lg = Logic()
    cr = CycleRule()
    mc = MemoryController()
    ms = MemoryScheduler()
    rb = RowBuffer()

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        m = _LINE_RE.match(line)
        if not m:
            continue  # skip anything that doesn't match the pattern

        section = m.group("section")
        metric = m.group("metric")
        value = int(m.group("value"))

        if section == "ThreadScheduler":
            if metric == "breakdown_dma": ts.breakdown_dma = value
            elif metric == "breakdown_etc": ts.breakdown_etc = value
            elif metric == "breakdown_run": ts.breakdown_run = value

        elif section == "Logic":
            if metric == "active_tasklets_0": lg.active_tasklets_0 = value
            elif metric == "active_tasklets_1": lg.active_tasklets_1 = value
            elif metric == "logic_cycle": lg.logic_cycle = value
            elif metric == "num_instructions": lg.num_instructions = value

        elif section == "CycleRule":
            if metric == "cycle_rule": cr.cycle_rule = value

        elif section == "MemoryController":
            if metric == "memory_cycle": mc.memory_cycle = value

        elif section == "MemoryScheduler":
            if metric == "num_fcfs": ms.num_fcfs = value

        elif section == "RowBuffer":
            if metric == "num_reads": rb.num_reads = value
            elif metric == "read_bytes": rb.read_bytes = value
            elif metric == "num_activations": rb.num_activations = value
            elif metric == "num_precharges": rb.num_precharges = value
            elif metric == "num_writes": rb.num_writes = value
            elif metric == "write_bytes": rb.write_bytes = value

        # else: silently ignore unknown sections

    return SimStats(
        thread_scheduler=ts,
        logic=lg,
        cycle_rule=cr,
        memory_controller=mc,
        memory_scheduler=ms,
        row_buffer=rb,
    )


# --- Example ---
if __name__ == "__main__":
    example = """\
ThreadScheduler[0_0_0]_breakdown_dma: 362
ThreadScheduler[0_0_0]_breakdown_etc: 2344
ThreadScheduler[0_0_0]_breakdown_run: 233
Logic[0_0_0]_active_tasklets_1: 2298
Logic[0_0_0]_logic_cycle: 2939
Logic[0_0_0]_num_instructions: 233
Logic[0_0_0]_active_tasklets_0: 641
CycleRule[0_0_0]_cycle_rule: 65
MemoryController[0_0_0]_memory_cycle: 17634
MemoryScheduler[0_0_0]_num_fcfs: 23
RowBuffer[0_0_0]_num_reads: 13
RowBuffer[0_0_0]_read_bytes: 104
RowBuffer[0_0_0]_num_activations: 3
RowBuffer[0_0_0]_num_precharges: 2
RowBuffer[0_0_0]_num_writes: 13
RowBuffer[0_0_0]_write_bytes: 104
"""
    stats = parse_sim_stats(example)
    print(stats)