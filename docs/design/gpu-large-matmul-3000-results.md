# Jac GPU 3000³ MatMul：完整运行与布局对照

2026-10-07，源码基础 `145f9899fce2e3d08c207721beac0f0aac88a706`。
上一轮已提交报告保持不变。本轮只新增实验 runner、测试、文档和机器摘要，未提交或推送。

**实际完成了 3000×3000×3000 的完整结果。** Current、完整 cursor BFS
Predicted、Random seeds 928/929/930 五个实例均执行全部 **9,000,000 输出**、
**27,000,000,000 multiply-accumulates**，逐输出验证成功，所有 status 为零。
不是用小尺寸外推，也不是用 dense 地址数组代替 Jac Graph。

**硬件 counter 证据仍缺失。** 本轮 ncu 实际 kernel 采集报
`ERR_NVGPUCTRPERM`，工具 exit 1。没有索取密码或更改权限/驱动；因此不对
coalescing、sector/request、cache、DRAM、occupancy 或 GPU 瓶颈原因作归因。

## 真实图、有界执行与资源

使用原 `named_cursors.jac` 的 Scalar、RowNext、ColumnNext 和 Dot 能力。
真实共享输入图一次构建：18,000,000 Scalar 节点、17,994,000 边。
节点仅存一个 int。没有按乘积复制输入。每种布局的 readonly SoA/CSR
约 719,952,016 bytes（0.671 GiB），上传一次后供所有输出批次复用。

每批至多 32768 个独立 GPU walker lane，275 次 launch 覆盖全部输出，最后
一批 21632 lanes。私有状态约 2.13 MiB/满批，不同时创建 900 万 CPU walker
对象。每个结果在 bounded batch 内成为真实的单 int Scalar 输出节点，保存
为 int64 binary 后释放；**没有同时保留完整的 900 万 CPU 输出节点图**。

Queue capacity=1：一个初始 seed；每轮先消费，再至多追加一个后继，因此
pending≤1。实际 CSR 检查每关系 outdegree≤1，构建出的链长度 K=3000，
max_visits=3001。该证明只用于本 fixture，不改变一般 CSR 分支队列的规则。

权重 A[i,k]=i+1、B[k,j]=j+1。每个输出独立 CPU oracle 为
K*(i+1)*(j+1)，使用 int64；所有完整输出逐项核对。每实例结果文件为
72,000,000 bytes，共同 SHA256：
`4e4078629f40c5b0bf4fcea300c74af4fcdacad32b440945343a1716986840de`。

先做可逆小样：96k 输入节点真实图 1.01s；768k 输入节点真实图 4.64s，
小样峰值 RSS 1.33 GiB。完整图构建实测 **140.80s、结束 RSS 17.32 GiB**；
全运行记录峰值 RSS **27.78 GiB**。主机 78 GiB RAM、初始可用 72 GiB，
cgroup memory.max=max，swap 2 GiB。保护为 RSS≤48 GiB、可用 RAM≥20 GiB；
未触发保护。未更改生产 packer 的默认 OOM 上限。

## 实际排列审计

Predicted 显式 prediction_budget=9,000,000。两 cursor 各 expanded/discovered
9,000,000，truncated=false。压缩的 5999 个规划绑定，按第一行全列再补
其余各行首列，首次 seed 顺序等于全量 row-major lanes；只压缩布局发现，
实际输出和到达事件不压缩。回归对 4×4×4、3×5×2、单行/单列边界比较
真实 node identity 顺序和全部 readonly 数组，并用实际 CPU Jac spawn
差分 LLVM JIT 的所有分批输出。

独立 audit 从 Current 的实际 CSR 和 heads 重建两通道完整 multi-source
BFS。Predicted identity 数组逐元素等于 **完整 A 序列 + 完整 B 序列**，
共 18m identities；这里 A/B 集合不相交。

- Current 与 Predicted **identity order 不同**。
- value、CSR offsets、targets 的 hashes 不同；tags hash 相同（全为 Scalar）。
- 独立拼接和 Predicted 共同 identity SHA256：
  `6f0291591238c28e0671cca567bfd39db70f89795ea07760325d91bbee7c72fa`。
