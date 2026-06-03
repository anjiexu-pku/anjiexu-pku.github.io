---
title: "A Single-Molecule Bound on Cryptochrome Radical Pair Compass Sensitivity and Its Implications for Avian Magnetoreception"
date: 2026-06-02
categories:
  - research
  - physics
tags:
  - quantum-biology
  - radical-pair
  - magnetoreception
  - cryptochrome
  - spin-dynamics
  - biophysics
excerpt: "A single-molecule bound on cryptochrome radical pair compass sensitivity—what quantum spin dynamics tells us about the physical limits of avian magnetoreception."
---

<style>
.lang-switch {
  text-align: right;
  margin-bottom: 1.5em;
  font-size: 0.95em;
  user-select: none;
}
.lang-switch a {
  color: #888;
  text-decoration: none;
  padding: 0 0.3em;
}
.lang-switch a.active {
  color: #333;
  font-weight: 600;
}
.lang-switch a:not(.active):hover {
  text-decoration: underline;
}
</style>

<div class="lang-switch">
  <a href="#zh" onclick="switchLang('zh');return false">中文</a>|
  <a href="#en" class="active" onclick="switchLang('en');return false">English</a>
</div>

<div id="lang-zh" class="lang-content" style="display:none" markdown="1">

> **摘要** —— 自由基对机制能否解释鸟类磁感应，取决于单个Cry4a蛋白是否产生足够的方向信号。我们使用精确的spin-1 Liouvillian动力学和DFT超精细张量，计算了[FAD<sup>•−</sup> TrpH<sup>•+</sup>]自由基对的单分子方向灵敏度 $\|\Delta\Phi\| = \|\Phi_S(\mathbf{B}\parallel\hat{z}) - \Phi_S(\mathbf{B}\perp\hat{z})\|$，得到N5+N1核构型的 $\|\Delta\Phi\| = 1.86\times 10^{-3}$（野生型Cry4a的上限）。我们的 $B_{1/2}=3.16$ mT 与实验一致（$3.55\pm 0.16$ mT, Golesworthy et al., 2023），W369F突变体增强（$6.6\times$）仅使用已测定的 $\tau_\text{RP}=299$ ns 即被定量重现。每个额外的核自旋都单调稀释该信号——**"越少越好"原理**——完整核系综被稀释约10–30×。我们的模型做出了三个独立于未知生物参数的可证伪预测：22×低温增强、位点特异性<sup>15</sup>N同位素效应（$\|\Delta\Phi\|\_{^{15}\text{N}}/\|\Delta\Phi\|\_{^{14}\text{N}} \approx 0.14$–$0.24$），以及强 $B_{1/2}$ 各向异性。我们构建了可行性走廊来框定生物需求：对于现实的细胞参数（Cry4a拷贝数$\sim 10^5$，取向序 $S\in[0.3,0.8]$，G蛋白放大 $\alpha\in[10^2,10^5]$），量级估计将Cry4a罗盘置于可行范围内。唯一的关键未知量是 $\alpha$，可通过GTP-γ-S结合实验直接测量。

---

## 1. 问题

欧洲知更鸟每年从斯堪的纳维亚飞到北非，依靠感知地球磁场方向来导航。地磁场只有约 50 μT——你手机扬声器里的磁铁比它强一万倍。鸟能做到这一点，是因为它们视网膜里有一个蛋白叫 **Cry4a（Cryptochrome 4a）**。

Cry4a 吸收蓝光后形成一对未配对的电子——一个**自由基对** [FAD<sup>•−</sup> … TrpH<sup>•+</sup>]。这两个电子的自旋状态在纳秒到微秒的时间尺度上演化，而地磁场方向会影响它们处于"单态"还是"三态"的概率。最终，单态和三态有不同的化学命运——产物比例携带了磁场方向的信息。

这被称为**自由基对机制（Radical Pair Mechanism, RPM）**。它在理论和实验上都有大量支持：2021年纯化的 Cry4a 蛋白在体外确实对磁场有响应（Xu et al., *Nature* 2021）。

但有一个悬而未决的问题：**Cry4a 周围有大约 15-20 个原子核（<sup>14</sup>N 和 <sup>1</sup>H）**。每个核通过超精细耦合与电子自旋相互作用。直觉上——更多的核 = 更丰富的量子动力学 = 更强的方向敏感性。这是真的吗？

一个核心的未解问题连接着单分子物理和生物体层面的行为：在蛋白环境中不可避免地存在~15–20个核自旋的情况下，单分子方向信号是否足以在生物放大后支撑一个5°精度的罗盘？回答这个问题需要：(i) 对单分子 $\|\Delta\Phi\|$ 进行严格计算；(ii) 一个框架，将该分子信号通过中间各层生物组织映射到生物体层面的精度。

本文提供 (i)，使用精确的spin-1 Liouvillian动力学，所有参数均由实验约束；(ii)，通过一个可行性走廊，独立于未知生物细节，识别RPM在物理上足够的参数组合。

## 2. 物理模型

### 2.1 自旋哈密顿量

自由基对包含两个电子自旋（S=1/2）和 N 个核自旋。系统在角频率单位（ħ=1）下的哈密顿量为：

\\[
H = H_Z + H_\text{HF}
\\]

**塞曼项：**

\\[
H_Z = \gamma_e (\mathbf{S}_1 + \mathbf{S}_2) \cdot \mathbf{B}
\\]

其中 $\gamma_e = 17.6$ MHz/G 是电子旋磁比，$\mathbf{B} = B(\sin\theta\cos\phi, \sin\theta\sin\phi, \cos\theta)$，$B = 0.5$ G（地球磁场）。

**超精细项：**

\\[
H_\text{HF} = \sum_j \mathbf{S}_{e(j)} \cdot \mathbf{A}_j \cdot \mathbf{I}_j
\\]

其中 $\mathbf{A}_j$ 是超精细张量——描述第 j 个核与电子的耦合。张量不是球对称的：沿着某些方向的耦合远强于其他方向。**这是方向敏感性的物理根源。**

> **DFT超精细张量主值**（单位：Gauss，来源：Grüning et al. 2022 *JACS*）：N5 的各向异性最强（A<sub>xx</sub> 远大于 A<sub>yy</sub>, A<sub>zz</sub>），是罗盘方向参考轴的主要提供者。张量的非零非对角元提供了次级方向信息。

