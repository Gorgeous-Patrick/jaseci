# Cursor 顺序拼接 BFS：实际布局、GPU 测量与证据边界（2026-10-07）

默认 `predicted` 已修正为 **按 cursor 声明顺序拼接完整的 batch 多源 BFS**：先放完整 a，再放完整 b，任意更多通道依次处理。共享 node identity 只保留第一次出现；剩余节点按原 discovery 顺序 fallback。旧 rank 交错实现已移除，没有兼容模式或旧方案重测。执行 FIFO、重复 arrival、联合触发、lane 顺序及邻接行顺序未改变。

**硬件 counter 证据缺口：Nsight Compute 2025.3.0 实际返回 `ERR_NVGPUCTRPERM`。没有实际 coalescing、sector/request、cache hit、DRAM bytes/bandwidth 或 occupancy 对照，不能解释 GPU 机制。未修改驱动/系统配置，未用 sudo 或索取密码。下面理论 sector 模型不能补充为硬件实测。**

GPU 独占时段由主 agent 协调；开始时 `nvidia-smi` 无计算进程，采集与正确性完成后已明确释放 GPU。旧[2026-10-06 报告](gpu-cursor-layout-results.md)保留历史数字，仅加旧方案提示，原始数据未改写。

## 1. 实际布局是否改变

4×4 和矩形 3×5×2 使用实际 packed heads/CSR 恢复身份标签，不从值猜 identity，也没有把矩阵坐标传给 packer。每个输入及输出 Scalar 只有一个 int；输入按身份共享，不按乘积复制。以下每一行就是物理 index 的实际身份：

### matmul-4x4x4

| Physical index | Current identity | 新 Predicted identity |
| ---: | --- | --- |
| 0 | A[0,0] | A[0,0] |
| 1 | B[0,0] | A[1,0] |
| 2 | B[0,1] | A[2,0] |
| 3 | B[0,2] | A[3,0] |
| 4 | B[0,3] | A[0,1] |
| 5 | A[1,0] | A[1,1] |
| 6 | A[2,0] | A[2,1] |
| 7 | A[3,0] | A[3,1] |
| 8 | A[0,1] | A[0,2] |
| 9 | B[1,0] | A[1,2] |
| 10 | B[1,1] | A[2,2] |
| 11 | B[1,2] | A[3,2] |
| 12 | B[1,3] | A[0,3] |
| 13 | A[1,1] | A[1,3] |
| 14 | A[2,1] | A[2,3] |
| 15 | A[3,1] | A[3,3] |
| 16 | A[0,2] | B[0,0] |
| 17 | B[2,0] | B[0,1] |
| 18 | B[2,1] | B[0,2] |
| 19 | B[2,2] | B[0,3] |
| 20 | B[2,3] | B[1,0] |
| 21 | A[1,2] | B[1,1] |
| 22 | A[2,2] | B[1,2] |
| 23 | A[3,2] | B[1,3] |
| 24 | A[0,3] | B[2,0] |
| 25 | B[3,0] | B[2,1] |
| 26 | B[3,1] | B[2,2] |
| 27 | B[3,2] | B[2,3] |
| 28 | B[3,3] | B[3,0] |
| 29 | A[1,3] | B[3,1] |
| 30 | A[2,3] | B[3,2] |
| 31 | A[3,3] | B[3,3] |

identity order SHA256：Current `bcc9bcfc670935c6018dc26a74956a373b655f8930dd55ab074d816d7d233780`；Predicted `1f70283cd73e5351a5550bc41f6fc4cb862b086ea750538beedc54d10a0c9aba`。

### matmul-3x5x2

