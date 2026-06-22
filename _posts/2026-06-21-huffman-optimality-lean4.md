---
title: "形式化证明 Huffman 最优性：我们的 splitLeaf / 交换论证方法"
date: 2026-06-21
categories:
  - formal-verification
  - algorithms
tags:
  - Lean4
  - Huffman
  - greedy
  - optimality
  - proof-methodology
excerpt: "整理我们在 Lean 4 中形式化 Huffman 编码最优性的方法：把一次贪心合并反过来写成 splitLeaf，用交换论证证明这个逆操作保持最优性，再用 splitLeaf 与 huffman 的交换律把归纳假设传回原始森林。"
---

> 本文整理 `CfProofs/Greedy/Huffman/` 中 V1 证明的结构，目标是为数学/算法博客提供一份可读的“方法地图”。V1 的 8 个文件共 3553 行 Lean 4（其中 `Optimal.lean` 约 1700 行），核心定理是 `optimum_huffman`。
>
> 我们的证明方法主要参考了 Jasmin Christian Blanchette 在 Isabelle/HOL 中对 Huffman 算法“课本证明”的形式化（Journal of Automated Reasoning, 2009），尤其是把一次贪心合并反过来写成 `splitLeaf` 的核心思路。

---

## 1. 问题与树模型

我们把前缀码树建模为二叉树 `HuffTree`：

```lean
inductive HuffTree
  | htLeaf (symbol freq : ℕ)
  | htInner (left right : HuffTree)
```

- 每个叶子存一个符号和正频率；
- 内部节点 `htInner l r` 代表把两棵子树合并成一个码字集合；
- `consistent t` 要求任意内部节点的左右子树字母表不交，从而保证它是合法前缀码。

一棵树的代价即编码的期望总 bit 数，也就是**加权外部路径长度**：

```lean
def cost : HuffTree → ℕ
  | htLeaf _ _ => 0
  | htInner l r => cost l + cost r + rootFreq l + rootFreq r
```

其中 `rootFreq t` 是 `t` 中所有叶子频率之和。该递归式等价于

\\[
\\operatorname{cost}(t)=\\sum_{s\\in\\operatorname{alphabet}(t)} \\operatorname{freqOf}(s,t)\\cdot \\operatorname{depthOf}(s,t).
\\]

Huffman 算法在森林上反复合并当前根频率最小的两棵树：

```lean
def insortTree (t : HuffTree) : List HuffTree → List HuffTree
  | [] => [t]
  | u :: us => if rootFreq t ≤ rootFreq u then t :: u :: us else u :: insortTree t us

def huffman : List HuffTree → HuffTree
  | [] => htLeaf 0 0
  | [t] => t
  | t₁ :: t₂ :: rest => huffman (insortTree (htInner t₁ t₂) rest)
```

`insortTree` 按 `rootFreq` 升序插入，保证森林始终有序。

---

## 2. 森林不变式

我们把所有前置条件写成对森林 `ts : List HuffTree` 的五个假设：

```lean
def forest_sorted : List HuffTree → Prop
  | [] => True | [_] => True
  | t₁ :: t₂ :: ts => rootFreq t₁ ≤ rootFreq t₂ ∧ forest_sorted (t₂ :: ts)

def forest_consistent : List HuffTree → Prop
  | [] => True | [t] => consistent t
  | t :: ts => consistent t ∧ forest_consistent ts ∧ (∀ u ∈ ts, Disjoint (alphabet t) (alphabet u))
```

再加上“每棵树都是叶子”和“所有叶子频率为正”。这五个条件构成 Huffman 最优性定理的全部假设：

```lean
theorem optimum_huffman (ts : List HuffTree)
    (h_sorted : forest_sorted ts)
    (h_cons : forest_consistent ts)
    (h_all_leaves : ∀ t ∈ ts, height t = 0)
    (h_pos : ∀ t ∈ ts, rootFreq t > 0)
    (h_nonempty : ts ≠ []) :
    optimum (huffman ts)
```

