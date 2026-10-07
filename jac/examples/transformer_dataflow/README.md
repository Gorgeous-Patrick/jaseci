# 操作级 Jac Transformer 数据流

本示例独立于 `../transformer_graph/`；不修改或替换其源码、结果或文档。
目标是可检查的操作图与 metadata/liveness 分析，不是性能优化、训练或融合编译器。
一层 encoder + 一层 decoder，postnorm、至少两个 heads、无 dropout、固定 seed 1729。
权重随机初始化，输出不代表训练后语言模型质量。

## 源码与执行

- `model.jac`：具体 primitive node、真实 `TensorEdge(port=...)`、构图帮助函数、
  `Analyze` 和 `Execute` walkers；模型架构与依赖关系在 Jac 中。
- `numerics.py`：架构无关的 metadata 校验、meta tensor 数值原语、初始化、
  输入检查和由拓扑/消费者计算的 liveness。没有 kind 字符串 dispatch。
- `reference.py`：独立直接 PyTorch 方程，用参数快照验证；执行图不会调用它。
- `validation.py` / `validate.jac`：数值差分、真实图变更、非法图和生命周期检查。

从仓库根目录运行，使用安装了当前 Jac 源码及 PyTorch 的 Python：

```bash
python -m jaclang run --backend python jac/examples/transformer_dataflow/demo.jac
python -m jaclang run --backend python jac/examples/transformer_dataflow/validate.jac --device cpu
```

本轮环境原 `.venv` 已不存在，现有 Python 3.12 没有 torch，因此使用独立临时环境，
不修改旧示例：

```bash
python -m venv --system-site-packages /tmp/jac-dataflow-venv
/tmp/jac-dataflow-venv/bin/python -m pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cu128
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_dataflow/demo.jac
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_dataflow/validate.jac --device cpu
```

GPU 仅在协调释放、确认无其他计算进程后运行；不进行本任务之外的性能实验：

```bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
XDG_CACHE_HOME=/tmp/jac-dataflow-cache /tmp/jac-dataflow-venv/bin/python -m jaclang run --backend python jac/examples/transformer_dataflow/validate.jac --device cuda:0
```

## Primitive 范围与端口

各类 node 通过多态 `ports()` / `infer()` / `evaluate()` 明确行为；共同基类只保存
调度状态。`Binary`、`Unary` 是抽象共享校验层，不在图中实例化。

| 类型 | 输入端口 | 属性/作用 |
|---|---|---|
| Input | 无 | source / target，推理入口 tensor |
| Parameter | 无 | `value` 持有该参数 tensor，具名 node；仅此类拥有训练参数 |
| Constant | 无 | 持久不训练 tensor，如 scale、epsilon、位置表 |
| Gather | table, indices | axis；rank-one int64 index_select |
| MatMul | a, b | 同 dtype/device，rank >= 2 的矩阵/批次 matmul |
| Add / Multiply / Subtract | a, b | 同 floating dtype/device，广播检查 |
| Square / Rsqrt / ReLU | x | float32/float64 |
| ReduceMean | x | axis、keepdim |
| Reshape | x | dimensions，允许一个 -1 |
| Transpose | x | dim0、dim1 |
| Contiguous | x | 显式连续化 |
| MaskedFill | x, mask | bool mask 可广播到 x；fill=-inf |
| Softmax | x | axis；primitive，不展开为指数和归约 |
| Arange | ref | 从 ref 指定 axis 的长度产生 int64 位置索引 |
| Full | ref | axes 引用 ref shape 构造尺寸、dtype、fill |
| Triu | x | diagonal=1 构造 causal 上三角 mask |

`linear`、`attention`、`norm`、`feed_forward`、`embedding` 仅在 build 时创建
primitive nodes/edges。运行时没有 Linear、Attention、FFN、AddNorm 黑盒节点。
每个 affine 的 weight/bias 都是独立 Parameter node；每个 norm 的 gamma/beta
也是 Parameter node。参数快照按实际 Parameter 类型读取，不读通用 weights dict。

位置编码是固定的正弦位置表 Constant，Arange/Gather/Add 在真实图中取出并加入
embedding；默认容量 256，明确拒绝超长输入。CPU float64 构造常量后转到所选
precision/device。位置表不是训练参数。causal mask 由 Full -> Triu -> MaskedFill
展开；Q/K/V 是 Parameter -> MatMul -> Add -> Reshape -> Transpose；随后
Q @ K^T -> Multiply(scale) -> MaskedFill（decoder）-> Softmax -> @ V ->
Transpose -> Contiguous -> Reshape -> 输出 MatMul/Add。

每个 postnorm 在图中展开为 residual Add -> ReduceMean -> Subtract -> Square ->
ReduceMean -> Add(epsilon) -> Rsqrt -> Multiply(center) -> Multiply(gamma) ->
Add(beta)。enc_norm2 分别连到 cross-attention K/V 投影的 `a` 端口，是真实 producer
依赖，不是运行时从某个固定 encoder 全局变量读取。