| Physical index | Current identity | 新 Predicted identity |
| ---: | --- | --- |
| 0 | A[0,0] | A[0,0] |
| 1 | B[0,0] | A[1,0] |
| 2 | B[0,1] | A[2,0] |
| 3 | A[1,0] | A[0,1] |
| 4 | A[2,0] | A[1,1] |
| 5 | A[0,1] | A[2,1] |
| 6 | B[1,0] | A[0,2] |
| 7 | B[1,1] | A[1,2] |
| 8 | A[1,1] | A[2,2] |
| 9 | A[2,1] | A[0,3] |
| 10 | A[0,2] | A[1,3] |
| 11 | B[2,0] | A[2,3] |
| 12 | B[2,1] | A[0,4] |
| 13 | A[1,2] | A[1,4] |
| 14 | A[2,2] | A[2,4] |
| 15 | A[0,3] | B[0,0] |
| 16 | B[3,0] | B[0,1] |
| 17 | B[3,1] | B[1,0] |
| 18 | A[1,3] | B[1,1] |
| 19 | A[2,3] | B[2,0] |
| 20 | A[0,4] | B[2,1] |
| 21 | B[4,0] | B[3,0] |
| 22 | B[4,1] | B[3,1] |
| 23 | A[1,4] | B[4,0] |
| 24 | A[2,4] | B[4,1] |

identity order SHA256：Current `2a0a16a7ce85c211f6b6e8a758e7ec09f9fd77e230e81d74c30a857dd51e2de6`；Predicted `860683d08c5e487f7fb5f350d2a6e3d093d0524fa383f9e42a4d5cfe26e89621`。

4×4：a 的 A 身份完整占据 index 0–15，b 的 B 身份完整占据 16–31。矩形：A 占据 0–14，B 占据 15–24。每个通道内部都先放整个 batch 的种子，再按 BFS 层推进；没有逐 walker 串接完整路径。

[完整小矩阵审计](../../dist/gpu-cursor-concat-20261007/audit-named/audits.json)保留索引、identity、投影值、原始 typed 数组及每列 hash。正式 benchmark 另外在 CPU 重建全部用例，所有布局每个数组的 dtype/count/SHA256 必须与实测完全相同，才接受身份顺序审计：

| 用例 | 身份位置改变数 / 节点数 | Current/Predicted 全数组 hash 相同 |
| --- | ---: | --- |
| dot-128x8 | 2046 / 2048 | 否 |
| dot-1024x32 | 65534 / 65536 | 否 |
| matmul-4x4x4 | 31 / 32 | 否 |
| matmul-3x5x2 | 24 / 25 | 否 |
| matmul-16x32x24 | 1279 / 1280 | 否 |
| matmul-32x64x48 | 5119 / 5120 | 否 |
| matmul-64x128x64 | 16383 / 16384 | 否 |

[全部身份/数组审计](../../dist/gpu-cursor-concat-20261007/benchmark-identity-audit/layout-identity-audit.json)。本轮 Dot 也有真实排列差异，与昨日交错方案的 Current/Predicted 相同情况不同。

## 2. 实测 coalescing / cache / DRAM 差异

**无法回答硬件差异。** 普通用户 ncu 在真实 kernel 上检查当前权限，失败日志：[原始 `/tmp` 日志](/tmp/jac-concat-ncu-probe.log)、[保留副本](../../dist/gpu-cursor-concat-20261007/jac-concat-ncu-probe.log)。只读驱动信息为 `RmProfilingAdminOnly: 1`。没有生成有效 counter report/metric CSV；catalogue 查询只证明工具有哪些指标，不能当测量。

独立[理论地址模型](../../dist/gpu-cursor-concat-20261007/benchmark/theoretical-sectors.json)逐 cursor、logical load、warp、round 分别计算 32-byte sector，不把不同 load 或不同 round 合并成一个请求。假设 arena 基址 256-byte 对齐、标量 8 bytes、warp 32 lanes；仅覆盖此处无条件单后继、单种子 Dot，拒绝条件/分支模式。模型不是执行指令、硬件请求数、cache miss 或 DRAM 流量，不模拟后端优化和缓存复用。

64×128×64，logical load 的 distinct sector 中位数（Random 示例 seed 928；全部 seed 见原始 JSON）：

| 通道 / logical load | Current | 新 Predicted | Random-928 |
| --- | ---: | ---: | ---: |
| node_value.column_0.cursor_0 | 1 | 1 | 1 |
| node_value.column_0.cursor_1 | 9 | 8 | 32 |
| tag.cursor_1 | 9 | 8 | 32 |
| csr_begin.cursor_1 | 9 | 9 | 32 |
| csr_end.cursor_1 | 9 | 9 | 32 |
| csr_target.cursor_1 | 8 | 8 | 32 |