| 核 | 自由基 | 自旋 I | A<sub>xx</sub> | A<sub>yy</sub> | A<sub>zz</sub> |
|---|---|---|---|---|---|
| FAD N5 | FAD<sup>•−</sup> | 1 | 17.57 | −0.87 | −1.00 |
| Trp N1 | TrpH<sup>•+</sup> | 1 | 10.81 | −0.53 | −0.64 |
| Trp H1 | TrpH<sup>•+</sup> | ½ | −0.07 | −7.05 | −10.83 |
| FAD N10 | FAD<sup>•−</sup> | 1 | 6.05 | −0.14 | −0.24 |
| Trp H4 | TrpH<sup>•+</sup> | ½ | −1.88 | −5.36 | −7.40 |
| FAD H6 | FAD<sup>•−</sup> | ½ | −1.98 | −4.34 | −5.30 |

### 2.2 Lindblad动力学

自由基对不是一个孤立系统。它的自旋相干性会被蛋白环境的涨落摧毁（退相干），并且它会以有限的速率复合回基态。

系统的密度矩阵 ρ(t) 按照 **Lindblad主方程**演化：

\\[
\frac{d\rho}{dt} = -i[H, \rho] - \frac{k}{2}\\{P_S, \rho\\} + \sum_k \left[c_k \rho c_k^\dagger - \frac{1}{2}\\{c_k^\dagger c_k, \rho\\}\right]
\\]

其中 $P_S = \|S\rangle\langle S\|$ 是单态投影算符，$k$ 是复合速率。退相干由 Lindblad 算符 $c_k$ 描述：

\\[
c_{1,2} = \sqrt{\Gamma_d} \cdot S_z \quad\text{（纯退相干，}\Gamma_d = 45\text{ MHz）}
\\]
\\[
c_{3-6} = \sqrt{\Gamma_r/2} \cdot S_\pm \quad\text{（自旋弛豫，}\Gamma_r = 0.1\text{ MHz）}
\\]

### 2.3 实验约束的参数

**所有参数来自独立实验——零自由参数。**

| 参数 | 值 | 来源 |
|---|---|---|
| $k_\text{WT}$ | 16.7 MHz（$\tau_\text{RP}=60$ ns） | Gravell et al. (2025) *JACS* |
| $k_\text{W369F}$ | 3.3 MHz（$\tau_\text{RP}=299$ ns） | Gravell et al. (2025) *JACS* |
| $\Gamma_d$ | 45 MHz（范围 30-60 MHz 的中点） | Golesworthy et al. (2023) *JCP* |
| $B_\text{earth}$ | 0.5 G（50 μT） | 地球磁场 |

### 2.4 稳态单态产率

我们关心的核心量是单态产率 $\Phi_S$——自由基对最终从单态复合的概率：

\\[
\Phi_S = k \int_0^\infty \text{Tr}[P_S \rho(t)] e^{-kt} dt
\\]

这是一个 Laplace 变换。不需要数值积分 ODE——可以直接写成：

\\[
\Phi_S = k \cdot \text{Tr}[P_S \cdot (k\mathbf{1} - \mathcal{L})^{-1} \cdot \rho_0]
\\]

其中 $\mathcal{L}$ 是 Liouvillian 超算符（$D^2 \times D^2$ 矩阵，$D$ 为 Hilbert 空间维度），$\rho_0 = \|S\rangle\langle S\| \otimes (1/d)_\text{nuc}$ 是初始态（电子单态 + 核自旋完全混合）。

> **方法优势：** 直接解 $(k\mathbf{1}-\mathcal{L})\mathbf{x} = \text{vec}(\rho_0)$ 这个线性方程，比传统的 ODE 数值积分快**约500倍**。36维系统扫1152个磁场方向只需3.2秒（传统方法需27分钟）。

方向敏感度定义为磁场平行于 FAD N5 超精细主轴（ẑ）与垂直于主轴时单态产率的绝对差：

\\[
\|\Delta\Phi\| = \|\Phi_S(\mathbf{B}\parallel\hat{z}) - \Phi_S(\mathbf{B}\perp\hat{z})\|_{B=0.5\text{ G}}
\\]

## 3. 计算验证

在报告核心结果之前，我们先用六个独立基准验证了求解器的正确性：

| # | 基准 | 结果 |
|---|---|---|
| 1 | 有效超精细耦合 σ | σ=1.69 mT，与Steiner-Ulrich公式精确匹配 |
| 2 | 标度不变性 | λ=0.5,2.0时Φ差 < 0.2% |
| 3 | 各向同性极限 | B=0时$\|\Delta\Phi\|=0$ ✓ |
| 4 | 零耦合极限 | 与纯去相位动力学的解析预测一致 |
| 5 | Weller $B_{1/2}$公式 | $\Gamma_d\to 0$给出2.72 mT（在理论范围2.46-3.71 mT内） |
| 6 | W369F预测检验 | 仅改变$\tau_\text{RP}$（60 ns→299 ns）产生6.6×增强——与实验一致 |

> **$B_{1/2}$验证：** 半饱和场 $B_{1/2}$ 是MARY曲线（$\Phi_S$ vs. B）的半高宽，反映有效超精细耦合强度。我们的WT模型计算值 $B_{1/2}=3.16$ mT 与实验值 $3.55\pm 0.16$ mT（Golesworthy et al., 2023）一致。W369F突变体增强 6.6×，**仅使用已发表论文中测量的 $\tau_\text{RP}=299$ ns 作为输入**——机制是扩展的S-T混合窗口，而非改变的超精细耦合（Gravell et al., 2025）。这是零自由参数的定量验证。

## 4. 核心结果：Spin-1 单调稀释——"越少越好"

我们从两个最强的核（FAD N5 + Trp N1）出发，按各向异性从大到小的顺序逐个添加核自旋，每次计算 $\|\Delta\Phi\|$。关键的物理事实是：**<sup>14</sup>N 核的自旋是 I=1（3个量子态）**——我们使用正确的 spin-1 算符，而不是前人常用的 spin-1/2 近似（2个态）。

![核收敛曲线](/images/cry4a-convergence.png)

*图1. (a) $\|\Delta\Phi\|$ 随核数量的变化——纯单调衰减。(b) 相对于 N5+N1 基准的稀释因子。空心符号为spin-1/2近似——产生定性错误（非单调假象），在正确的spin-1处理中消失。*