target 采用 shifted input：labels=[6,7,2] 对应输入 [BOS=1,6,7]，输出每个位置的
词表概率。teacher-forced forward 一次计算全部 target 位置；autoregressive
生成则每步用已生成前缀重新分析/执行，追加最后位置的 argmax。没有 KV cache。

## Metadata 分析、执行与失效

`Analyze` walker 首先从真实 TensorEdge 枚举输入生产者，拒绝未知端口、重复生产者、
缺端口或非法 roots。由无输入 Input/Parameter/Constant roots 出发，沿边传 metadata；
消费者所有端口 ready 后才 visit。顺序由图依赖产生，不是手写层列表。若未完成全部
节点则报告 cycle/unreachable。每类 infer 执行自身 primitive 的 metadata 规则；
matmul、reshape、gather、mean、transpose 使用 PyTorch meta tensors 推导 shape，
而不运行真实数值计算。广播用 broadcast_shapes，dtype/device/axis/mask 单独校验。
只支持具体整数 shape，不提供符号约束求解。

metadata 结果单独保存为 `Model.analysis` 的 input_specs/tensor_specs；成功后再生成
`Model.plan` 的 order、实际 edges、每端口生产者、consumer 列表和 liveness。
计划引用分析得到的 specs，执行仍单独进行。`Execute` walker 单独重置 inbox/output/done/queued，沿真实边传
resident tensor 引用，再以端口 readiness 触发 evaluate；不按 hardcoded pipeline
调用模块，也不把分析 order 当作张量 forward 管线。执行顺序与分析计划逐项核对，
每个实际输出 metadata 与分析结果核对。

分析与执行分别进行。指纹包括实际 edges/roots、具体类型、端口、操作属性和
Parameter/Constant metadata。修改边/axis/reshape 或参数 shape/dtype/device 后，
forward 拒绝旧计划并要求 `analyze()`。改变输入长度也明确要求重分析。相同 metadata
下的参数值修改不需要重分析，执行读取 Parameter 的当前 value。
`to()` 和 `add()` 会清空计划。完整 graph scan 检查失效有主机成本，没有性能优势声称。

最后使用位置由 walker 的实际拓扑顺序与所有 consumer 端口计算，包含同一 producer
到同一 consumer 不同端口的计数。执行在消费者使用后减少引用计数，最后使用时
清空 producer.output，并清空消费节点 inbox。Parameter/Constant.value 始终持久；
返回 probabilities 保留。capture 是显式诊断选项，刻意保留选定中间值；没有 capture
时只保留返回结果。验证逐步比较分析与实际 release/live_after。

logical bytes/peak 是 tensor 值的活跃性度量，view aliases 分别计数，不是 CUDA
allocator 峰值或严格 buffer reuse 分析；调用者输入和诊断 captures 的外部引用不
计入。没有 alias analysis、in-place 运算、autograd 或训练内存规划。

设备检查使用 metadata，不下载 tensor。全部参数/常量先放置到设备，边只传对象引用，
默认同一调用者 stream，不启用辅助 stream，也不逐节点同步。host token 列表在入口
上传；resident int64 tensor 的 ID 范围需调用者预验证，避免数据依赖的同步检查。
验证/展示会在 forward 外读取数值。

## 与 FX/export 的比较边界

该图属于 tensor operation 数据流层次，可与 FX graph / export ATen graph 的
producer-consumer 与 metadata 分析比较，不应与纯模块关系图相比而夸大细粒度。
本地只读参考 `/home/baichuan/pytorch/torch/fx/passes/shape_prop.py`：ShapeProp
逐节点执行/记录 shape 和 dtype，可结合 fake mode。参考
`/home/baichuan/pytorch/torch/export/__init__.py`：export 输出捕获的 tensor graph
及有效性约束。本示例是手工通过 Jac 构图帮助函数建立图，不从 Python 程序 tracing；
只有固定 shape 的检查，不等价于 export 的符号 shape constraints、完整 ATen
覆盖或编译器生态。它没有声称比 Dynamo/Inductor 更快或比 FX 更有表达力。
实际价值是将操作与参数作为 Jac 实体、可检查并修改真实边，并明确展示分析和
生命周期在 Jac traversal 上如何工作。这个价值要通过图修改与拒绝非法图的实验
验证，不能仅因为存在图就当作研究贡献。

## 验证与产物

`demo.jac` 导出实际 `graph.dot` 和 `analysis.json`。每组验证额外导出原图/重连图
及其实际分析；`results/validation_cpu.json`、`validation_cuda_0.json` 保存结果。
包括独立 reference 的关键中间值（全部投影、scores/mask/attention、完整 norm 等）、
概率归一化、future-token isolation、encoder 影响、不同长度、重复推理、参数修改、
真实 skip 重连/恢复、插入 Constant/Multiply 修改 logits、memory 缺边，以及 matmul/broadcast/dtype/device/axis/reshape/
cycle/duplicate/unknown-port/mask/index 错误拒绝和分析失效。