这里改变的是 value/tag 的理论地址覆盖，不是所有 CSR load；CSR plane 中 `node_count+1` 的位移也进入精确地址计算。原始 JSON 记录第一 warp 前两 round 的具体 byte addresses/sector IDs，可逐项复核。该事实不证明真实事务减少，也不能解释下面的 GPU 排名。

## 环境、kernel 与实验方法

实际设备 RTX 3090，驱动 **580.65.06**；Python **3.12.11**，LLVM **20.1.8**（独立 `/tmp` llvmlite 0.46.0 shim），nsys **2025.3.2.367**，ncu **2025.3.0.0**。不沿用昨日驱动/Python/Nsight 配置。源码 revision `3505f21febf7a92dcedebd0f59d315f1e4965a88`，工作区未提交；关键文件 hash 及与测量 hash 完全匹配的源码快照已保留。未锁定 GPU 时钟。

全部布局、用例使用同一个 `jac_Dot_cursors_batch`，PTX SHA256 `1dcb05c5f3cc1dfc7aa4a6ec3d79e4bc096f9b0842977b50183694db3131fdca`，PTX 6.0 / sm_70，block=128；每个用例 layout 使用同输入、dtype=int64、lanes、grid 与资源参数。Random 只 permutation 统一去重的物理 node 索引，重映射所有列/heads/CSR 行和 targets，保留行内顺序与 lane 分派。

每 seed 928/929/930 做 6 次预热、16 次配对重复，pair 内布局顺序确定性随机化。每次 launch 全 lane 对独立 CPU oracle 和 Current 结果校验，代表 lane 另运行真实 Jac CPU walker。输入 nodes 分别为 `(M+N)*K`，显式 node/lane/payload 上限控制规模。普通计时和 nsys 重放分开，所有 2,807 次 kernel 的名称/几何/顺序均严格对齐。

本轮使用按请求 schema 懒加载的 named-only 路径；旧 Chain schema 的 LLVM pass-builder ABI 不匹配未作为本任务处理，**旧 Chain 回归本轮未重跑**。15 项 named 测试已通过 CPU/JIT/真实 CUDA，包含 3/7 cursor、共享 identity、空/不等长队列、重复 arrival、CSR 分支、条件 visit、循环、report，以及新完整拼接/fallback/共享顺序回归。物理 permutation/汇总边界测试 2 项通过。

## 时间事实与分布

第一轮独立 nsys resident kernel（μs，median [p10,p90]），不是 event 区间。每格包含全部三个 seed，未挑最快 seed：

| 用例 | Current | 新 Predicted | Random |
| --- | ---: | ---: | ---: |
| dot-1024x32 | 77.681 [48.161,78.433] | 77.440 [47.488,77.953] | 96.881 [69.313,97.985] |
| dot-128x8 | 14.976 [14.944,15.009] | 14.848 [14.784,14.912] | 15.776 [15.489,16.064] |
| matmul-16x32x24 | 47.297 [47.200,47.360] | 47.329 [47.201,47.392] | 44.400 [44.128,45.472] |
| matmul-32x64x48 | 93.024 [92.801,93.089] | 92.736 [92.641,92.833] | 98.080 [97.760,98.369] |
| matmul-3x5x2 | 7.712 [7.680,7.712] | 7.200 [7.168,7.232] | 6.816 [6.464,7.040] |
| matmul-4x4x4 | 6.720 [6.688,6.721] | 6.784 [6.720,6.784] | 5.968 [5.728,6.368] |
| matmul-64x128x64 | 237.266 [184.481,253.794] | 259.522 [183.970,268.514] | 238.674 [200.834,243.458] |

宽分布用例追加固定输入、无 build/pack 的 16 次预热/64 次重复每 seed：普通 event 单独采集，nsys 再单独重放。第一份补采普通样本与 CPU trace 提取有重叠，仍留档，但报告使用不并行 CPU 分析的 `controlled-normal-isolated`，不覆盖原样本。

