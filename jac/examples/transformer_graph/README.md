# Typed Jac Graph CPU / GPU Transformer

完整的一层编码器、一层解码器 Transformer：`d_model=8`、双头 attention（每头 4 维）、
`d_ff=16`、词表大小 13、随机种子 1729。采用原始架构的 post-norm、正弦位置编码、
ReLU FFN，推理不使用 dropout。默认标准库 CPU 路径无需依赖；可选 PyTorch CPU/CUDA
张量路径见后文。

从仓库根目录运行：

```bash
.venv/bin/jac run --backend python jac/examples/transformer_graph/demo.jac
.venv/bin/jac run --backend python jac/examples/transformer_graph/validate.jac
```

`jac` 已在 PATH 中时可替换 `.venv/bin/jac`。显式选择现有 Python CPU backend。
Jac CLI 首次使用会初始化编译/类型缓存；现有图运行时也会访问本地缓存。
只读沙箱中运行这些 CLI 命令需要允许访问 `~/.cache/jac`。

## 具体节点和参数字段

架构在 `model.jac` 的 `build()` 中建立：显式实例化具体 Jac node 类型，再使用
`+>: Flow(...) :+>` 建立真实边。`Module` 基类只承载调度状态及多态接口，
没有 `kind` 或 `weights` 字段。每个具体节点在 Jac 中声明命名参数字段、
`initialize()` 和 `evaluate()`；无参数节点没有占位权重。

| 具体 Jac 类型 | 图节点 | 实例持有的参数字段 |
| --- | --- | --- |
| Input | source、target | 无 |
| Embedding | enc_embed、dec_embed | 各自独立 `table` `[13,8]`，输出乘 `sqrt(8)` |
| PositionalEncoding | enc_pos、dec_pos | 无；Jac 中逐位置计算 sin/cos |
| SelfAttention | enc_attn | `w_q/w_k/w_v/w_o` `[8,8]`，`b_q/b_k/b_v/b_o` `[8]` |
| CausalSelfAttention | dec_attn | 直接声明自身 `w_q/w_k/w_v/w_o` 和 `b_q/b_k/b_v/b_o` 字段 |
| CrossAttention | cross_attn | 直接声明自身 `w_q/w_k/w_v/w_o` 和 `b_q/b_k/b_v/b_o` 字段 |
| FeedForward | enc_ffn、dec_ffn | `w_up` `[8,16]`、`b_up` `[16]`、`w_down` `[16,8]`、`b_down` `[8]` |
| AddNorm | enc_norm1/2、dec_norm1/2/3 | 各自的 `gamma`、`beta` `[8]`；epsilon 为 `1e-5` |
| Linear | projection | `weight` `[8,13]`、`bias` `[13]` |
| Softmax | probabilities | 无 |

三种 attention 类型各自直接声明 8 个参数字段和初始化方法，且各自的 Jac
`evaluate()` 明确执行 Q/K/V affine 与 O 输出投影。SelfAttention 的 Q/K/V
都来自 x；CausalSelfAttention 传入 causal=True；CrossAttention 的 Q 来自 x，
K/V 来自 memory。它们共享非参数基类 AttentionOps 中的 Jac `head_context()`：
head 切片、`QKᵀ / sqrt(head_width)`、因果 mask、逐行 softmax、加权 V 和拼接。
AttentionOps 不持有权重，也不在图中实例化；没有字符串架构分派。
FeedForward 在 Jac 中执行 up affine → ReLU → down affine；AddNorm 在 Jac 中
执行残差相加、逐 token 均值/方差、标准化及 gamma/beta affine。

`math_cpu.py` 只提供通用矩阵乘法、转置、affine、加法、缩放、ReLU、softmax、
随机矩阵以及数值检查原语；没有 Transformer、attention、FFN 或 norm 架构函数，
也不持有参数或执行前向调度。模型参数不共享，Linear 与 embedding 权重也不绑定。

