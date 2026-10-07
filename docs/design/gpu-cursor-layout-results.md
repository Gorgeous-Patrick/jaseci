# Jac GPU 多 cursor：布局实验与证据边界

已实现 GPU 联合 cursor 执行和按整个 batch、多源、各通道分别展开的 BFS
预测 packer。实验使用真实 RTX 3090；GPU 测量期间 Transformer 停止 GPU 工作，
测量和最终 CUDA 回归完成后已释放独占时段。未提交、推送或修改系统配置。

**GPU 因果证据存在硬性缺口：ncu 2025.2.1 返回 `ERR_NVGPUCTRPERM`；仅提升本次
进程的 `sudo -n` 尝试返回需要密码。没有 cache、coalescing、实际访存 transactions、
bandwidth 或 occupancy counter，不能解释这些机制导致的速度差异。** 两份失败日志
均保留。不等待管理员，不把地址连续度或输入大小当硬件证据。

## 实现与正确性

[语法、语义与 GPU 子集](gpu-named-cursors.md)描述任意编译期固定数量的 cursor、
各通道稳定当前位置和私有 FIFO、联合 arrival/entry 匹配、重复事件和结束条件。
旧单通道 chain/CSR 路径保留。动态标量循环、分支、算术和 report 复用现有 lowering。
GPU 首批支持同触发节点类型的单个联合 ability、每通道至多一次无条件或简单条件 visit；
更一般触发/visit 组合明确拒绝。CSR 支持有界分支和环；链模式验证单后继、无环。

物理节点按身份共享一次，字段 SoA；heads、CSR 行与 targets 全部重映射。
预测只影响物理布局，绝不合并真实到达事件。条件 visit 使用保守关系展开，预算
或发现集保证预测终止；执行仍按实际条件和 FIFO 进行。
[可运行示例](../../jac/examples/gpu/named_cursors.jac)包含同类型双 cursor 点积、
三 cursor、条件 visit、循环及共享 A 行/B 列输入的整数 matmul。每个输入/输出
Scalar 只保存一个 int；GPU 写 walker.total，host 发布输出节点，未扩展设备写节点能力。

最终当前工作区 12 项 named-cursor 测试在真实 CUDA 下通过，同时覆盖 CPU reference、
LLVM host JIT 和 mock ABI。包含三/七 cursor、共享节点、空/不等长队列、类型不匹配、
CSR 分支/重复到达、条件 visit、无 visit、循环和 report；这些证据与 mock/JIT 明确分开。
此前旧 GPU host 回归 92 项中 90 通过、2 项 device-only 跳过，后续补跑这两项 CUDA 通过；
13 项旧整数/循环 CUDA 测试及 11 项仓库 PTX/CPU 测试通过。
新增物理 permutation/汇总边界测试 2 项通过。

## 方法与原始产物

GPU：NVIDIA GeForce RTX 3090，驱动 595.71.05；nsys 2025.1.3.140，ncu 2025.2.1.0。
测量时源版本 `2c130ccbe08aed1725de9693668aaf3d4386977e`，工作区未提交。
关键编译/运行时/测量源码逐文件 SHA256 和匹配的源码快照已保留，避免其他 agent
提交导致 HEAD 不足以描述本次源码。Python 版本、PTX hash、dtype、launch 参数、
GPU 前后 telemetry 见 inputs.json。未锁定 GPU 时钟。

[主输入与环境](../../dist/gpu-layout-exclusive-20261006/inputs.json)、
[普通 CSV](../../dist/gpu-layout-exclusive-20261006/wall-events.csv)、
[nsys 原始报告](../../dist/gpu-layout-exclusive-20261006/trace.nsys-rep)、
[nsys SQLite](../../dist/gpu-layout-exclusive-20261006/trace.sqlite)、
[已对齐 kernel CSV](../../dist/gpu-layout-exclusive-20261006/profile-launches.csv)、
[counter 失败](../../dist/gpu-layout-exclusive-20261006/ncu-matmul-predicted.log)、
[提权失败](../../dist/gpu-layout-exclusive-20261006/ncu-matmul-predicted-privileged.log)。
完整副本位于 `dist/gpu-layout-exclusive-20261006/`，包含 typed 输入二进制、
CSV/JSON、源码快照、raw profiler、CPU .prof 和 SHA256 清单。
[仓库可读机器报告](../../scripts/gpu_walker/validation/named_layouts_3090_profiled.json)
保留每 seed 配对统计、完整分布、排列审计和环境。

[runner](../../scripts/gpu_walker/compare_named_layouts.py)复用旧
compare_layouts.py 的固定 seed、paired sampling 和严格 profiler replay 方法。
旧单通道原脚本已直接跑通并另存 `/tmp/jac-legacy-layout-profile/`。
本次统一 runner 使用 seed 928/929/930、block=128、每 seed 6 次预热和 16 次重复，
每 pair 随机化布局次序。Random 对 Current 已统一去重的物理索引 permutation，
同步重映射每个字段、通道 heads、CSR 行及 targets，保留行内顺序与 lane 分派。
每次 launch 全 lane 对 CPU 算术 oracle 和另一个布局校验；选取的 Jac CPU walker
lane 也差分运行。输入权重、dtype 和 launch 配置完全相同。