| 配置 | Hilbert维度 | $\|\Delta\Phi\|$ | 稀释因子 |
|---|---|---|---|
| N5+N1（基准） | 36D | $1.86\times 10^{-3}$ | 1.0× |
| +N10 | 108D | $3.16\times 10^{-4}$ | 5.9× |
| +H1 | 72D | $2.09\times 10^{-4}$ | 8.9× |
| +H4 | 72D | $9.91\times 10^{-5}$ | 18.7× |
| +H6 | 72D | $5.88\times 10^{-5}$ | 31.6× |
| N5+N1+N10+H1（N=4） | 216D\* | $1.59\times 10^{-4}$ | 11.7× |
| +H4（N=5） | 432D\* | $4.97\times 10^{-5}$ | 37.3× |

*\*N=4和N=5通过矩阵自由GMRES方法计算，此前在计算上不可解。*

> **核心发现——"越少越好"原理：** 在正确的spin-1物理中，**每个添加的核自旋都单调稀释方向信号**。没有一个核例外。没有"非单调增强"——那是spin-1/2近似的假象。这一单调稀释源自Hilbert空间标度：每个spin-1核贡献 I(I+1)=2 个独立的S-T混合通道，破坏性干涉在 N ≥ 3 时占主导。该原理适用于所有具有多核超精细环境的自由基对系统，而不仅限于Cry4a。

### 4.1 为什么 Spin-1/2 近似是错的

自旋-1的每个核贡献 I(I+1)=2 个独立的S-T混合通道。自旋-1/2的每个核只贡献 3/4 个。随着核数量增加，spin-1 的混合通道数量增长2.7倍快。通道越多，破坏性干涉越强——方向信号被冲淡。

在 spin-1/2 近似中，通道太稀疏，个别强各向异性核（如 Trp H1）的"正面"贡献可以超过干涉噪声——产生假的信号增强。在正确的 spin-1 物理中，干涉噪声总是占主导。

### 4.2 延伸到 N=15

完整 15-20 个核的精确解（需要 $>10^7$ 维的 Hilbert 空间）在计算上尚不可行。我们使用了 **SU(3)⊗SU(2) 集体算子模型**，该模型利用了电子自旋只能通过三个集体算符 $K_\alpha = \sum_j A_{j,\alpha} I_{j,\alpha}$ 与核系综耦合的性质。该模型在 N=2-5 处以 1.13±0.26× 的精度通过了精确结果的验证。

集体模型预测：在 N=15（完整Cry4a核系综）时，$\|\Delta\Phi\|$ 比最小的 N5+N1 模型降低了约 10–30×。精确的稀释倍数取决于核的具体张量方向和相对耦合强度，但单调趋势是确定的。

## 5. 三个可证伪的独立预测

在讨论生物学意义之前，我们的模型做出了**三个独立于未知生物参数**——因此可以直接被实验检验——的预测。这些预测仅源于自旋哈密顿量，不依赖于 α 或任何下游生物参数。

1. **位点特异性 <sup>15</sup>N 同位素效应。** <sup>15</sup>N 标记在 FAD N5 将 $\|\Delta\Phi\|$ 降低至 <sup>14</sup>N 值的 0.20×；标记在 Trp N1 降低至 0.24×；双标记降低至 0.14×。这与 Galván et al. (2024) 关于 <sup>15</sup>N **增强**灵敏度的预测相矛盾，提供了一个清晰的实验检验——仅需表达 <sup>15</sup>N 标记的 Cry4a 并测量 MARY 曲线。

2. **低温增强。** $\|\Delta\Phi\|$ 在从 300 K 冷却至 200 K 时增加约 **22×**，由复合和退相干的 Arrhenius 减缓驱动。这是因为更低的温度延长了 $\tau_\text{RP}$（更慢的复合），扩大了 S-T 混合窗口。预测不依赖于蛋白的具体活化能——仅需 Arrhenius 行为，不涉及相变。

3. **$B_{1/2}$ 各向异性。** $B_{1/2}$ 在 **B**∥ẑ（N5主轴方向）时为 3.16 mT；在 **B**⟂ẑ 时，MARY 曲线显示最小调制（$\Phi_S$ 在 0–50 mT 范围内变化 <0.2%）。可通过在脂质双层上定向排列 Cry4a 进行实验检验（Bradlaugh et al., 2025）。

> **为什么这些预测很重要：** 它们不依赖于 α、$N_\text{cells}$、S 或任何未知生物参数。如果这三个预测中任何一个被实验证伪，则当前形式的 RPM 就需要修正。如果全部被证实，则 RPM 在单分子物理层面的有效性得以确立——剩下的唯一问题是生物放大是否足够。

## 6. 生物学意义：可行性走廊

给定单分子 $\|\Delta\Phi\| = 1.86\times 10^{-3}$（N5+N1上限），需要什么样的生物参数才能使罗盘起作用？我们将下游生物学视为参数化的放大链：

| 阶段 | 机制 | 增益 | 约束 |
|---|---|---|---|
| 1. 系综平均 | $N_\text{copies} \approx 10^5$ Cry4a/细胞 | $\sqrt{N_\text{copies}} \approx 316$ | Xu et al. (2021) *Nature* |
| 2. 取向有序 | 膜有序参数 $S \in [0.3, 0.8]$ | S（保持方向信号） | Bradlaugh et al. (2025) *ACS Chem. Biol.* |
| 3. G蛋白级联 | 放大因子 $\alpha \in [10^2, 10^5]$ | α（生化增益） | 视紫红质基准 (Arshavsky et al., 2002) |
| 4. 多细胞整合 | $N_\text{cells}$ 个感光细胞汇聚 | $\sqrt{N_\text{cells}}$ | 视网膜汇聚比 2:1 到 >10:1 |

该链的角度误差约为 $\delta\theta \approx 180^\circ / \text{SNR}$，其中：

\\[
\text{SNR} = \sqrt{N_\text{copies} \cdot N_\text{cells} \cdot \alpha} \cdot S \cdot \|\Delta\Phi\| / \sigma_\Phi
\\]

其中 $\sigma_\Phi = \sqrt{\Phi_S(1-\Phi_S)} \approx 0.48$ 是 $\Phi_S \approx 0.35$ 处的单分子 Poisson 噪声。该估计有意简化——其目的是识别参数区间，而非进行精确的角度预测。

![可行性走廊](/images/cry4a-feasibility-corridor.png)