最优性 `optimum t` 要求：

```lean
def optimum (t : HuffTree) : Prop :=
  consistent t
  ∧ (∀ s ∈ alphabet t, freqOf s t > 0)
  ∧ ∀ u, consistent u → sameFreqs t u → cost t ≤ cost u
```

即 `t` 在所有与它频率分布相同且一致的前缀码树中代价最小。

---

## 3. 证明概览：把一次贪心步“倒过来”

标准 Huffman 归纳证明通常是：

1. 取两个最小频率叶子 `sa(fa), sb(fb)`；
2. 把它们合并成 `sa(fa+fb)`；
3. 对更短的森林用归纳假设；
4. 再把合并的叶子“展开”回 `sa(fa), sb(fb)`，并证明最优性保持。

我们在形式化中把第 4 步显式建模为树操作 `splitLeaf`：

```lean
def splitLeaf (t : HuffTree) (z a b fa fb : ℕ) : HuffTree :=
  match t with
  | htLeaf sym f => if sym = z then htInner (htLeaf a fa) (htLeaf b fb) else htLeaf sym f
  | htInner l r => htInner (splitLeaf l z a b fa fb) (splitLeaf r z a b fa fb)
```

`splitLeaf t z z b fa fb` 把树 `t` 中符号 `z` 的叶子替换为内部节点 `htInner (htLeaf z fa) (htLeaf b fb)`。这正是“合并”的逆操作。

<figure style="text-align:center;">
  <img src="/images/huffman-splitleaf-inverse.png" alt="splitLeaf 是 Huffman 合并步的逆操作" style="max-width: 600px; width: 100%;">
  <figcaption><b>图 1：</b>splitLeaf 把 reduced tree 中频率为 fa+fb 的合并叶子重新分裂为一对同胞叶子，从而把归纳假设传回原森林。</figcaption>
</figure>

于是整个证明可以概括为两条强归纳：

| 层次 | 归纳对象 | 作用 |
|---|---|---|
| **外层** | 森林长度 `ts.length` | 把 Huffman 算法的一次合并步规约到 `splitLeaf` |
| **内层** | 竞争对手 `u` 的节点数 `nodeCount u` | 证明 `splitLeaf` 保持最优性 |

---

## 4. 外层归纳：从森林到 reduced forest

对 `ts.length` 做强归纳。

### 4.1 基例

- **长度 1**：`ts = [htLeaf s f]`，直接用 `optimum_leaf`。

  ```lean
  lemma optimum_leaf (s f : ℕ) (h_f_pos : f > 0) : optimum (htLeaf s f) := by
    refine ⟨by simp [consistent], ?_, ?_⟩
    · simp [alphabet, freqOf, h_f_pos]
    · intro u _ h_sameFreqs
      simpa [cost] using cost_nonneg u
  ```

- **长度 2**：`ts = [htLeaf sa fa, htLeaf sb fb]`。由 `forest_consistent` 得 `sa ≠ sb`，再用 `optimum_two_distinct_leaves`。

  ```lean
  lemma optimum_two_distinct_leaves (sa fa sb fb : ℕ)
      (h_ne : sa ≠ sb) (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) :
      optimum (htInner (htLeaf sa fa) (htLeaf sb fb)) := by
    -- 先验证两个符号的频率为正，再说明任何 competitor 的 cost 都不更低
    ...
  ```

### 4.2 归纳步

设 `ts = htLeaf sa fa :: htLeaf sb fb :: tc :: rest`（长度 ≥ 3）。由于 `forest_sorted`，前两个正是全局频率最小的叶子。

构造 **reduced forest**：

```lean
let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)
```

`Preservation.lean` 负责验证 `reduced` 仍然满足所有不变式，并且长度严格减少。关键引理包括：