```sh
python scripts/gpu_walker/compare_named_layouts.py \
  --chain-cases 128x8 1024x64 --dot-cases 128x8 1024x32 \
  --matmul-cases 16x32x24 32x64x48 64x128x64 \
  --seeds 928 929 930 --warmup 6 --repeats 16 --profile \
  --output /tmp/jac-layout-exclusive
```

需要仓库 .venv、`PYTHONPATH=jac` 和 README 中的 LLVM shim 环境配置。
显式 CPU/device 规模上限防止 OOM；输入节点分别为 `(M+N)*K`，不为每个乘积复制输入。
普通计时与 nsys 重放分别运行。nsys 逐一核对了 2,541 次 kernel 的名称、几何及顺序，
全部对应到 cuLaunchKernel correlation。CUDA event 区间可能含主机 enqueue 间隙；
下表是另一轮 nsys/CUPTI 的纯 kernel 时间，不混为普通计时。

## Current 与 Predicted 是否真的不同

所有实测输入数组已逐个比对 hash。另在 CPU 重建图并重复 pack，只有当每个布局的
所有重建数组 dtype/count/SHA256 与实测完全相同才接受审计。
identity label 使用重建图的 conservative-discovery 索引，非跨进程对象地址。
[审计结果](../../dist/gpu-layout-exclusive-20261006/identity-audit/layout-identity-audit.json)
和逐用例完整 identity order 已保存。

| 用例 | identity 顺序相同 | 改变位置数 | 所有数组 hash 相同 |
| --- | --- | ---: | --- |
| Dot 128×8 | 是 | 0 | 是 |
| Dot 1024×32 | 是 | 0 | 是 |
| matmul 16×32×24 | 否 | 1,278 / 1,280 | 否 |
| matmul 32×64×48 | 否 | 5,118 / 5,120 | 否 |
| matmul 64×128×64 | 否 | 16,128 / 16,384 | 否 |

因此 Dot 的 Current/Predicted 计时差仅是同输入的噪声/测量差异待解释，**不是布局效应**。
matmul 有真实排列差异，但是否解释 GPU 时间仍需有效 counter 证据。

## 实测 kernel 与统计波动

第一轮独立 nsys resident kernel，单位 μs，单元格为 median [p10, p90]。
Current 是现有 discovery/单通道 packer 排列；Predicted 只用于 named walkers。

| 用例 | Current | Predicted | Random，合并三个 seed |
| --- | ---: | ---: | ---: |
| chain 128×8 | 3.200 [3.168,3.232] |  -  | 3.168 [3.104,3.200] |
| chain 1024×64 | 14.431 [14.399,14.432] |  -  | 17.072 [17.023,17.120] |
| Dot 128×8 | 12.960 [12.928,13.023] | 12.959 [12.927,12.992] | 13.567 [13.120,13.792] |
| Dot 1024×32 | 77.198 [47.967,77.534] | 77.294 [48.127,77.822] | 96.782 [69.503,97.886] |
| matmul 16×32×24 | 47.167 [47.071,47.199] | 47.279 [47.071,47.423] | 43.999 [43.679,44.479] |
| matmul 32×64×48 | 92.654 [92.574,92.702] | 93.054 [92.958,93.118] | 97.822 [97.470,98.110] |
| matmul 64×128×64 | 226.955 [184.220,245.115] | 257.994 [186.588,267.642] | 239.403 [199.835,242.139] |

宽分布用例追加固定输入、无构图/pack 的受控重放，16 次预热、64 次重复/seed。
[普通结果](../../dist/gpu-layout-exclusive-20261006/controlled-normal/records.csv)、
[独立 nsys](../../dist/gpu-layout-exclusive-20261006/controlled-trace.nsys-rep)、
[受控配对结果](../../dist/gpu-layout-exclusive-20261006/controlled-profile/records.csv)全部保留。
受控 nsys 的 Random/Predicted 配对比值：

| 用例 | seed 928 median | seed 929 median | seed 930 median | 合并 median [p10,p90] |
| --- | ---: | ---: | ---: | ---: |
| Dot 1024×32 | 1.260 | 1.257 | 1.261 | 1.260 [0.940,1.938] |
| matmul 64×128×64 | 0.942 | 1.007 | 0.990 | 0.995 [0.813,1.283] |

比值大于 1 表示 Random 较慢。Dot 相对 Random 的中位数差在三 seed 可复现，
但它并不说明新预测比 Current 更好，因为两者输入相同；matmul 比值跨越 1 且分布宽，
不能将第一轮单个 median 当稳定收益或稳定退化。小 matmul 的 Random 较快是测量事实，
GPU 机制原因尚不能解释。也不将未采样的动态时钟或其它因素当成已证实原因。

## 可由 profiling 支持的成本解释