受控 nsys 的 **Predicted/Current** 配对比值；小于 1 为 Predicted 较快：

| 用例 | seed 928 median | seed 929 median | seed 930 median | 合并 median [p10,p90] |
| --- | ---: | ---: | ---: | ---: |
| dot-1024x32 | 0.9840 | 0.9852 | 0.9864 | 0.9853 [0.6451,1.0023] |
| matmul-64x128x64 | 1.0131 | 0.9739 | 0.9778 | 0.9806 [0.7586,1.2710] |

大 MatMul 第一轮三 seed 的 Predicted/Current 配对 median 为 1.0562/1.0607/1.0734；受控重放跨过 1，普通 event 与 nsys 的 Random 排名也不同。不能把一轮 median 当稳定收益或稳定退化。Dot 相对 Random 的中位数差可重复观察，新 Predicted 相对 Current 的差小且轮次依赖；这里不声明统计显著性，更不归因于 coalescing/cache。小 MatMul 的 Random 更快也是保留的负结果，GPU 原因未知。

## Pack、copy、应用成本的 profiling 事实

普通计时分别记录 build、collection、prediction、SoA/remap、random permutation、host H2D/D2H API、event 和执行 wall。Event 区间可能含 enqueue 间隙；nsys 另给精确 kernel/device copy/launch API，不混为一种时间。

一次性运行成本（ms，各布局配对样本的中位数）：

| 用例 / 指标 | Current | 新 Predicted | Random |
| --- | ---: | ---: | ---: |
| matmul-3x5x2 / pack | 0.3623 | 0.3777 | 0.4504 |
| matmul-3x5x2 / H2D | 0.1089 | 0.1084 | 0.1087 |
| matmul-3x5x2 / D2H | 0.0170 | 0.0171 | 0.0171 |
| matmul-3x5x2 / pack_through_D2H | 0.6487 | 0.6612 | 0.7366 |
| matmul-3x5x2 / graph_through_D2H | 0.8255 | 0.8380 | 0.9135 |
| matmul-4x4x4 / pack | 0.4821 | 0.4967 | 0.5817 |
| matmul-4x4x4 / H2D | 0.1105 | 0.1101 | 0.1099 |
| matmul-4x4x4 / D2H | 0.0171 | 0.0168 | 0.0169 |
| matmul-4x4x4 / pack_through_D2H | 0.7687 | 0.7817 | 0.8657 |
| matmul-4x4x4 / graph_through_D2H | 0.9972 | 1.0101 | 1.0941 |
| matmul-64x128x64 / pack | 294.7695 | 297.0577 | 298.4864 |
| matmul-64x128x64 / H2D | 0.2588 | 0.2579 | 0.2437 |
| matmul-64x128x64 / D2H | 0.0282 | 0.0279 | 0.0276 |
| matmul-64x128x64 / pack_through_D2H | 295.5495 | 297.8059 | 299.3431 |
| matmul-64x128x64 / graph_through_D2H | 464.8301 | 467.0865 | 468.6237 |

pack-through-D2H 是 pack 与 execute wall 的组合成本；graph-through-D2H 再加独立测得的 build，**不是包含 cold context 初始化、验证和最终输出 node 发布的完整应用 wall timer**。稳态 one-shot 复用 session；resident 模式排除输入 upload，output poisoning 和验证不在 kernel timer 内。限制完整写在 timing contract，不冒充冷启动端到端加速。

nsys 的 4×4 Current one-shot：device H2D 合计 4.320 μs、D2H 1.664 μs、cuLaunchKernel API 6.065 μs；纯 resident kernel 约 6.720 μs。64×128×64 Current 的对应设备 copy 为 84.081/5.376 μs、launch API 6.670 μs。API 与 device 可重叠，不直接相加；不拿 copy 时长推断显存带宽瓶颈。