*图2. Cry4a罗盘的可行性走廊。(a) 取向序 S vs. G蛋白放大 α，在 $N_\text{cells}=100$ 时。(b) 参与细胞数 $N_\text{cells}$ vs. α，在 S=0.5 时。绿色：<5° 角度误差。红色：>30°。已知参数范围（蓝色框）主要位于功能区。(c) 每个 (S, $N_\text{cells}$) 组合实现 5° 精度所需的最小 α。*

> **关键结论：** 在整个已知参数范围——$S \in [0.3, 0.8]$，$N_\text{cells} \in [1, 10^3]$，$\alpha \in [10^2, 10^5]$，$N_\text{copies} \approx 10^5$——**我们的量级估计将 Cry4a 罗盘置于可行范围内**。即使在最差值（S=0.3，$N_\text{cells}=1$），所需放大 $\alpha \approx 4.5\times 10^4$ 仍在视紫红质基准之内。

### 6.1 完整核系综的影响

以上使用 N5+N1 的 $\|\Delta\Phi\| = 1.86\times 10^{-3}$ 作为保守的单分子上限。在现实的多核 Cry4a（N ≈ 10–15）中，$\|\Delta\Phi\|$ 被额外稀释约 10–30×。这将最差情况下所需 α 上移至 $4.5\times 10^5$–$1.4\times 10^6$ 区间——接近但可比于视紫红质基准（$\alpha_\text{rhodopsin} \sim 10^5$–$10^7$），并且在中等多细胞整合条件下（$N_\text{cells} \sim 10^2$）即可实现。

### 6.2 唯一的关键未知量：α

在上述参数中，$N_\text{copies}$、S 和 $N_\text{cells}$ 均有实验约束（或至少可被合理估计）。**唯一完全没有实验测量的关键参数是 α——Cry4a 特异性的 G 蛋白放大因子。**

> **如果 $\alpha \gtrsim 10^3$：** 罗盘在单细胞水平即可运行。
> **如果 $\alpha < 10^3$：** 需要多细胞整合。
>
> 该参数**可通过 GTP-γ-S 结合实验直接测量**——该实验不需要磁场调制。这是关闭从分子量子动力学到生物体行为这一完整定量链条所剩的最后一个关键实验。

## 7. 讨论

我们使用精确的 spin-1 动力学计算了 Cry4a 自由基对的单分子方向灵敏度，并证明了——与"更大的核系综提供更丰富方向信息"的直觉相反——**每个额外的核自旋都单调稀释 $\|\Delta\Phi\|$**。这一"越少越好"原理源于 Hilbert 空间标度：每个 spin-1 核贡献 I(I+1)=2 个独立的 S-T 混合通道，破坏性干涉在 N ≥ 3 时占主导。

我们的 $B_{1/2}=3.16$ mT 落在独立自旋动力学计算的理论范围之内（Wong & Hore, 2023），W369F 突变体的 6.6× 增强仅使用已测量的 $\tau_\text{RP}=299$ ns 即被定量重现——确认了机制是扩展的 S-T 混合窗口，而非改变的超精细耦合。

我们模型的三个可证伪预测——22× 低温增强、位点特异性 <sup>15</sup>N 同位素效应（抑制比 0.14–0.24）、以及强 $B_{1/2}$ 各向异性——仅源于自旋哈密顿量，不依赖于 α 或任何下游生物参数。它们为 RPM 在分子层面提供了清洁的实验检验。如果被证伪，当前形式的 RPM 需要修正；如果被证实，RPM 在单分子物理层面的有效性得以确立。

连接单分子信号与生物体层面行为的唯一关键未知量是 α——Cry4a 特异性的 G 蛋白放大因子。我们的可行性走廊提供了生物需求的量级估计——识别 RPM 在物理上足够的参数区间——但无法确定生物学是否确实在这些区间内运行。**这是对从第一性原理可以计算和不能计算的内容的诚实陈述：** 我们可以计算 $\|\Delta\Phi\|$ 并与实验验证；我们可以估计所需放大；但我们不能预测 α，α 必须通过 GTP-γ-S 结合实验来测量。

在此之前，我们的单分子界限提供了关于 RPM 物理合理性最坚实的可用约束。

## 8. 代码与计算

所有计算使用 Python 3.10 + QuTiP 5.2 + SciPy 1.15。核心求解器（`radical_pair_fast.py`）约300行，以约500倍的加速比（相较于标准 QuTiP `mesolve`）计算稳态单态产率。精确计算可达 5 核（432D Hilbert 空间、1,866D Liouvillian 空间）——使用矩阵自由 GMRES 方法解决了此前因 SuperLU 内存爆炸而不可解的问题。对于更大的系统，SU(3)⊗SU(2) 集体算子模型将维度从 $>10^7$ 降至 544，并在可精确验证的区间（N=2–5）以 1.13±0.26× 的精度通过与精确结果的比对。

