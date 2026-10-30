#!/usr/bin/env python3
"""Collect one checked-O2 counter probe; retain access errors and full validation."""
import argparse
from pathlib import Path
import subprocess
import sys
import shutil
from prepare import HERE, read, write, sha


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('validation',type=Path)
    p.add_argument('--ncu',default='/opt/nvidia/nsight-compute/2025.3.0/ncu')
    p.add_argument('--nvcc',default='/usr/local/cuda-12.9/bin/nvcc')
    p.add_argument('--status-evidence',type=Path)
    args=p.parse_args();v=args.validation
    folder=v/'counters';folder.mkdir(exist_ok=True)
    metric='l1tex__t_sectors_pipe_lsu_mem_global_op_ld.sum'
    # A short flag also selects Python mode when sys.executable is bundled jac.
    command=[args.ncu,'--target-processes','all','--kernel-name','regex:jac_Dot_cursors_batch','--launch-count','1','--metrics',metric,'--force-overwrite','--export',str(folder/'o2-random928'),sys.executable,'-B',str(HERE/'run.py'),'--inputs',str(v/'inputs/inputs.json'),'--jac-ptx',str(v/'optimized-codegen/O2.ptx'),'--output',str(folder/'o2-probe'),'--case-id','matmul-256x256x256','--only-arm','before','--warmup','0','--repeats','1','--inner','1','--nvcc',args.nvcc]
    if args.status_evidence:command+=['--status-evidence',str(args.status_evidence)]
    if shutil.which(args.ncu) is None:
        (folder/'o2-ncu.log').write_text(f'Nsight Compute executable unavailable: {args.ncu}\n')
        write(folder/'o2-status.json',{'status':'unavailable','error':'tool_not_found','command':command,
            'log':'o2-ncu.log','log_sha256':sha(folder/'o2-ncu.log'),'requested_metric':metric})
        return
    with (folder/'o2-ncu.log').open('w') as f:
        result=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT)
    text=(folder/'o2-ncu.log').read_text()
    denied='ERR_NVGPUCTRPERM' in text
    write(folder/'o2-status.json',{'status':'unavailable' if denied else 'collected' if result.returncode==0 else 'failed','error':'ERR_NVGPUCTRPERM' if denied else None,
        'exit_code':result.returncode,'log':'o2-ncu.log','log_sha256':sha(folder/'o2-ncu.log'),'requested_metric':metric,'command':command,
        'probe_case':'matmul-256x256x256','probe_arm':'Jac before (Random928 + checked LLVM O2)','timing_usage':'separate counter probe; primary timings from optimized-profile'})
    assert result.returncode==0 or denied
    if result.returncode==0:assert read(folder/'o2-probe/results.json')['complete']


if __name__=='__main__':main()