## 实际架构与图导出

编码器：Embedding → PositionalEncoding → SelfAttention → AddNorm → FeedForward → AddNorm。
解码器：Embedding → PositionalEncoding → CausalSelfAttention → AddNorm →
CrossAttention → AddNorm → FeedForward → AddNorm → Linear → Softmax。

每个 AddNorm 都由对应子层输出 `main` 和子层输入 `skip` 两条边合流；
编码器最终输出通过 `encoder_memory:memory` 边接入 CrossAttention。
一共 18 个计算节点、22 条数据边、2 条 Model entry 边，包括 5 条残差跳连。

`demo.jac` 调用 `Model.export_dot()` 重新生成本目录 `graph.dot`：
它查询实际 Jac Flow 出边，读取真实目标节点及实际类型名称，不维护独立手写图。
可选渲染：

```bash
dot -Tsvg jac/examples/transformer_graph/graph.dot -o /tmp/transformer.svg
```

## Walker 就绪调度和重置

`Model.forward(source, shifted_target)` 在 Model 节点 spawn 一个新 `Infer` walker。
使用已有 CPU `spawn`、`visit` 和 `[edge ->:Flow:->]` 语法，不使用命名 cursor。

1. Model entry 清空每个模块的 inbox、output、diagnostics、done、queued；参数不变。
   source/target 节点收到各自的 `tokens`，然后从真实 entry 边发现输入节点并 visit。
2. walker 的 Module entry 适用于具体子类型，检查 `ready()`，多态调用其 `evaluate()`，
   标记 done 并记录 trace。没有预排的层执行列表或硬编码前向管线。
3. walker 遍历当前节点真实 Flow 出边，将输出传给目标节点 `inbox[edge.role]`。
   `Flow.path` 标记 main/residual/encoder_memory；role 决定节点读取哪个输入。
   未声明或重复输入角色直接报错。
4. 当全部 required 输入到达时才 visit 目标；queued 避免重复入队。
   AddNorm 必须等待 main 与 skip，CrossAttention 必须等待 x 与 memory。
5. 完成时检查全部模块都已执行。删除必需边、不可达节点或依赖循环无法静默完成。
   返回 walker 保留概率、节点访问 trace 和全部数据边 delivery。

模块注册表用于初始化、重置、快照和完成性检查；实际执行顺序由图边和 readiness 决定。
重连残差边会改变推理，删除 memory 边会阻断推理；验证直接操作真实 Jac 边。
每次运算产生新输出列表，旧返回值不会被后续推理修改。节点激活表示最近一次推理；
同一个 Model 不支持并发推理。

## Shifted target 与生成

约定 BOS=1、EOS=2。demo 的 labels 是 `[6,7,2]`，shifted target 是 `[1,6,7]`。
Teacher-forced forward 输入真实前缀，在每个位置输出下一 token 的概率，形状为
`[target_length,13]`。CausalSelfAttention 将严格上三角 score 设为负无穷，
softmax 后为零；位置 t 无法读取未来目标 token。没有 loss、训练或反向传播。

`greedy()` 从 `[BOS]` 开始，每次用已生成前缀重新运行同一张图，选择最后位置
概率最大的 token；遇 EOS 或步数上限结束。返回包含 BOS，以及生成到的 EOS。
后续输入是模型自己的预测，与 teacher forcing 使用真实 labels 不同。
没有 KV cache，每步也重新计算编码器。

## 独立参考与验证

`Model.parameter_snapshot()` 多态调用每个具体节点的 `parameters()`，从其命名
字段读取并深拷贝参数。字典仅是独立参考的传输快照，不是推理的权重表示或参数所有者。
`reference.py` 使用独立 CPU 数值公式和显式参考管线，不导入实现的数值原语，
不调用任何 Jac evaluate/head_context 方法。仅验证程序使用这条参考管线。