- 全部原始 order、A/B candidate order 与字段数组留存 binary，不写 per-node JSON。
- Random 对统一物理索引 permutation，同步重映射所有字段、CSR 行/targets、
  heads/queue；行内邻居顺序和 walker/lane 顺序保留。三 seed 均完整验证。

[机器审计](../../scripts/gpu_walker/large_matmul/validation/identity-audit.json)
包含完整 hashes；[原始审计](/tmp/jac-large-matmul-3000-20261007/identity-audit.json)。

## 正式性能采样：完整图上的 subset

此处 timing 与上述 full-result 验证分开。复用 exact checksummed packed
binaries；相同 int64、PTX、32768 lanes、128 threads/block（256 blocks）、
输入和绑定。每 seed 4 warmup、16 measured paired rounds，布局顺序按固定
seed 打乱。每对取相同输出起点：第一 launch 上传绑定，第二 launch resident
重放；每次结果仍核对 CPU oracle。**每 layout 48 个 measured resident
samples，每次仅 32768 输出，不能把这些 samples 当完整 900 万输出计时。**

普通 event 与 nsys 重放为两个独立进程，均正常 exit 0。开始前旧试验进程和
GPU context 已退出；无其他 GPU compute process。自己的回归、构图和分析
均未并行。另有其他用户的零 CPU resource_tracker，不予干预。

| 方法（每 layout n=48） | Current min / median / max ms | Predicted min / median / max ms | Random min / median / max ms |
| --- | --- | --- | --- |
| 普通 CUDA event | 8.826 / 8.907 / 8.996 | 8.835 / 8.879 / 8.952 | 70.179 / 70.319 / 70.429 |
| nsys 纯 kernel duration | 8.795 / 8.851 / 8.959 | 8.917 / 8.973 / 9.041 | 70.665 / 70.802 / 70.961 |

CUDA event 区间可能包含 CPU enqueue 间隙；nsys 纯 kernel duration 才用于
该 kernel 时间事实。分析严格核对全部 360 个 trace kernels 与记录顺序、
kernel name、grid/block 后关联。

| seed | event Pred/Current 配对比值 median | nsys Pred/Current 配对比值 median | nsys Random/Pred 配对比值 median |
| --- | --- | --- | --- |
| 928 | 0.99636 | 1.01123 | 7.85345 |
| 929 | 0.99683 | 1.01367 | 7.89796 |
| 930 | 0.99879 | 1.01400 | 7.90814 |

所有配对原始 samples、每 seed min/median/max 和聚合分布均留档，未挑最优
seed。**Current/Pred 的小差异在两个采样方法间方向反转，未观察到稳定的
Predicted 收益。** Random 的 kernel 明显更慢，这一事实得到 nsys 支持；
它的硬件原因尚未建立，不能宣称由 coalescing/cache 引起。BFS 不是最优
布局结论。对这个 fixture，仅为 resident kernel 改成 Predicted 没有实测
稳定收益；最小后续工作是获得 counter 后对同一 batch/profile 对照，而非
先继续复杂重排。其他数据/规模不能由本例推断。

nsys 实测整个受控重放 H2D：1116 copies、6,880,648,464 bytes、纯 copy
合计 0.62955s；D2H：360 copies、70,778,880 bytes、0.005756s。
cuLaunchKernel 360 次 API 合计 0.004095s；cuEventSynchronize 合计10.64926s。
这些是 trace 范围合计，包含 warmup、九次 graph upload 和 private binding，
不是单 kernel 的 DRAM 流量/带宽 counter，也不能把 API sync 当额外 kernel
时间相加。每次上传、private H2D、D2H 和 launch 对的 wall 均在 raw records。

## 完整运行成本和过程退出限制

| 实例 | pack/重排 wall s | readonly graph H2D wall s | 全输出 execution wall s |
| --- | --- | --- | --- |
| Current | 328.52 pack | 0.06464 | 10.72 |
| Predicted | 266.74 pack（其中 prediction 6.90s） | 0.06614 | 10.76 |
| Random 928 | 78.71 重排，另复用 Current pack | 0.06482 | 27.78 |
| Random 929 | 77.10 重排，另复用 Current pack | 0.06412 | 27.80 |
| Random 930 | 79.81 重排，另复用 Current pack | 0.06472 | 31.08 |