实际完成结果（2026-10-07）：CPU demo 和 CPU/CUDA validate 均退出 0。
GPU 经协调释放并确认无其他计算进程后验证，设备 RTX 3090，driver 580.65.06，
PyTorch 2.8.0+cu128 / CUDA 12.8，Python 3.12.11，CPU math threads=1、TF32=false。
CUDA 验证完成后已释放 GPU，未运行性能 benchmark/profiling。

小配置 d=8/h=2/FF=16/V=13、source=4/target=3；中配置 d=64/h=4/FF=128/V=127、
source=32/target=24；均 batch=1，每组验证 float64 与 float32。
各配置原图均为 **200 个真实操作节点、224 条 TensorEdge、46 个 Parameter**。
独立 reference 检查 **137 个中间结果**，包含全部 Q/K/V/输出投影、attention scores/
mask/maps/context、五个完整 postnorm 和 FFN；全部 200 节点 metadata 与执行输出
逐一核对，224 条边的 tensor 对象身份传递、每步 release/live_after 与分析一致。

| config / dtype | CPU vs independent reference max abs | CUDA vs independent reference max abs | CUDA graph vs CPU equations max abs |
|---|---:|---:|---:|
| small / float64 | 0 | 0 | 4.4409e-15 |
| small / float32 | 2.8610e-6 | 1.1921e-6 | 1.9073e-6 |
| medium / float64 | 0 | 1.2434e-14 | 1.4211e-14 |
| medium / float32 | 6.6757e-6 | 8.5831e-6 | 6.6757e-6 |

float32 不要求 bitwise 相同：Jac 的位置表由 CPU float64 计算后转换，独立 reference
按目标 dtype/device 重新计算位置编码，两者还可能使用不同设备的数学近似。
差分容差为 float64 atol=2e-11/rtol=2e-10、float32 atol=3e-5/rtol=3e-4。
MaskedFill 的预期 -inf 单独允许，其余被检查中间值有限，概率有限且每行归一化。

真实 residual skip 重连在 CPU float64 小/中配置的概率最大变化分别为
0.156913 / 0.050384，与对应独立方程一致；插入 Constant/Multiply 缩放 logits
使图增加到 202 节点/226 边，变化分别为 0.083251 / 0.047602，也与独立方程一致。
同一个 Execute walker 不改流程。恢复原边后恢复原输出。长度 2/1、1/5、5/2、
未来 token 隔离、encoder memory 影响、十种参数修改、旧结果不被后续调用污染、
resident forward 无 scalar extraction/下载/显式 synchronize 审计均通过。
缺 memory 输入与 11 种额外非法 graph/metadata 情况全部被分析拒绝；相关报错保留
在 validation JSON。shape 保持的 axis 修改也会使原计划失效。

原图活跃性逻辑峰值为 small float64 2057 bytes、small float32 1033 bytes、
medium float64 148032 bytes、medium float32 74304 bytes；峰值活跃 tensor 值数量 10。
这些数字排除持久 Parameter/Constant，也不是实际显存占用，不能用来声称分配器
节省或更快执行。`execution.json` 保存默认 CPU demo 的实际完整 trace、边传递、
对象身份和最后使用释放过程，便于与 `analysis.json` 的计划直接核对。

当前只完成正确性和可检验分析；没有 Dynamo/FX/export 性能或优化比较，没有
融合、符号 shape、训练、padding/batched输入、KV cache 或 in-place/alias 分析。
对 FX/export 的比较限于操作图与 metadata 的层次，不声称替代其能力或获得加速。



实际图的可读局部视图由导出的分析 JSON 提取，保留真实边/输入端口/metadata：

```bash
/tmp/jac-dataflow-venv/bin/python jac/examples/transformer_dataflow/extract_views.py jac/examples/transformer_dataflow/analysis.json
dot -Tsvg jac/examples/transformer_dataflow/attention.dot -o jac/examples/transformer_dataflow/attention.svg
dot -Tsvg jac/examples/transformer_dataflow/norm.dot -o jac/examples/transformer_dataflow/norm.svg
```

`attention.dot/svg` 展示 decoder Q/K/V -> score -> mask -> softmax -> V 的真实路径；
`norm.dot/svg` 展示 enc_norm1 的完整展开。它们来自实际构图的分析，不是手画结构。
`preservation.json` 记录旧示例 80 个源码/结果/文档文件的 SHA-256，用于最终不变检查。


旧示例保持检查（只读）：

```bash
/tmp/jac-dataflow-venv/bin/python jac/examples/transformer_dataflow/verify_preservation.py
```

本轮最终检查：80 个文件的 SHA-256 全部一致；源码仅新增本目录，不改共享
compiler/runtime、packer 或旧 Transformer，未 commit/push。

缓存说明：本轮复用了 packer 已生成的兼容 stub catalog 的**独立副本**，未写其
缓存。key 包含 Python 主次版本、平台、类型系统摘要；不匹配时 Jac 会重新构建。
普通新环境可直接按上面的 XDG_CACHE_HOME 命令自行初始化；首次初始化可能较慢。