`validate.jac` 比较全部 18 个节点的中间结果（容差 `1e-12`），并检查：

- 10 种具体节点类型、命名字段、独立参数快照和非参数节点；
- 全部中间矩阵形状与有限值、概率归一化，包括输入长度 2/1、1/5、5/2；
- 三种 attention 的双头概率形状、causal 上三角零值与未来 token 前缀隔离；
- 源输入扰动影响输出，CrossAttention 收到真实编码器输出对象；
- 长度变化后原输入完全复现，旧返回值与 trace/deliveries 保持不变；
- 每个模块恰好执行一次、22 条真实边的生产者顺序和输入对象、5 个残差合流；
- 入口边逆序结果不变，重连残差改变结果，删除 memory 后 CrossAttention 不执行；
- 直接修改 Embedding、三种 attention 全部 Q/K/V/O、FFN、AddNorm、Linear 字段，
  修改后的全部中间结果仍匹配独立参考；短贪心生成。

随机初始化仅证明架构与执行正确性，不代表训练后的语言模型质量。
仅支持单样本、非空序列，无 padding mask、批处理、训练、持久化或 KV cache。
使用 Python float 和列表矩阵，适合小规模示例；配置常量在 `model.jac`，维度须能
整除头数。边目标读取使用现有运行时 `__jac__` anchor API。

本次最终 demo 与 validate 均退出 0：18 个节点基准最大绝对误差
`6.661338147750939e-16`，不同长度最大误差 `8.881784197001252e-16`，
直接修改命名参数字段后最大误差 `4.996003610813204e-16`。
编码器输入扰动产生最大概率变化 `0.04607110721894103`。
默认 demo 的 teacher-forced argmax 为 `[6,5,12]`，贪心序列为
`[1,6,5,12,5,12]`（包含 BOS）。

## PyTorch CPU / CUDA 张量路径

默认 `build()` 仍可直接运行标准库列表 CPU 推理，无 PyTorch 依赖。
可选 `model.to("cpu", "float64")` 或 `model.to("cuda:0", "float64")` 将每个
具体节点的命名参数字段转换为该 device/dtype 的张量。切换设备时只转换一次，
节点仍是参数所有者；没有模型级权重字典，没有 `nn.Transformer`。
`build(dimension=256, heads=8, hidden=1024, vocabulary=1024)` 创建较大的一层模型。

Jac 节点方法直接使用 PyTorch 的 index_select、matmul、reshape/transpose、
mask、softmax、ReLU、均值/方差等原语。`tensor_ops.py` 只提供可选依赖加载、
张量放置、token 入口检查和 greedy 单 ID 读取，不表达任何 Transformer 前向结构。
张量执行与列表执行使用同样的真实边和 `Infer` walker readiness 调度。
walker 在主机上运行；矩阵计算由 PyTorch 在 CPU 或 CUDA 上执行。

权重、激活、位置编码及 causal mask 驻留所选设备。位置编码/mask 按长度缓存，
`to()` 会清空这些设备相关缓存；缓存不含本次推理激活，所以不破坏状态隔离。
数据边只传同一个 tensor 对象引用，不复制、不下载、不在节点之间同步。
默认使用调用者当前的同一 CUDA stream，不启动辅助 stream。
列表 token 在一次 forward 的入口转换/上传；预先放置的 int64 token tensor
不再上传，其 ID 范围应由调用者预先验证。节点中不使用 `.item()` 或 `.cpu()`。
Greedy 每个生成步结束时读取一个 argmax ID，这是单步控制依赖，未计入前向基准。

可复现依赖（本次安装，仅 torch 和其必需依赖）：

```bash
.venv/bin/pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cu128
```

CPU 正确性验证（包括小型和中等模型、float64 和 float32）：

```bash
.venv/bin/jac run --backend python jac/examples/transformer_graph/tensor_runner.jac --mode validate --device cpu --check-compile
```