Full execution wall 包含 batch 准备、绑定 H2D、kernel、D2H、oracle、Scalar
输出节点 materialization/校验和 binary 保存。原始记录另列各项。上述 pack
包括边界检查与 identity artifact；production pack 内部分阶段另存 timings。
**pack 期间曾并行运行 CPU/JIT 测试，因此这些是本次资源事实，不能比较成
独占 CPU 性能基准**。没有为更漂亮的 CPU 数字重建 18m 图。

**完整运行进程最终 exit 143（SIGTERM），不是正常 exit 0，也不是工具超时。**
五实例完整计算、零 status 校验、完整 binary 和 report.complete=true 已落盘
之后，进程在 Python 解释器退出清理中继续使用 CPU。perf 6.8.12 以
cpu-clock:u、99Hz、DWARF sampling 采集5s、495 samples、lost=0；该窗口
95.35% self samples 位于 gc_collect_main，调用链 Py_FinalizeEx。
这只证明采样窗口的热点，不能归因整次运行的所有未计时开销。

确认无本进程 CUDA context 后，仅 SIGTERM 此已完成计算的进程，避免干扰
正式 sampling。退出 clock bracket 为1795.43–1795.68s（epoch 转换约1s精度），
包括构图、五实例、artifacts 和被终止的清理；**不是自然退出的端到端成本**。
不提供未经实测的正常 full end-to-end 加速比；resident kernel 时间也不能
抵销一次性真实 CPU 构图/pack 成本。

[退出日志](../../scripts/gpu_walker/large_matmul/validation/full-run-exit.log)、
[终止记录](../../scripts/gpu_walker/large_matmul/validation/termination.json)、
[CPU profiler报告](../../scripts/gpu_walker/large_matmul/validation/cleanup-perf-report.txt)。

## 复现、证据与检查

GPU：RTX3090，24576MiB，driver580.65.06，CUDA driver API13000；
Python3.12.11，LLVM20.1.8 shim，nsys2025.3.2.367，ncu2025.3.0.0。
本机不是通过旧报告假定：本轮已重新检查设备、工具和无外部进程。
PTX SHA256：`1dcb05c5f3cc1dfc7aa4a6ec3d79e4bc096f9b0842977b50183694db3131fdca`。

- [工具/语义](../../scripts/gpu_walker/large_matmul/README.md)；
  [精确命令/环境](../../scripts/gpu_walker/large_matmul/validation/commands.txt)。
- [全结果机器摘要](../../scripts/gpu_walker/large_matmul/validation/full-run.json)。
- [普通 samples](../../scripts/gpu_walker/large_matmul/validation/ordinary.json)、
  [nsys关联结果](../../scripts/gpu_walker/large_matmul/validation/profile.json)。
- [ncu失败日志](../../scripts/gpu_walker/large_matmul/validation/ncu-predicted.log)。
- [本机 raw目录](/tmp/jac-large-matmul-3000-20261007)，约4.6GiB，包括所有完整
  packed arrays/heads、identity arrays、五个完整 output binaries、PTX、source
  snapshots、raw JSON/CSV。未将这些大二进制放进仓库。
- [raw nsys trace](/tmp/jac-large-matmul-3000-20261007/nsys-trace.nsys-rep)、
  [SQLite](/tmp/jac-large-matmul-3000-20261007/nsys-trace.sqlite)、
  [raw CPU perf](/tmp/jac-large-matmul-3000-20261007/cleanup.perf.data)。
- 本轮15项既有 named CPU/JIT tests通过；1项新 bounded 差分回归包含四形状
  及 Current/Predicted，两者真实 node identity/CSR 与完整 lane pack 相同。
  实际 CUDA 小样、重复 resident replay 和五实例完整3000³均正确。
- Named-only schema；旧 Chain LLVM 路径本轮未复测，未更改全局 LLVM 环境。

GPU独占时段已明确释放，最终确认 compute-process 列表为空。保护了其他
agent 文件、untracked 工作和 stash；无 branch switch、commit 或 push。