nsys 实测短 chain 的 kernel 中位数约 3.2 μs，而同用例 one-shot 的 cuLaunchKernel
API 中位数约 5.81 μs；设备 H2D 合计约 3.78 μs、D2H 约 1.86 μs。
因此纯 kernel 的小差异不足以代表应用总成本。API 和 kernel 可重叠，不能简单相加。
共享输入大 matmul 的设备 copy 合计 H2D 约 85.87 μs、D2H 约 5.28 μs，
cuLaunchKernel API 约 7.01 μs。host API 包含提交/同步等成本，比纯设备 copy 时间更大；
原始 API 及 copy 记录见 trace-facts.json，不拿它们推断显存带宽瓶颈。

普通 one-shot 的 matmul 64×128×64，Current/Predicted/Random 的 pack 中位数分别为
223.416 / 223.182 / 259.365 ms；pack-through-D2H 为 224.202 / 223.986 / 260.154 ms。
Predicted 的 BFS 阶段中位数为 6.630 ms。相比数百 μs 的 kernel，重建/pack 成本是
当前一次性执行总成本的主要测量项；即使 resident kernel 节省几十 μs，也不足以
摊销每次重新 pack。两布局 pack 差异受整段采样波动影响，不能据此说 BFS 免费。
Graph build 单独计时，graph-through-D2H 是加上该独立测量的组合成本，未包括最终
输出节点发布；session/context 初始化单列为 setup，稳态 one-shot 复用 session。

[CPU cProfile](../../dist/gpu-layout-exclusive-20261006/cpu-profile/cpu-profile.json)
使用同样 64×128×64 图，仅 CPU、每布局三次 pack。Current 的 pack_cursors 累计
1.984 s，其中嵌套 walk 累计 0.645 s；Predicted 的 predict_layout 累计 0.115 s；
Random 的 permute_cursors 累计 0.233 s。它证实 collection/query、预测和重排确有
CPU 开销；profile 时间有 instrumentation overhead，不能替代普通 pack 计时，
嵌套累计时间也不能相加。`.prof` 原文件和 top functions 均保留。

当前适用结论：独立链相对随机排列的 resident 差异可测；此共享输入 matmul 范围
没有稳定的新 BFS kernel 收益，逐次 pack 不值得只为可能的微秒收益启用预测。
这不是 BFS 最优或必快的证据。最小下一步是复用已 pack 的 resident batch，提供
Current/Predicted 可选策略，并在有临时 ncu 权限后采集同 kernel 的事务/cache/
occupancy 指标，才决定是否修改共享节点冲突的合并策略。未取得 counter 前不宣称
图共享、lane 映射、FIFO 分歧、pointer chasing、cache 或计算吞吐是已证实瓶颈。

## 修改文件与验证入口

| 文件 | 用途 |
| --- | --- |
| `jac/jaclang/compiler/backends/native/ptx_walker.jac`, `ptx_csr.jac` | named cursor schema/LLVM lowering 接入，保留旧 dispatch |
| `jac/jaclang/runtime/gpu_cursors.py` | schema 子集检查、联合 FIFO kernel、预测 packer、SoA ABI 与 CUDA 执行 |
| `jac/jaclang/runtime/gpu.jac`, `gpu_cuda.jac` | schema、packer、内存计划、session dispatch |
| `jac/examples/gpu/named_cursors.jac` | Dot/Three/条件/循环/report/共享整数 matmul |
| `jac/tests/compiler/backends/native/test_ptx_named_cursors.jac`, `scripts/gpu_walker/test_named_cursors.py` | 编译、CPU/JIT/mock/实际 CUDA 正确性与拒绝诊断 |
| `scripts/gpu_walker/test_integers.py` | 修正临时模块名碰撞，允许组合回归运行 |
| `scripts/gpu_walker/compare_named_layouts.py`, `layout_benchmark.py`, `test_layout_benchmark.py` | 严格物理 permutation、配对计时、event instrumentation、边界测试 |
| `profile_named_layout.py`, `replay_layout_timings.py`, `analyze_layout_trace.py`, `profile_layout_cpu.py`, `audit_layout_orders.py` | 分离 counter/受控计时/trace事实/CPU profile/排列审计；均在 `scripts/gpu_walker/` |
| `docs/design/named-cursors.md`, `gpu-named-cursors.md`, 本文；`scripts/gpu_walker/README.md`, `runtime.md` | 语法、语义、ABI、运行与结果证据 |
| `scripts/gpu_walker/validation/named_cursors_3090.json`, `named_layouts_3090_profiled.json` | 初步正确性记录及正式测量完整机器报告 |

实际 CUDA 最终回归日志 [jac-named-exclusive-cuda.log](../../dist/gpu-layout-exclusive-20261006/jac-named-exclusive-cuda.log)，CPU 回归日志
[jac-named-final-host.log](../../dist/gpu-layout-exclusive-20261006/jac-named-final-host.log) 已随实验产物保留。Python 编译检查及
`git diff --check` 通过。共享目录中 Transformer/slides/littleX/pycore、数据文件和
stash 未被本任务改写；其他 agent 的提交/修改通过独立源码 hash 与快照区分。