CUDA 测试和正式测量必须在协调好的 GPU 独占时段执行，不与 GPU layout 实验并行：

```bash
.venv/bin/jac run --backend python jac/examples/transformer_graph/tensor_runner.jac --mode validate --device cuda:0 --check-compile --exclusive-note "coordinated exclusive measurement slot"
.venv/bin/jac run --backend python jac/examples/transformer_graph/tensor_runner.jac --mode benchmark --device cpu
.venv/bin/jac run --backend python jac/examples/transformer_graph/tensor_runner.jac --mode benchmark --device cuda:0 --exclusive-note "coordinated exclusive measurement slot"
```

`results/validation_cpu.json`、`validation_cuda.json` 保存验证结果、环境、trace 和
角色传递。CPU/GPU 的相同初始化/输入在所有中间结果上差分；还检查 mask、
残差和 memory 的对象身份、源输入影响、不同长度/重复调用、命名参数直接修改、
greedy、float32，以及 forward 内的 scalar extraction/CPU download/synchronize 禁用审计。
`configuration_validation` 额外验证默认两组配置和两个 dtype 的中间形状、有限值、
CPU/device 差分、概率与真实边重连后的对应基线。审计只针对已缓存、resident 输入的
forward；输入上传、断言、输出展示和 greedy 的单步读取发生在该区域之外。

`results/tensor_cpu.dot` 和 `tensor_cuda.dot` 由实际图导出；对应 `_rewired.dot`
来自将 encoder 第一个 AddNorm 的 skip 从 enc_pos 改接到 enc_attn 的真实图。
只改变边，walker 流程不改；baseline 显式选择相同的 skip 输入。
还测试恢复原边后结果恢复，删除 memory 边后无法完成。

## 性能研究方法与证据

`tensor_baseline.py` 是仅比较使用的独立 PyTorch eager 管线，读取参数快照。
它与 Jac 张量节点使用同样的数值原语，shape、参数、输入、dtype、device、TF32
设置一致。位置编码/mask 都缓存。基线保留全部模块输出和 attention maps，与图的
中间结果可观察性及对象生命周期一致；这不是只输出最终概率的最激进优化上限。
可用时实际执行 `torch.compile(backend="inductor", fullgraph=True, dynamic=False)`，
关闭 CUDA graphs；数值错误会报错，编译不支持时 JSON 明确记录原因。
不会把 eager 回退冒充编译结果。图重连后基线也切换相应分支，单独记录首次编译。

默认测量小型（d=8, heads=2, FF=16, V=13, source=4, target=3）和
中等（d=256, heads=8, FF=1024, V=1024, source=128, target=96），均 batch=1。
先 float64 验证，再考虑 float32 性能模式，不使用 TF32 或 dropout。
CPU math 和编译 worker 各限制为 1；warmup=5，3 轮，每轮每方法 12 次。
每轮随机化方法顺序，JSON 保留全部样本和 p10/median/p90/p95、均值和范围。

报告将以下阶段分开，不能把它们相减当作严格因果分解：

- 库导入、CUDA context 初始化、图/参数初始化、张量放置、首次 forward 与缓存创建；
- 编译 wrapper 创建及首次调用的编译+执行耗时（注明持久编译缓存是否已存在）；
- warmup 与稳态端到端延迟：resident 输入，含 walker、数学执行、请求边界等待；
- CUDA host enqueue 与 event stream span：event 包围 host 调度，包含 host 造成的
  stream 空闲间隙，**不是纯 kernel 时间**；同步只发生在请求边界；
- `schedule_replay()` 仅在性能实验中重放已计算的 tensor 句柄，沿同样真实边和
  readiness/visit 运行，不执行数学。这是调度微基准，不是模型推理；
- 单独的 cProfile 与 PyTorch/Kineto profiler：前者记录主机函数的 exclusive 时间，
  不启用节点 range；后者启用 `Jac.node/...` range，保存 Chrome trace、实际 kernel
  数量/耗时及 launch 记录。profile 是带观察开销的独立运行，不能当稳态延迟。

