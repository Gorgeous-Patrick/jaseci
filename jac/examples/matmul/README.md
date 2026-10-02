# Jac matmul 实现集

这些实现用于比较算法、数据布局和 OSP 表达方式，统一在 **Jac 的 Python CPU 后端**运行。所有计算代码都在 `.jac` 文件中；库版本通过 Jac 的 Python 互操作调用 CPU 实现。

在仓库根目录运行全部实现：

```bash
jac run -b python jac/examples/matmul/validate.jac
```

输出每种实现的验证结果，最后打印：

```text
Known result: [[58.0, 64.0], [139.0, 154.0]]
PASS: 40 CPU implementations, 19 cases each, all outputs agree
```

本环境安装了 NumPy 和 SciPy，所以共有 40 种。只使用 Jac 和 Python 标准库时有 32 种：

```bash
jac run -b python jac/examples/matmul/validate.jac --no-libraries
```

保存可复查的 JSON 结果：

```bash
jac run -b python jac/examples/matmul/validate.jac --json /tmp/matmul-results.json
```

## 稠密、递归及稀疏算法

所有函数接受 `a, b` 两个二维列表，返回新的二维结果列表，输入保持不变。非空矩形输入必须满足 A 的列数等于 B 的行数。实现面向有限实数；验证使用 float64 范围内的数据，不保证所有极端数值、NaN、无穷或溢出情形有相同行为。

| 文件 | 实现 | 核心变化 |
|---|---|---|
| `dense.jac` | `loop_ijk`, `loop_ikj`, `loop_jik`, `loop_jki`, `loop_kij`, `loop_kji` | 六种三重循环顺序；`kij` 可看作逐 k 的外积累加 |
| `dense.jac` | `transposed_dot` | 先转置 B，再执行连续行点积 |
| `dense.jac` | `comprehension` | 列表推导式与 `sum` |
| `dense.jac` | `flat_buffers` | 行优先一维 `array('d')`，显式索引 |
| `dense.jac` | `blocked` | M/N/K 分块，处理尾部不完整块 |
| `dense.jac` | `packed_tiles` | 每阶段把 A/B 子块打包为连续缓冲区 |
| `dense.jac` | `register_2x2` | 四个局部累加器复用输入，计算 2×2 输出 |
| `dense.jac` | `split_k` | 分段计算 K，再归约部分结果；本实现串行执行各段 |
| `dense.jac` | `pairwise` | 二叉树式求和 |
| `dense.jac` | `compensated` | Kahan 补偿求和 |
| `dense.jac` | `accurate_sum` | 使用标准库 `math.fsum` |
| `dense.jac` | `winograd_pairs` | Winograd 成对乘积公式，单独处理奇数 K |
| `dense.jac` | `threaded_rows` | 线程池独立计算各输出行 |
| `dense.jac` | `overloaded_operator` | Jac `Matrix` 对象实现 `__matmul__`，使用 `a @ b` |
| `recursive.jac` | `recursive_blocks` | 递归拆分最大维度，使用索引视图而不复制子矩阵 |
| `recursive.jac` | `strassen` | 七次子矩阵乘法；补零为二次幂方阵后裁剪 |
| `recursive.jac` | `strassen_winograd` | Strassen 的 Winograd 变体，减少矩阵加减 |
| `sparse.jac` | `csr_dense` | 将 A 打包为 CSR，与稠密 B 相乘 |
| `sparse.jac` | `csr_csc_merge` | A 的稀疏行与 B 的稀疏列按 K 索引双指针合并 |
| `sparse.jac` | `coo_scatter` | A 的 COO 项与 B 的稀疏行进行乘积散射 |

`blocked`、`packed_tiles`、`output_tile_tasks` 的第三个参数是 tile 大小，`split_k` 是 K 分段长度，`strassen` 和 `strassen_winograd` 是递归叶子 cutoff；都要求正整数。验证另外测试 1、2、3、8、32，共 90 次配置检查，并检查非正参数会被拒绝。

这里的分块和局部累加器表达的是计算结构，不意味着 CPU 后端自动产生 SIMD，也不意味着一个 walker 自动成为协作的 CUDA 线程块。线程池版本也不保证加速；Python GIL 和任务开销仍需考虑。Strassen 的统一方阵 padding 对细长矩阵可能代价很高，这里用于完整展示算法。