- `forest_sorted_insortTree_of_sorted`：插入保持有序；
- `forest_consistent_insortTree_fresh`：因为 `sa` 原本不出现在 `tc :: rest` 中，插入 `htLeaf sa (fa+fb)` 保持不交性；
- `insortTree_length`：长度增加 1，而原长度减 2，故 `reduced.length = ts.length - 1`。

下面是这一步的 Lean 骨架（不变式的具体证明已省略）：

```lean
let reduced := insortTree (htLeaf sa (fa + fb)) (tc :: rest)

have h_reduced_nonempty : reduced ≠ [] := by
  rw [← List.length_pos_iff_ne_nil, insortTree_length]
  omega
have h_reduced_sorted : forest_sorted reduced := ...
have h_reduced_cons : forest_consistent reduced := ...
have h_reduced_leaves : ∀ t ∈ reduced, height t = 0 := ...
have h_reduced_pos : ∀ t ∈ reduced, rootFreq t > 0 := ...
have h_len : reduced.length < n := by
  rw [← hlen]
  simp [reduced, insortTree_length]

have h_opt_reduced : optimum (huffman reduced) :=
  ih reduced.length h_len reduced h_reduced_sorted h_reduced_cons
    h_reduced_leaves h_reduced_pos h_reduced_nonempty rfl
```

于是得到 `optimum (huffman reduced)`。接下来需要把 `huffman reduced` 中的合并叶子重新分裂，并让它等于原森林的 Huffman 输出。

---

## 5. 内层核心：`optimum_splitLeaf`

这是整个证明的“发动机”。定理陈述如下：

```lean
theorem optimum_splitLeaf (t : HuffTree) (z b fa fb : ℕ)
    (h_opt : optimum t)
    (h_z_in : z ∈ alphabet t)
    (hb_not_mem : b ∉ alphabet t)
    (hz_ne_b : z ≠ b)
    (h_fa_pos : fa > 0) (h_fb_pos : fb > 0) (h_fa_le_fb : fa ≤ fb)
    (h_fa_min : ∀ s ∈ alphabet t, fa ≤ freqOf s t)
    (h_fb_min : ∀ s ∈ alphabet t, s ≠ z → fb ≤ freqOf s t)
    (h_sum : freqOf z t = fa + fb) :
    optimum (splitLeaf t z z b fa fb)
```

含义：已知 `t` 最优，把 `t` 中频率为 `fa+fb` 的符号 `z` 分裂成同胞叶子 `z(fa)` 与 `b(fb)`，新树仍最优。条件正是 Huffman 一次合并所满足的。

### 5.1 成本关系

`splitLeaf` 的成本增加量恰好是 `fa + fb`：

```lean
theorem cost_splitLeaf_eq (t : HuffTree) (z a b fa fb : ℕ) (h_cons : consistent t)
    (h_z_in : z ∈ alphabet t) (h_sum : freqOf z t = fa + fb) :
    cost (splitLeaf t z a b fa fb) = cost t + fa + fb := by
  -- 先证 splitLeaf 保持 rootFreq，再对树结构做归纳
  ...
```

因此要证明分裂后的树最优，只需证明：对任意竞争对手 `u`，

\\[
\\operatorname{cost}(t)+fa+fb \\le \\operatorname{cost}(u).
\\]

### 5.2 交换论证（exchange argument）

核心工具是 `cost_exchangeLeaf_le`：

```lean
lemma cost_exchangeLeaf_le (t : HuffTree) (a x : ℕ) (h_cons : consistent t)
    (ha_in : a ∈ alphabet t) (hx_in : x ∈ alphabet t) (h_ne : a ≠ x)
    (h_freq : freqOf a t ≤ freqOf x t)
    (h_depth : (depthOf a t).getD 0 ≤ (depthOf x t).getD 0) :
    (cost (swapFreqs a x (swapLeaves a x t)) : ℤ) ≤ (cost t : ℤ)
```