`results/benchmark_cpu.json`、`benchmark_cuda.json` 保存正式测量、每次重连结果、
初始化/编译/warmup、调度重放以及 profiler 汇总；`results/profiles/*.trace.json`
保留原始时间线。`results/smoke_cpu` 仅用于验证基准/编译/profiler 脚本，样本太少，
不用于性能结论。profile 的 kernel duration sum 与 kernel window 不同；window-minus-sum
包含提交间隙及测量中的主机工作，不把它单独归因为 Jac。

## 已完成的测量与结论（2026-10-06）

GPU layout agent 释放设备后，在授权的独占时段完成真实 CUDA 验证、计时和
profiling。环境为 RTX 3090 24 GiB、driver 595.71.05、PyTorch 2.8.0+cu128、
CUDA 12.8、Python 3.13.7。CPU 单线程；两组 shape、两种 dtype、原图/重连图、
三种实现，各 36 个稳态样本，共 1728 次端到端测量。以下为原图 median / p90：

| device | config | dtype | Jac median / p90 ms | eager median / p90 ms | compile median / p90 ms |
|---|---|---|---:|---:|---:|
| cpu | small | float64 | 1.2181 / 1.2928 | 0.4394 / 0.4918 | 0.2110 / 0.2598 |
| cpu | small | float32 | 1.1775 / 1.3168 | 0.4400 / 0.4813 | 0.2023 / 0.2287 |
| cpu | medium | float64 | 12.1298 / 12.3528 | 11.1892 / 11.5228 | 10.4964 / 11.0600 |
| cpu | medium | float32 | 6.2874 / 6.7519 | 5.5660 / 5.7599 | 5.0890 / 5.7748 |
| cuda | small | float64 | 2.0699 / 2.2640 | 1.2498 / 1.4850 | 0.8316 / 1.0315 |
| cuda | small | float32 | 2.3847 / 2.6691 | 1.5243 / 1.5796 | 0.9141 / 0.9409 |
| cuda | medium | float64 | 2.9897 / 3.3334 | 2.6762 / 3.0234 | 2.3128 / 2.3225 |
| cuda | medium | float32 | 2.4504 / 2.4611 | 1.6213 / 1.6748 | 0.9306 / 0.9784 |

中等 float32 的 **Jac GPU forward 中位数为 2.4504 ms，eager 为 1.6213 ms，
compile 为 0.9306 ms**。本实验中 Jac 没有优于等价 PyTorch 基线。
中等 float64 从 Jac CPU 12.1298 ms 降至 CUDA 2.9897 ms，体现设备数学执行的
收益，不代表 Jac 语言加速。小配置 CUDA 比 CPU 更慢；下面的独立 profiling
观察显示数学工作很少而提交间隙明显，支持关注主机提交成本。

CPU/CUDA 全部中间结果和 attention maps 验证通过：float64 最大设备差异
1.6432e-14，float32 为 8.7023e-6；同设备 Jac/eager 差异为零。
CPU 与 CUDA 的 fullgraph Inductor 在原图和重连图上均实际执行并通过验证。
mask、不同长度、残差/memory 角色、参数修改、重复推理隔离、删除 memory 边、
resident forward 无 scalar extraction/下载/逐节点同步的审计均通过。
随机初始化仅展示架构执行，生成 token 不代表语言模型质量。

独立 CUDA profiler 每种方法记录 3 次请求。下表只报告每请求的 kernel 数量与
kernel duration sum（ms）；这些数值来自带 profiler 的运行，**不能与上表未
profile 的延迟混用，也不能作为其严格因果分解**：