## 七种 node / edge / walker 表达

设 A 为 M×K，B 为 K×N。代码全部位于 `graphs.jac`。

| 实现 | 节点 | 边 | walker / 结果 |
|---|---|---|---|
| `product_chains` | MNK 个乘数对节点 | MN(K−1) 条链边 | MN 个 walker，每个算一个输出点积 |
| `dual_cursors` | MK+KN 个共享标量节点 | A 行链和 B 列链 | MN 个 walker；主位置访问 A，第二游标访问 B |
| `row_nodes` | M 个含行数组的节点 | 无 | 每个 walker 算一行；共享转置后的 B |
| `output_cell_tasks` | MN 个输出坐标任务节点 | 无 | walker 用共享矩阵数组和 K 循环计算一个输出 |
| `output_tile_tasks` | ceil(M/T)×ceil(N/T) 个任务节点 | 无 | walker 用共享数组计算一个输出块 |
| `bipartite_join` | MK+KN 个标量节点 | MKN 条同 K 连接边，加上 A 行链 | M 个 walker；沿 A 行遍历并通过邻居查询累加整行 |
| `edge_payloads` | MN 个输出任务节点和 K 个索引节点 | MNK 条保存乘数对的边 | walker 查询边属性并归约 |

这些图都在 CPU 上构造，构图成本包含在一次函数调用中。双游标方案复用原始标量节点；二部图方案复用节点，但仍需大量边；乘数对节点和边属性方案则显式复制乘法输入。这里保留这些方案，方便对比各自的表达力与准备成本。

只有乘数对链式能力的结构符合当前 GPU walker 子集；其独立 GPU 版本是 `../gpu/matmul.jac`。其他形式在本任务中只验证 CPU 执行。节点引用状态、数组字段、动态索引、嵌套查询和边属性读取都不能由当前 GPU 后端完整执行。

## CPU 库实现

`libraries.jac` 在依赖已安装时加入这些路径：

- NumPy `@`、`matmul`、`dot`、`einsum`、`tensordot`。
- NumPy 广播乘积后沿 K 求和；会创建 M×K×N 中间数组。
- SciPy BLAS `dgemm`。
- SciPy CSR 稀疏矩阵乘法，最后转为稠密结果。

这些属于不同接口/表达路径，不是八种独立的底层数值算法。没有安装依赖时会明确缩减验证清单，标准库版本仍全部运行。

## 一致性验证

`validate.jac` 使用固定 seed，覆盖 19 组输入：已知答案、单元素、零矩阵、单位矩阵、符号零、抵消求和、非方阵、奇数维度、不同分块边界、随机小整数、随机浮点数、稀疏输入和对角矩阵。

- 13 组小整数数据使用 Python 整数计算独立参考，要求结果**精确相等**。
- 6 组浮点数据使用 `Decimal.from_float` 和 100 位十进制运算建立独立参考，要求 `rel_tol=1e-10`、`abs_tol=1e-10`。
- 每种实现另检查 6 组非法形状、输入没有被修改，以及已知的 2×3 乘 3×2 答案。
- JSON 保存每种实现的最大绝对误差、通过样例数、依赖版本、seed 和 Jac 源码哈希。

不同求和顺序通常不会给出逐位相同的浮点结果。Strassen、Winograd 等还会产生额外的加减；这些检查仅证明列出的数据与容差下输出一致，并不是任意输入的数值稳定性证明。记录的 elapsed 时间包含各实现的转换、打包、构图等成本，仅供定位开销，不是受控性能基准。

仓库回归测试：

```bash
jac test jac/tests/runtimelib/test_matmul_variants.jac
```

## 参考资料

- [Strassen 与 Winograd 变体的公式，Kouya 2014，式 (5)–(8)](https://arxiv.org/abs/1410.1599)。
- [NumPy dot / matmul 接口](https://numpy.org/doc/stable/reference/generated/numpy.dot.html)。
- [SciPy 稀疏数组与矩阵运算](https://docs.scipy.org/doc/scipy/reference/sparse.html)。

复杂的 GPU tile 协作、shared memory、Tensor Core 以及调度优化需要后端能力扩展；本实现集先提供可执行的算法与 OSP 表达，供后续选择。