组合操作 `swapFreqs a x (swapLeaves a x t)` 先交换 `a` 与 `x` 的**位置**，再交换它们的**频率标签**。这样既保留了树的形状，又把 `a` 的频率放到了原来 `x` 的深度。当 `a` 的频率更低且深度更浅时，这次“交换”不会增加成本。这个不等式是 Huffman 贪心最优性的经典解析基础。

### 5.3 deepest sibling pair

为了在竞争对手 `u` 中找到合适的位置应用交换引理，我们递归地取 `u` 中**最深的一对同胞叶子**：

```lean
def deepestSiblingPair (t : HuffTree) : ℕ × ℕ := ...
```

相关引理保证：

- `deepestSiblingPair_mem1 / mem2`：这对符号确实在字母表中；
- `deepestSiblingPair_depth`：它们的深度都等于树高；
- `deepestSiblingPair_areSiblings`：它们确实是同胞。

因为这对叶子在最深处，任何其他符号的深度都不超过它们，这满足了 `cost_exchangeLeaf_le` 的前提。

### 5.4 合并对手中的同胞：`mergePair`

一旦通过有限次交换把 `z, b` 移到同胞位置，就可以用 `mergePair` 把它们合并回单个叶子 `z(fa+fb)`，得到一棵更小的树 `v''`。

```lean
def mergePair (a b z fz : ℕ) : HuffTree → HuffTree
  | htInner (htLeaf x fx) (htLeaf y fy) =>
      if (x = a ∧ y = b) ∨ (x = b ∧ y = a) then htLeaf z fz
      else htInner (htLeaf x fx) (htLeaf y fy)
  | htInner l r => htInner (mergePair a b z fz l) (mergePair a b z fz r)
  | t => t
```

关键引理：

- `cost_mergePair_of_areSiblings`：合并后成本减少 `fa + fb`，即

  ```lean
  lemma cost_mergePair_of_areSiblings (t : HuffTree) (a b z fa fb : ℕ)
      (h_sib : areSiblings a b t) (h_cons : consistent t) (h_ne : a ≠ b)
      (h_fa : freqOf a t = fa) (h_fb : freqOf b t = fb) (h_fz : fz = fa + fb) :
      (cost (mergePair a b z fz t) : ℤ) = (cost t : ℤ) - (fa : ℤ) - (fb : ℤ) := by
    -- 对 areSiblings 归纳，直接计算同胞对合并前后的 cost
    ...
  ```

  用整数写出来就是
  \\[
  \\operatorname{cost}(v'') = \\operatorname{cost}(u) - fa - fb.
  \\]
- `nodeCount_mergePair_lt_of_areSiblings`：节点数严格减少，提供内层强归纳的测度。

于是原目标等价于
\\[
\\operatorname{cost}(t) \\le \\operatorname{cost}(v'').
\\]
而 `v''` 与 `t` 同频率分布且一致，故由 `t` 的最优性直接得到。

### 5.5 情形枚举

`optimum_splitLeaf` 的证明本质上是一场关于最深同胞对 `(x, y)` 与目标符号 `z, b` 相对关系的大规模分类讨论：

- `x = z`：
  - `y = b`：直接完成；
  - `y ≠ b`：交换 `b ↔ y`。
- `x = b`：
  - `y = z`：调整顺序得到 `z, b`；
  - `y ≠ z`：先交换 `z ↔ b`，再交换 `b ↔ y`。
- `x ∉ {z, b}`：
  - `y = z`：交换 `b ↔ x` 再交换 `z ↔ b`；
  - `y ≠ z`：交换 `z ↔ x` 得到 `z, y`，再处理 `y = b` 与否。

如果某个分支出现 `y` 不在原树 `t` 的字母表中（频率为 0），则可以直接剪枝并应用归纳假设。

---

## 6. 关键桥梁：`splitLeaf` 与 `huffman` 可交换

外层归纳得到 `optimum (huffman reduced)`，内层 `optimum_splitLeaf` 给出

```lean
optimum (splitLeaf (huffman reduced) sa sa sb fa fb)
```