| config / dtype | Jac kernels / sum ms | eager kernels / sum ms | compile kernels / sum ms |
|---|---:|---:|---:|
| small / float64 | 109 / 0.3264 | 109 / 0.3262 | 42 / 0.2037 |
| small / float32 | 109 / 0.1989 | 109 / 0.1991 | 42 / 0.0811 |
| medium / float64 | 109 / 2.5579 | 109 / 2.5634 | 40 / 2.1738 |
| medium / float32 | 123 / 0.4123 | 123 / 0.4134 | 53 / 0.2609 |

Jac/eager 的 kernel 数量相同、duration sum 接近，说明这里没有额外的数学内核
加速；compile 的实际内核/启动数量更少，支持减少提交与中间原语开销的解释。
中等 float32 三次请求的 profile kernel window 为 Jac 11.5955、eager 7.1695、
compile 4.1565 ms，window-minus-sum 分别为 10.3587、5.9292、3.3739 ms。
这些间隙包括主机提交和 profiler 的观察开销，不能全部归因为 walker。

调度句柄重放在 CUDA 四组配置的中位数为 0.5030–0.5228 ms，CPU 为
0.4977–0.5186 ms，量化了当前真实边遍历/readiness 的基础成本，但重放不是
真实推理，也不能从 forward 延迟中扣除。独立 cProfile 中，CUDA 中等 float32
三次 Jac 请求的 runtime/server/data exclusive 时间共 3.4477 ms，包含
`walk`、`next_slot`、`hop` 等实际调用；模型方法共 2.9421 ms，PyTorch 调用共
3.2949 ms。结合相同数学内核和调度重放，这些证据支持存在主机遍历/调度成本，
不提供严格的端到端因果拆分。

首次成本独立记录：本次 CUDA 库导入约 1053.5 ms、context 初始化 111.8 ms，
小配置首个 Jac forward（含位置/mask 缓存及首次算子初始化）172.9 ms。
原图 compile 首次调用 CPU 为 283.8–3235.7 ms，CUDA 为 272.5–1775.4 ms；
**持久 Inductor 缓存已存在**，这些不是干净冷缓存编译数据，不可据此推算冷启动
盈亏平衡。wrapper、图构建、放置、首次 eager、重连后的首次 compile、warmup
分别保存在 JSON。CUDA case 的峰值 allocated 为 9.27–140.16 MiB，包含同一
进程内各基线、验证和 profiler，不是单个模型的最小内存需求。

实际改变 `enc_norm1` 的 skip 边后，walker 自动使用新输入，流程代码不变；
中等 float32 概率最大变化 0.0284492，与对应 eager/compile 基线一致。
重连图的 GPU 中位数为 Jac 2.4470、eager 1.5950、compile 0.9185 ms，完整分布
保存在 JSON。图的价值在此是可执行、可检查、通过连接改变依赖关系；这不构成
“存在图即有性能贡献”的证明。现有数据更支持先研究调度/提交开销与受控融合，
不支持投入巨大融合编译器或声称单 kernel 会解决所有问题。

局限：仅一层 encoder/decoder、batch=1、两组长度、单 GPU；没有训练、反向传播、
KV cache、padding mask、混合精度、CUDA graphs 或吞吐量实验。compile 使用固定
shape，并保留中间结果，因此不是生产优化的最强基线。性能结论只适用于当前
配置/环境；raw samples 和 trace 保留用于复核。

重新生成摘要（不启动 GPU、不重新计时）：

```bash
.venv/bin/python jac/examples/transformer_graph/analyze_tensor_results.py
```

输出 `results/summary.json` 与 `results/timing_table.md`；原始正式 JSON 和 Chrome
trace 为证据来源。原始列表 CPU demo/validate 和新增 tensor validate 均执行通过。


数值/计时依据：[PyTorch CUDA semantics](https://docs.pytorch.org/docs/2.8/notes/cuda.html)、
[torch.compile](https://docs.pytorch.org/docs/2.8/generated/torch.compile.html)、
[固定版本安装](https://pytorch.org/get-started/previous-versions/#v2-8-0)。