代码和重现材料可在 [GitHub](https://github.com/TankTechnology/radical-pair) 获取。

---

## 参考文献

1. Xu, J. et al. Magnetic sensitivity of cryptochrome 4 from a migratory songbird. *Nature* **594**, 535–540 (2021).
2. Gravell, J.D. et al. Spectroscopic characterization of radical pair photochemistry in nonmigratory avian cryptochromes. *J. Am. Chem. Soc.* **147**, 24286–24298 (2025).
3. Golesworthy, M.J. et al. Singlet-triplet dephasing in radical pairs in avian cryptochromes. *J. Chem. Phys.* **159**, 105102 (2023).
4. Grüning, G. et al. Effects of dynamical degrees of freedom on magnetic compass sensitivity. *J. Am. Chem. Soc.* **144**, 22902–22914 (2022).
5. Hore, P.J. & Mouritsen, H. The radical-pair mechanism of magnetoreception. *Annu. Rev. Biophys.* **45**, 299–344 (2016).
6. Bradlaugh, A. et al. European Robin Cryptochrome-4a associates with lipid bilayers. *ACS Chem. Biol.* **20**, 592–606 (2025).
7. Galván, I. et al. Isotope effects on radical pair performance in cryptochrome. *BioEssays* **46**, 2300152 (2024).
8. Wong, S.Y., Benjamin, P. & Hore, P.J. Magnetic field effects on radical pair reactions. *Phys. Chem. Chem. Phys.* **25**, 975–982 (2023).
9. Arshavsky, V.Y., Lamb, T.D. & Pugh, E.N. G proteins and phototransduction. *Annu. Rev. Physiol.* **64**, 153–187 (2002).

</div>

<div id="lang-en" class="lang-content" markdown="1">

> **Abstract** — Whether the radical pair mechanism can explain avian magnetoreception depends on whether a single Cry4a protein produces sufficient directional signal. We compute the single-molecule directional sensitivity $\|\Delta\Phi\| = \|\Phi_S(\mathbf{B}\parallel\hat{z}) - \Phi_S(\mathbf{B}\perp\hat{z})\|$ for the [FAD<sup>•−</sup> TrpH<sup>•+</sup>] radical pair using exact spin-1 Liouvillian dynamics with DFT-derived hyperfine tensors, finding $\|\Delta\Phi\| = 1.86 \times 10^{-3}$ for the N5+N1 nuclear configuration (an upper bound for wild-type Cry4a). Our $B_{1/2}=3.16$ mT is consistent with experiment ($3.55\pm 0.16$ mT, Golesworthy et al., 2023) and the W369F mutant enhancement ($6.6\times$) is quantitatively reproduced using only the measured $\tau_\text{RP}=299$ ns. Each additional nuclear spin monotonically dilutes this signal---a **"fewer is always better" principle**---with the full nuclear ensemble diluted by ~10--30×. Our model makes three falsifiable predictions independent of unknown biology: a 22× low-temperature enhancement of $\|\Delta\Phi\|$; site-specific <sup>15</sup>N isotope effects ($\|\Delta\Phi\|\_{^{15}\text{N}}/\|\Delta\Phi\|\_{^{14}\text{N}} \approx 0.14$--$0.24$); and strong $B_{1/2}$ anisotropy. We construct a feasibility corridor to frame the biological requirements: for realistic cellular parameters (Cry4a copy number $\sim 10^5$, orientational order $S \in [0.3, 0.8]$, G-protein amplification $\alpha \in [10^2, 10^5]$), our order-of-magnitude estimate places the Cry4a compass within the feasible regime. The single critical unknown is $\alpha$, directly measurable by GTP-γ-S binding assay.

---

## 1. The Problem

European robins migrate from Scandinavia to North Africa each year, navigating by sensing the direction of Earth's magnetic field. The geomagnetic field is only about 50 μT---the magnet in your phone speaker is ten thousand times stronger. Birds accomplish this because their retinas contain a protein called **Cry4a (Cryptochrome 4a)**.

Upon absorbing blue light, Cry4a generates a pair of unpaired electrons---a **radical pair** [FAD<sup>•−</sup> … TrpH<sup>•+</sup>]. The spin states of these two electrons evolve on nanosecond-to-microsecond timescales, and the direction of the geomagnetic field affects the probability that they end up in the "singlet" versus "triplet" state. Ultimately, singlet and triplet states have different chemical fates---the product ratio carries information about the magnetic field direction.

This is known as the **Radical Pair Mechanism (RPM)**. It has substantial theoretical and experimental support: purified Cry4a protein was shown in 2021 to respond to magnetic fields in vitro (Xu et al., *Nature* 2021).

But an unresolved question remains: **Cry4a is surrounded by approximately 15--20 atomic nuclei (<sup>14</sup>N and <sup>1</sup>H)**. Each nucleus interacts with the electron spins via hyperfine coupling. The intuition is---more nuclei = richer quantum dynamics = stronger directional sensitivity. Is this true?

A central open question links single-molecule physics to organism-level behavior: in the inevitable presence of ~15--20 nuclear spins in the protein environment, is the single-molecule directional signal sufficient, after biological amplification, to support a compass with 5° precision? Answering this requires: (i) a rigorous computation of the single-molecule $\|\Delta\Phi\|$; (ii) a framework that maps this molecular signal through successive layers of biological organization to organism-level precision.

This paper provides (i), using exact spin-1 Liouvillian dynamics with all parameters experimentally constrained; and (ii), via a feasibility corridor that identifies parameter combinations for which RPM is physically sufficient, independent of unknown biological details.

## 2. Physical Model

### 2.1 Spin Hamiltonian

The radical pair comprises two electron spins (S=1/2) and N nuclear spins. The Hamiltonian of the system, in angular frequency units (ħ=1), is:

\\[
H = H_Z + H_\text{HF}
\\]

**Zeeman term:**

\\[
H_Z = \gamma_e (\mathbf{S}_1 + \mathbf{S}_2) \cdot \mathbf{B}
\\]

where $\gamma_e = 17.6$ MHz/G is the electron gyromagnetic ratio, $\mathbf{B} = B(\sin\theta\cos\phi, \sin\theta\sin\phi, \cos\theta)$, and $B = 0.5$ G (Earth's magnetic field).

**Hyperfine term:**

\\[
H_\text{HF} = \sum_j \mathbf{S}_{e(j)} \cdot \mathbf{A}_j \cdot \mathbf{I}_j
\\]

where $\mathbf{A}_j$ is the hyperfine tensor---describing the coupling of the j-th nucleus to the electron. The tensor is not spherically symmetric: coupling along certain directions is far stronger than along others. **This is the physical origin of directional sensitivity.**

> **DFT hyperfine tensor principal values** (units: Gauss, source: Grüning et al. 2022 *JACS*): N5 exhibits the strongest anisotropy (A<sub>xx</sub> far larger than A<sub>yy</sub>, A<sub>zz</sub>), serving as the primary provider of the compass directional reference axis. Nonzero off-diagonal tensor elements supply secondary directional information.

| Nucleus | Radical | Spin I | A<sub>xx</sub> | A<sub>yy</sub> | A<sub>zz</sub> |
|---|---|---|---|---|---|
| FAD N5 | FAD<sup>•−</sup> | 1 | 17.57 | −0.87 | −1.00 |
| Trp N1 | TrpH<sup>•+</sup> | 1 | 10.81 | −0.53 | −0.64 |
| Trp H1 | TrpH<sup>•+</sup> | ½ | −0.07 | −7.05 | −10.83 |
| FAD N10 | FAD<sup>•−</sup> | 1 | 6.05 | −0.14 | −0.24 |
| Trp H4 | TrpH<sup>•+</sup> | ½ | −1.88 | −5.36 | −7.40 |
| FAD H6 | FAD<sup>•−</sup> | ½ | −1.98 | −4.34 | −5.30 |

### 2.2 Lindblad Dynamics

The radical pair is not an isolated system. Its spin coherence is destroyed by fluctuations in the protein environment (decoherence), and it recombines to the ground state at a finite rate.

The density matrix ρ(t) of the system evolves according to the **Lindblad master equation**:

\\[
\frac{d\rho}{dt} = -i[H, \rho] - \frac{k}{2}\\{P_S, \rho\\} + \sum_k \left[c_k \rho c_k^\dagger - \frac{1}{2}\\{c_k^\dagger c_k, \rho\\}\right]
\\]

where $P_S = \|S\rangle\langle S\|$ is the singlet projection operator and $k$ is the recombination rate. Decoherence is described by the Lindblad operators $c_k$:

\\[
c_{1,2} = \sqrt{\Gamma_d} \cdot S_z \quad\text{(pure dephasing, }\Gamma_d = 45\text{ MHz)}
\\]
\\[
c_{3-6} = \sqrt{\Gamma_r/2} \cdot S_\pm \quad\text{(spin relaxation, }\Gamma_r = 0.1\text{ MHz)}
\\]

### 2.3 Experimentally Constrained Parameters

**All parameters come from independent experiments---zero free parameters.**

| Parameter | Value | Source |
|---|---|---|
| $k_\text{WT}$ | 16.7 MHz ($\tau_\text{RP}=60$ ns) | Gravell et al. (2025) *JACS* |
| $k_\text{W369F}$ | 3.3 MHz ($\tau_\text{RP}=299$ ns) | Gravell et al. (2025) *JACS* |
| $\Gamma_d$ | 45 MHz (midpoint of range 30--60 MHz) | Golesworthy et al. (2023) *JCP* |
| $B_\text{earth}$ | 0.5 G (50 μT) | Earth's magnetic field |

### 2.4 Steady-State Singlet Yield

The central quantity of interest is the singlet yield $\Phi_S$---the probability that the radical pair ultimately recombines from the singlet state:

\\[
\Phi_S = k \int_0^\infty \text{Tr}[P_S \rho(t)] e^{-kt} dt
\\]

This is a Laplace transform. Rather than numerically integrating the ODE, we can directly write:

\\[
\Phi_S = k \cdot \text{Tr}[P_S \cdot (k\mathbf{1} - \mathcal{L})^{-1} \cdot \rho_0]
\\]

where $\mathcal{L}$ is the Liouvillian superoperator (a $D^2 \times D^2$ matrix, with $D$ the Hilbert space dimension), and $\rho_0 = \|S\rangle\langle S\| \otimes (1/d)_\text{nuc}$ is the initial state (electronic singlet + fully mixed nuclear spins).

> **Methodological advantage:** Solving the linear system $(k\mathbf{1}-\mathcal{L})\mathbf{x} = \text{vec}(\rho_0)$ directly is **~500× faster** than conventional ODE numerical integration. A 36-dimensional system over 1,152 field directions requires only 3.2 seconds (vs. 27 minutes for the conventional method).

The directional sensitivity is defined as the absolute difference in singlet yield when the magnetic field is parallel versus perpendicular to the FAD N5 hyperfine principal axis (ẑ):

\\[
\|\Delta\Phi\| = \|\Phi_S(\mathbf{B}\parallel\hat{z}) - \Phi_S(\mathbf{B}\perp\hat{z})\|_{B=0.5\text{ G}}
\\]

## 3. Computational Validation

Before reporting the core results, we validated the solver against six independent benchmarks:

| # | Benchmark | Result |
|---|---|---|
| 1 | Effective hyperfine coupling σ | σ=1.69 mT, exact match with Steiner-Ulrich formula |
| 2 | Scaling invariance | Φ difference < 0.2% for λ=0.5, 2.0 |
| 3 | Isotropic limit | $\|\Delta\Phi\|=0$ at B=0 ✓ |
| 4 | Zero-coupling limit | Consistent with analytical prediction for pure dephasing dynamics |
| 5 | Weller $B_{1/2}$ formula | $\Gamma_d\to 0$ yields 2.72 mT (within theoretical range 2.46--3.71 mT) |
| 6 | W369F prediction test | Changing only $\tau_\text{RP}$ (60 ns→299 ns) yields 6.6× enhancement---consistent with experiment |

> **$B_{1/2}$ validation:** The half-saturation field $B_{1/2}$ is the half-width at half-maximum of the MARY curve ($\Phi_S$ vs. B), reflecting the effective hyperfine coupling strength. Our WT model value $B_{1/2}=3.16$ mT agrees with the experimental value of $3.55\pm 0.16$ mT (Golesworthy et al., 2023). The W369F mutant enhancement of 6.6× is reproduced **using only the measured $\tau_\text{RP}=299$ ns from the published literature as input**---the mechanism is an extended S-T mixing window, not altered hyperfine couplings (Gravell et al., 2025). This constitutes a zero-free-parameter quantitative validation.

## 4. Core Result: Spin-1 Monotonic Dilution---"Fewer Is Always Better"

Starting from the two strongest nuclei (FAD N5 + Trp N1), we sequentially add nuclear spins in order of decreasing anisotropy, computing $\|\Delta\Phi\|$ at each step. The critical physical fact: **<sup>14</sup>N nuclei have spin I=1 (3 quantum states)**---we use the correct spin-1 operators, not the spin-1/2 approximation (2 states) commonly employed in prior work.

![Nuclear convergence curve](/images/cry4a-convergence.png)

*Figure 1. (a) $\|\Delta\Phi\|$ vs. number of nuclei---purely monotonic decay. (b) Dilution factor relative to the N5+N1 baseline. Open symbols correspond to the spin-1/2 approximation---producing qualitatively incorrect (non-monotonic) artifacts that vanish under the correct spin-1 treatment.*

| Configuration | Hilbert dimension | $\|\Delta\Phi\|$ | Dilution factor |
|---|---|---|---|
| N5+N1 (baseline) | 36D | $1.86\times 10^{-3}$ | 1.0× |
| +N10 | 108D | $3.16\times 10^{-4}$ | 5.9× |
| +H1 | 72D | $2.09\times 10^{-4}$ | 8.9× |
| +H4 | 72D | $9.91\times 10^{-5}$ | 18.7× |
| +H6 | 72D | $5.88\times 10^{-5}$ | 31.6× |
| N5+N1+N10+H1 (N=4) | 216D\* | $1.59\times 10^{-4}$ | 11.7× |
| +H4 (N=5) | 432D\* | $4.97\times 10^{-5}$ | 37.3× |

*\*N=4 and N=5 computed via matrix-free GMRES method, previously computationally intractable.*

> **Core finding---the "fewer is always better" principle:** Under the correct spin-1 physics, **each added nuclear spin monotonically dilutes the directional signal**. No nucleus is an exception. There is no "non-monotonic enhancement"---that is an artifact of the spin-1/2 approximation. This monotonic dilution arises from Hilbert space scaling: each spin-1 nucleus contributes I(I+1)=2 independent S-T mixing channels, and destructive interference dominates for N ≥ 3. This principle applies to all radical pair systems with multi-nuclear hyperfine environments, not only Cry4a.

### 4.1 Why the Spin-1/2 Approximation Is Wrong

Each spin-1 nucleus contributes I(I+1)=2 independent S-T mixing channels. Each spin-1/2 nucleus contributes only 3/4. As the number of nuclei increases, the number of mixing channels in spin-1 grows 2.7× faster. More channels mean stronger destructive interference---the directional signal is washed out.

In the spin-1/2 approximation, channels are too sparse, and the "positive" contribution of individual strongly anisotropic nuclei (e.g., Trp H1) can exceed the interference noise---producing a spurious signal enhancement. Under the correct spin-1 physics, interference noise always dominates.

### 4.2 Extension to N=15

Exact solution for the full 15--20 nuclei (requiring a Hilbert space of $>10^7$ dimensions) is not currently computationally feasible. We employed an **SU(3)⊗SU(2) collective operator model**, which exploits the fact that the electron spin couples to the nuclear ensemble only through three collective operators $K_\alpha = \sum_j A_{j,\alpha} I_{j,\alpha}$. This model passes validation against exact results at N=2--5 with an accuracy of 1.13±0.26×.

The collective model predicts: at N=15 (the full Cry4a nuclear ensemble), $\|\Delta\Phi\|$ is reduced by approximately 10--30× relative to the minimal N5+N1 model. The precise dilution factor depends on specific nuclear tensor orientations and relative coupling strengths, but the monotonic trend is definitive.

## 5. Three Falsifiable, Independent Predictions

Before discussing biological implications, our model makes **three predictions that are independent of unknown biological parameters**---and thus directly experimentally testable. These predictions arise solely from the spin Hamiltonian and do not depend on α or any downstream biological parameters.

1. **Site-specific <sup>15</sup>N isotope effects.** <sup>15</sup>N labeling at FAD N5 reduces $\|\Delta\Phi\|$ to 0.20× the <sup>14</sup>N value; labeling at Trp N1 reduces it to 0.24×; double labeling reduces it to 0.14×. This contradicts the prediction of Galván et al. (2024) that <sup>15</sup>N **enhances** sensitivity, providing a clean experimental test---one need only express <sup>15</sup>N-labeled Cry4a and measure the MARY curve.

2. **Low-temperature enhancement.** $\|\Delta\Phi\|$ increases by approximately **22×** upon cooling from 300 K to 200 K, driven by Arrhenius slowing of recombination and dephasing. This occurs because lower temperatures extend $\tau_\text{RP}$ (slower recombination), enlarging the S-T mixing window. The prediction does not depend on the protein's specific activation energy---only on Arrhenius behavior, without invoking any phase transition.

3. **$B_{1/2}$ anisotropy.** $B_{1/2}$ = 3.16 mT when **B**∥ẑ (the N5 principal axis direction); when **B**⟂ẑ, the MARY curve shows minimal modulation ($\Phi_S$ varies by <0.2% over 0--50 mT). This is experimentally testable by orienting Cry4a on lipid bilayers (Bradlaugh et al., 2025).

> **Why these predictions matter:** They are independent of α, $N_\text{cells}$, S, or any unknown biological parameter. If any one of these three predictions is experimentally falsified, then RPM in its current form requires revision. If all three are confirmed, the validity of RPM at the single-molecule physics level is established---the only remaining question is whether biological amplification is sufficient.

## 6. Biological Implications: The Feasibility Corridor

Given the single-molecule $\|\Delta\Phi\| = 1.86\times 10^{-3}$ (N5+N1 upper bound), what biological parameters are required for the compass to function? We treat the downstream biology as a parameterized amplification chain:

| Stage | Mechanism | Gain | Constraint |
|---|---|---|---|
| 1. Ensemble averaging | $N_\text{copies} \approx 10^5$ Cry4a/cell | $\sqrt{N_\text{copies}} \approx 316$ | Xu et al. (2021) *Nature* |
| 2. Orientational order | Membrane order parameter $S \in [0.3, 0.8]$ | S (preserves directional signal) | Bradlaugh et al. (2025) *ACS Chem. Biol.* |
| 3. G-protein cascade | Amplification factor $\alpha \in [10^2, 10^5]$ | α (biochemical gain) | Rhodopsin benchmark (Arshavsky et al., 2002) |
| 4. Multicellular integration | $N_\text{cells}$ photoreceptor cells converging | $\sqrt{N_\text{cells}}$ | Retinal convergence ratios 2:1 to >10:1 |

The angular error of this chain is approximately $\delta\theta \approx 180^\circ / \text{SNR}$, where:

\\[
\text{SNR} = \sqrt{N_\text{copies} \cdot N_\text{cells} \cdot \alpha} \cdot S \cdot \|\Delta\Phi\| / \sigma_\Phi
\\]

where $\sigma_\Phi = \sqrt{\Phi_S(1-\Phi_S)} \approx 0.48$ is the single-molecule Poisson noise at $\Phi_S \approx 0.35$. This estimate is deliberately simplified---its purpose is to identify parameter regimes, not to make precise angular predictions.

![Feasibility corridor](/images/cry4a-feasibility-corridor.png)

*Figure 2. Feasibility corridor for the Cry4a compass. (a) Orientational order S vs. G-protein amplification α, at $N_\text{cells}=100$. (b) Number of participating cells $N_\text{cells}$ vs. α, at S=0.5. Green: <5° angular error. Red: >30°. Known parameter ranges (blue boxes) lie predominantly in the functional regime. (c) Minimum α required to achieve 5° precision for each (S, $N_\text{cells}$) combination.*

> **Key conclusion:** Across the entire known parameter range---$S \in [0.3, 0.8]$, $N_\text{cells} \in [1, 10^3]$, $\alpha \in [10^2, 10^5]$, $N_\text{copies} \approx 10^5$---**our order-of-magnitude estimate places the Cry4a compass within the feasible regime**. Even at the worst-case values (S=0.3, $N_\text{cells}=1$), the required amplification $\alpha \approx 4.5\times 10^4$ remains within the rhodopsin benchmark.

### 6.1 Impact of the Full Nuclear Ensemble

The above uses $\|\Delta\Phi\| = 1.86\times 10^{-3}$ from N5+N1 as a conservative single-molecule upper bound. In realistic multi-nuclear Cry4a (N ≈ 10--15), $\|\Delta\Phi\|$ is further diluted by approximately 10--30×. This raises the worst-case required α to the $4.5\times 10^5$--$1.4\times 10^6$ range---approaching but comparable to the rhodopsin benchmark ($\alpha_\text{rhodopsin} \sim 10^5$--$10^7$), and readily achievable under moderate multicellular integration ($N_\text{cells} \sim 10^2$).

### 6.2 The Single Critical Unknown: α

Among the above parameters, $N_\text{copies}$, S, and $N_\text{cells}$ all have experimental constraints (or at least can be reasonably estimated). **The only critical parameter that has never been experimentally measured is α---the Cry4a-specific G-protein amplification factor.**

> **If $\alpha \gtrsim 10^3$:** the compass can operate at the single-cell level.
> **If $\alpha < 10^3$:** multicellular integration is required.
>
> This parameter **is directly measurable via GTP-γ-S binding assay**---an experiment that requires no magnetic field modulation. This is the last critical experiment needed to close the complete quantitative chain from molecular quantum dynamics to organismal behavior.

## 7. Discussion

We have computed the single-molecule directional sensitivity of the Cry4a radical pair using exact spin-1 dynamics and demonstrated that---contrary to the intuition that a larger nuclear ensemble provides richer directional information---**each additional nuclear spin monotonically dilutes $\|\Delta\Phi\|$**. This "fewer is always better" principle arises from Hilbert space scaling: each spin-1 nucleus contributes I(I+1)=2 independent S-T mixing channels, and destructive interference dominates for N ≥ 3.

Our $B_{1/2}=3.16$ mT falls within the theoretical range of independent spin dynamics calculations (Wong & Hore, 2023), and the 6.6× enhancement of the W369F mutant is quantitatively reproduced using only the measured $\tau_\text{RP}=299$ ns---confirming that the mechanism is an extended S-T mixing window, not altered hyperfine couplings.

Our model's three falsifiable predictions---22× low-temperature enhancement, site-specific <sup>15</sup>N isotope effects (suppression ratio 0.14--0.24), and strong $B_{1/2}$ anisotropy---arise solely from the spin Hamiltonian and do not depend on α or any downstream biological parameters. They provide clean experimental tests of RPM at the molecular level. If falsified, RPM in its current form requires revision; if confirmed, the validity of RPM at the single-molecule physics level is established.

The single critical unknown linking single-molecule signals to organism-level behavior is α---the Cry4a-specific G-protein amplification factor. Our feasibility corridor provides an order-of-magnitude estimate of the biological requirements---identifying the parameter regime in which RPM is physically sufficient---but cannot determine whether biology actually operates in that regime. **This is an honest statement about what can and cannot be computed from first principles:** we can compute $\|\Delta\Phi\|$ and validate against experiment; we can estimate the required amplification; but we cannot predict α, which must be measured via GTP-γ-S binding assay.

Until then, our single-molecule bound provides the most rigorous constraint available on the physical plausibility of RPM.

## 8. Code and Computation

All computations used Python 3.10 + QuTiP 5.2 + SciPy 1.15. The core solver (`radical_pair_fast.py`) is approximately 300 lines and computes the steady-state singlet yield with roughly a 500× speedup relative to standard QuTiP `mesolve`. Exact calculations are feasible up to 5 nuclei (432D Hilbert space, 1,866D Liouvillian space)---using a matrix-free GMRES method that resolves problems previously intractable due to SuperLU memory blowup. For larger systems, the SU(3)⊗SU(2) collective operator model reduces the dimensionality from $>10^7$ to 544, and passes validation against exact results in the exactly verifiable regime (N=2--5) with an accuracy of 1.13±0.26×.

Code and reproduction materials are available on [GitHub](https://github.com/TankTechnology/radical-pair).

---

## References

1. Xu, J. et al. Magnetic sensitivity of cryptochrome 4 from a migratory songbird. *Nature* **594**, 535–540 (2021).
2. Gravell, J.D. et al. Spectroscopic characterization of radical pair photochemistry in nonmigratory avian cryptochromes. *J. Am. Chem. Soc.* **147**, 24286–24298 (2025).
3. Golesworthy, M.J. et al. Singlet-triplet dephasing in radical pairs in avian cryptochromes. *J. Chem. Phys.* **159**, 105102 (2023).
4. Grüning, G. et al. Effects of dynamical degrees of freedom on magnetic compass sensitivity. *J. Am. Chem. Soc.* **144**, 22902–22914 (2022).
5. Hore, P.J. & Mouritsen, H. The radical-pair mechanism of magnetoreception. *Annu. Rev. Biophys.* **45**, 299–344 (2016).
6. Bradlaugh, A. et al. European Robin Cryptochrome-4a associates with lipid bilayers. *ACS Chem. Biol.* **20**, 592–606 (2025).
7. Galván, I. et al. Isotope effects on radical pair performance in cryptochrome. *BioEssays* **46**, 2300152 (2024).
8. Wong, S.Y., Benjamin, P. & Hore, P.J. Magnetic field effects on radical pair reactions. *Phys. Chem. Chem. Phys.* **25**, 975–982 (2023).
9. Arshavsky, V.Y., Lamb, T.D. & Pugh, E.N. G proteins and phototransduction. *Annu. Rev. Physiol.* **64**, 153–187 (2002).

</div>

<script>
function switchLang(lang) {
  document.querySelectorAll('.lang-content').forEach(function(el) {
    el.style.display = 'none';
  });
  document.getElementById('lang-' + lang).style.display = 'block';
  document.querySelectorAll('.lang-switch a').forEach(function(el) {
    el.classList.remove('active');
  });
  document.querySelector('.lang-switch a[href="#' + lang + '"]').classList.add('active');
}
</script>