最后需要把这个表达式变回 `huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest)`。

`Commutation.lean` 证明了 `splitLeaf` 可以拉到 `huffman` 外面：

```lean
theorem splitLeaf_huffman_commute (s1 s2 f1 f2 : ℕ) (rest : List HuffTree)
    (h_s1_notin_rest : ∀ t ∈ rest, s1 ∉ alphabet t) :
    splitLeaf (huffman (insortTree (htLeaf s1 (f1+f2)) rest)) s1 s1 s2 f1 f2
    = huffman (insortTree (htInner (htLeaf s1 f1) (htLeaf s2 f2)) rest)
```

右端再把 `htInner (htLeaf s1 f1) (htLeaf s2 f2)` 插入有序森林，正好等价于原森林 `htLeaf sa fa :: htLeaf sb fb :: tc :: rest` 的 Huffman 输出。

在 `Optimal.lean` 中，最后一步这样完成：

```lean
have h_opt_split : optimum (splitLeaf (huffman reduced) sa sa sb fa fb) := by
  apply optimum_splitLeaf (huffman reduced) sa sb fa fb
    h_opt_reduced h_a_in_reduced h_b_notin_reduced h_ne
    h_fa_pos h_fb_pos h_fa_le_fb h_fa_min h_fb_min h_freq_a

have h_eq : splitLeaf (huffman reduced) sa sa sb fa fb =
    huffman (htLeaf sa fa :: htLeaf sb fb :: tc :: rest) := by
  rw [show reduced = insortTree (htLeaf sa (fa + fb)) (tc :: rest) by rfl]
  rw [splitLeaf_huffman_commute sa sb fa fb (tc :: rest) h_a_notin_tc_rest]
  simp [huffman, insortTree, unite]

rw [h_eq] at h_opt_split
exact h_opt_split
```

这正是为什么我们要把“合并两个最小叶子”表述成 `splitLeaf` 的逆操作：它让归纳假设与算法步骤之间有了一个干净的代数恒等式。

---

## 7. 文件依赖与模块化

V1 证明按功能拆成 7 个文件，形成清晰的依赖链：

<figure style="text-align:center;">
  <img src="/images/huffman-v1-deps.png" alt="V1 文件依赖图" style="max-width: 720px; width: 100%;">
  <figcaption><b>图 2：</b>V1 证明的模块依赖关系。Base 提供数据类型和树手术；Swap* 与 MergeLemmas 提供交换/合并论证；Preservation 与 Commutation 把森林不变式与 Huffman 算法衔接；Optimal 组装出最终定理。</figcaption>
</figure>

| 文件 | 主要职责 |
|---|---|
| `Base.lean` | `HuffTree`、`cost`、`huffman`、`splitLeaf`、`swapLeaves`、`mergePair` 等定义与局部引理 |
| `SwapBasic.lean` | `swapLeaves` 保持 `rootFreq` 与 `cost` |
| `SwapFreqDepth.lean` | 交换后频率/深度的精确变化 |
| `SwapDisjoint.lean` | 交换保持一致性、`cost_exchangeLeaf_le` |
| `MergeLemmas.lean` | `mergePair` 的成本、节点数、一致性、频率分布 |
| `Preservation.lean` | 森林不变式在 `insortTree` / `huffman` 下的保持 |
| `Commutation.lean` | `splitLeaf_huffman_commute` |
| `Optimal.lean` | `optimum_splitLeaf` 与 `optimum_huffman` |

---

## 8. 形式化中的典型模式

在把上述数学论证写成 Lean 4 时，有几个反复出现的模式：

1. **形状操作 + 频率操作分离**
   - `swapLeaves` 只换符号位置；
   - `replaceFreq` / `swapFreqs` 只换频率标签；
   - 组合使用实现“把低频符号放到更深位置”。

2. **整数桥接**
   许多成本等式带减法（如 `cost_mergePair`），先在 `ℤ` 中处理，再用 `exact_mod_cast` / `push_cast` 转回 `ℕ`。