当前大 MatMul pack 约 295–299 ms，而 kernel 约数百 μs；Predicted 的 prediction 阶段普通 median 5.728 ms。逐次重新 pack 时，这些 CPU 成本远大于所观察到的微秒级 kernel 差异。CPU [process-time cProfile](../../dist/gpu-cursor-concat-20261007/cpu-profile-process-time/cpu-profile.json)独立于 GPU 采集，三次 pack：Current pack_cursors 累计 4.641 CPU s，其中嵌套 walk 1.526 s；Predicted 的 predict_layout 0.264 s；Random permute_cursors 0.590 s。它支持 query/预测/重排实际消耗 CPU 的判断，不替代普通计时；timer/profiler 开销显著，嵌套累计时间不能相加。

适用结论：实际拼接策略已落实，但在这批共享输入 MatMul 上不能声称稳定 resident 收益；一次性使用不值得仅为微小不稳定的 kernel 差而承担额外预测。缓存/访存/occupancy 解释留空。下一步最小验证是获得可用的普通 counter 权限后对同一 kernel/数据采 sector/request/cache/DRAM，并复用 packed resident batch 来单独评估布局；不先按理论 sector 数承诺优化收益。

## 复现与原始证据

```sh
export XDG_CACHE_HOME=/tmp/jac-cursor-concat-cache
export JAC_CACHE_HOME=/tmp/jac-cursor-concat-cache/jac
export JAC_PG_DIST=/home/baichuan/.cache/jac/pg/dist/linux-amd64-18.6.0
export JAC_LLVM_SHIM=/tmp/jac-cursor-llvm/llvmlite/binding/libllvmlite.so
export PYTHONPATH=jac
# llvmlite 0.46.0 installed only under /tmp/jac-cursor-llvm; shared env unchanged
env/bin/python scripts/gpu_walker/compare_named_layouts.py \
  --chain-cases --dot-cases 128x8 1024x32 \
  --matmul-cases 4x4x4 3x5x2 16x32x24 32x64x48 64x128x64 \
  --seeds 928 929 930 --warmup 6 --repeats 16 --profile \
  --output /tmp/jac-layout-cursor-concat-20261007
```

重复时选择新输出目录，避免覆盖既有样本。GPU 时段需先协调；CPU audit/model/profile 不申请设备。完整命令、版本、environment、source/shim/PTX hash 见[采集元数据](../../dist/gpu-cursor-concat-20261007/profiling-evidence.json)。

- [机器报告与每 seed 配对分布](../../scripts/gpu_walker/validation/cursor_concatenation_3090_20261007.json)
- [普通 CSV](/tmp/jac-layout-cursor-concat-20261007/wall-events.csv)、[输入/哈希](/tmp/jac-layout-cursor-concat-20261007/inputs.json)
- [nsys 原报告](/tmp/jac-layout-cursor-concat-20261007/trace.nsys-rep)、[SQLite](/tmp/jac-layout-cursor-concat-20261007/trace.sqlite)、[逐 launch CSV](/tmp/jac-layout-cursor-concat-20261007/profile-launches.csv)
- [受控 nsys](/tmp/jac-layout-cursor-concat-20261007/controlled-trace.nsys-rep)、[受控配对 CSV](/tmp/jac-layout-cursor-concat-20261007/controlled-profile/records.csv)、[受控普通 CSV](/tmp/jac-layout-cursor-concat-20261007/controlled-normal-isolated/records.csv)
- [kernel/copy/API correlation 事实](/tmp/jac-layout-cursor-concat-20261007/trace-facts.json)、[counter 失败](/tmp/jac-concat-ncu-probe.log)
- [15 项 CUDA 回归](/tmp/jac-concat-cuda-tests.log)、[CPU/JIT 回归](/tmp/jac-concat-host-tests.log)、[补充 MatMul CPU/JIT](/tmp/jac-concat-matmul-host.log)

完整 raw 副本（typed 数组、所有样本、source snapshot、profiler/.prof、理论逐地址、SHA 清单）位于 `dist/gpu-cursor-concat-20261007/`。主要改动：gpu_cursors.py 合并顺序；test_named_cursors.py 三项 meaningful 回归；runner/replay/profile helpers 的请求 schema 懒加载和策略标记；新实际 MatMul 审计与理论地址模型；语义和结果文档。未切分支、commit/push，未覆盖根目录图像、env、output、task.c/task_bins 或其他 agent 文件；stash 未改动。
