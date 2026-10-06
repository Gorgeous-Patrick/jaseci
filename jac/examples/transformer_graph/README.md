# Typed Jac Graph CPU Transformer

完整的一层编码器、一层解码器 Transformer：`d_model=8`、双头 attention（每头 4 维）、
`d_ff=16`、词表大小 13、随机种子 1729。采用原始架构的 post-norm、正弦位置编码、
ReLU FFN，CPU 推理不使用 dropout。仅使用现有 Jac 和 Python 标准库，无新增依赖。

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