3. **强归纳测度**
   外层对森林长度，内层对竞争对手节点数。

4. **分类讨论**
   `optimum_splitLeaf` 的核心是符号相等与否的分支，配合 `by_cases`、`rcases` 与 `omega`。

5. **零频率符号剪枝**
   当竞争对手中出现不在原树字母表中的符号时，其频率为 0，可以直接 `mergePair` 合并，把问题归约到更小的实例。

---

## 9. 结论

V1 证明的核心方法论可以概括为一句话：

> **把 Huffman 的一次贪心合并反过来写成 `splitLeaf`，用交换论证证明这个逆操作保持最优性，再用 `splitLeaf` 与 `huffman` 的交换律把归纳假设传回原始森林。**

这一结构使得我们可以：

- 复用经典的“最深同胞对 + 交换”论证；
- 把算法的归纳步骤与树手术的代数性质解耦；
- 在形式化中按 Base → Swap → Merge → Preservation → Commutation → Optimal 的层次组织代码。

---

## 10. 参考文献

1. **Donald E. Knuth**, *The Art of Computer Programming, Vol. 1: Fundamental Algorithms*, 3rd ed., Addison-Wesley, 1997. 见 Section 2.3.4.5 对 Huffman 编码与最优性证明的经典论述。

2. **Thomas H. Cormen, Charles E. Leiserson, Ronald L. Rivest, Clifford Stein**, *Introduction to Algorithms*, 3rd ed., MIT Press, 2009. 见 Section 16.3 “Huffman Codes” 中的交换论证与贪心选择性质。

3. **Laurent Théry**, “Formalising Huffman’s Algorithm,” *Research Report*, Università degli Studi dell’Aquila, 2004. Coq 形式化，覆盖了前缀码与满二叉树之间的同构，规模较大。
   - HAL: <https://hal.archives-ouvertes.fr/hal-02149909>

4. **Jasmin Christian Blanchette**, “Proof Pearl: Mechanizing the Textbook Proof of Huffman’s Algorithm,” *Journal of Automated Reasoning*, Vol. 43, No. 1, 2009, pp. 1–18. Isabelle/HOL 形式化，Archive of Formal Proofs 条目。
   - PDF: <https://www.tcs.ifi.lmu.de/staff/jasmin-blanchette/jar2009-huffman.pdf>
   - AFP: <https://www.isa-afp.org/entries/Huffman.html>

5. 我们的 Lean 4 实现：`CfProofs/Greedy/Huffman/` 目录，见 `Optimal.lean` 中的 `optimum_huffman` 与 `optimum_splitLeaf`。

---

## 11. 附录 A：正确性检查清单

在把证明上传之前，我检查了以下几个容易出错的点：

| 检查项 | 说明 | 对应代码 |
|---|---|---|
| `cost` 与加权外部路径长度等价 | 递归定义 `cost (htInner l r) = cost l + cost r + rootFreq l + rootFreq r` 等价于 `Σ freq·depth`；`optimum` 定义要求在所有同频率分布的一致树中代价最小。 | `Base.lean` 中 `cost`、`optimum` |
| 基例确实最优 | `optimum_leaf` 与 `optimum_two_distinct_leaves` 直接验证。 | `Optimal.lean` 开头 |
| `splitLeaf` 的成本增量正确 | `cost_splitLeaf_eq` 严格给出 `cost t + fa + fb`。 | `Base.lean` |
| 外层归纳测度严格递减 | 原森林去掉两个最小叶子，插入一个合并叶子，长度从 `n` 变为 `n-1`。 | `insortTree_length` + `omega` |
| 合并后的叶子符号在剩余森林中新鲜 | 由 `forest_consistent` 推出 `sa ∉ rest`，这是 `forest_consistent_insortTree_fresh` 的前提。 | `Optimal.lean` 归纳步 |
| `optimum_splitLeaf` 的前提与 Huffman 合并步一致 | `fa ≤ fb`、`fa, fb` 是两个最小频率、`freqOf z t = fa + fb`、`b` 新鲜。 | `Optimal.lean` 归纳步 |
| 内层归纳测度严格递减 | `mergePair` 合并同胞对时节点数严格减少（`nodeCount_mergePair_lt_of_areSiblings`）。 | `MergeLemmas.lean` |
| 交换不等式方向正确 | `cost_exchangeLeaf_le` 展开后得到 `(freq_a - freq_x)(depth_x - depth_a) ≤ 0`，与“低频放更深不增 cost”一致。 | `SwapDisjoint.lean` |
| `splitLeaf` 与 `huffman` 可交换 | `splitLeaf_huffman_commute` 把“先 Huffman 再 split”与“先 split 再 Huffman”等同。 | `Commutation.lean` |
| 整个项目通过 `lake build` | 无错误、无未完成目标（`sorry`）。 | 见附录 B |

---

## 12. 附录 B：编译报告

我在本地完整编译了包含该证明的 Lean 4 项目，结果如下：

- **工具链**：`leanprover/lean4:v4.29.1`
- **Lake 版本**：`5.0.0-src+f72c35b (Lean version 4.29.1)`
- **编译命令**：`lake build`
- **编译结果**：`Build completed successfully (16524 jobs)`
- **核心目标**：`CfProofs.Greedy.Huffman.Optimal` 构建成功
- **状态**：无错误、无未完成目标

> 说明：构建过程中只有一些 `unusedSimpArgs` / `unusedVariables` 的 linter warning，这些是代码风格提示，不影响定理正确性。

---
## 13. 附录 C：源码索引

完整 V1 源码不再全文内联在博客里。正文保留关键证明片段，完整文件随个人主页发布在 `/files/huffman-optimality-lean4/`，也可以一次性下载：[huffman-optimality-lean4.zip](/files/huffman-optimality-lean4.zip)。

| 文件 | 行数 | 关键入口 |
|---|---:|---|
| [`Base.lean`](/files/huffman-optimality-lean4/Base.lean) | 437 | `HuffTree`、`cost`、`splitLeaf`、`cost_splitLeaf_eq` |
| [`SwapBasic.lean`](/files/huffman-optimality-lean4/SwapBasic.lean) | 29 | `rootFreq_swapLeaves_eq`、`cost_swapLeaves_eq` |
| [`SwapFreqDepth.lean`](/files/huffman-optimality-lean4/SwapFreqDepth.lean) | 93 | `freqOf_swapLeaves_*`、`depthOf_swapLeaves_*` |
| [`SwapDisjoint.lean`](/files/huffman-optimality-lean4/SwapDisjoint.lean) | 172 | `consistent_swapLeaves`、`cost_exchangeLeaf_le` |
| [`MergeLemmas.lean`](/files/huffman-optimality-lean4/MergeLemmas.lean) | 501 | `areSiblings`、`cost_mergePair_of_areSiblings`、`freqOf_mergePair_*` |
| [`Preservation.lean`](/files/huffman-optimality-lean4/Preservation.lean) | 452 | `freqOf_huffman_eq_forest_freq`、`consistent_huffman_of_consistent` |
| [`Commutation.lean`](/files/huffman-optimality-lean4/Commutation.lean) | 182 | `splitLeaf_huffman_commute_general`、`splitLeaf_huffman_commute` |
| [`Optimal.lean`](/files/huffman-optimality-lean4/Optimal.lean) | 1687 | `optimum_splitLeaf`、`optimum_huffman` |

推荐读法：先看正文第 5 节的 `optimum_splitLeaf`，再对照 `SwapDisjoint.lean` 的交换不等式和 `MergeLemmas.lean` 的合并成本公式；最后读 `Optimal.lean` 末尾的 `optimum_huffman`，它负责把 reduced forest 的归纳假设接回原始 Huffman 输出。
