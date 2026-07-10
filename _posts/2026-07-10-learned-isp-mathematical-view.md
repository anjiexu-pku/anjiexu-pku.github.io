---
title: "从 RAW 到 sRGB: Learned ISP 的数学本质"
date: 2026-07-10
categories:
  - tech
tags:
  - computational-photography
  - isp
  - raw
  - deep-learning
---

我们平时说“相机拍了一张照片”, 这句话其实省略了太多东西。传感器并不会直接给出一张好看的 RGB 图片。它最初得到的是 RAW: 线性的、带噪声的、经过 CFA 马赛克采样的传感器读数。我们最终看到的 sRGB/JPEG, 则是经过一整套 ISP, Image Signal Processing pipeline, 之后的结果。

所以 learned ISP 要回答的问题不是“能不能用神经网络修图”, 而是:

> 给定传感器测量, 如何恢复、解释并渲染出某种目标图像?

这句话里有三个层次: 恢复, 是从有噪声、有缺失的 RAW 中估计场景信号; 解释, 是把相机响应、颜色、曝光、噪声和显示模型放到同一个数学框架里; 渲染, 是决定什么样的输出才算“好图像”。深度学习进入 ISP 的真正意义, 是把这些原本由工程规则、厂商经验和人工调参定义的流程, 变成一个由数据、损失函数、结构先验和任务目标共同决定的优化问题。

下面我尝试从一个尽量小但足够有表达力的数学模型出发, 推导 learned ISP 的问题本质、求解思路和一些结论。

## RAW 不是照片, 而是传感器观测

设场景在像素位置 $p$ 处进入相机的光谱辐射为 $L(p,\lambda)$, 曝光时间为 $t$, 第 $c$ 个颜色通道的光谱响应为 $S_c(\lambda)$。如果暂时忽略采样和噪声, 理想线性传感器信号可以写成:

$$
x_c(p) = t \int L(p,\lambda) S_c(\lambda) d\lambda.
$$

这里的 $x_c(p)$ 仍然不是我们看到的 RGB 颜色。它只是相机第 $c$ 个通道对光谱的积分响应。不同相机的 $S_c(\lambda)$ 不同, 所以同一个场景在不同相机上的 RAW 响应也不同。

真实传感器通常使用 CFA, 例如 Bayer pattern。每个像素只记录一个颜色通道。令 $M_c(p)\in\lbrace0,1\rbrace$ 表示像素 $p$ 是否采样通道 $c$, 那么 RAW 测量可以写成:

$$
r(p) = Q_B\left(
b + g\sum_{c\in\{R,G,B\}} M_c(p)x_c(p) + n(p)
\right).
$$

其中:

- $Q_B$ 是 $B$-bit ADC 量化, 常见 RAW 是 10 到 16 bit;
- $b$ 是 black level;
- $g$ 是模拟/数字增益;
- $n(p)$ 是噪声。

对相机 RAW 来说, 一个常用近似是 Poisson-Gaussian 噪声:

$$
\mathrm{Var}(n(p)\mid x(p)) = \alpha x(p)+\beta.
$$

这表示噪声不是与信号无关的固定扰动。shot noise 随信号变大而变大, read noise 近似为固定项。低光下 $x$ 小, 信噪比低; 但只要 RAW 没有被量化和压缩彻底抹掉, 弱信号仍然可能存在。

如果把全图写成向量形式, 一个更紧凑的模型是:

$$
r = A M x + \eta.
$$

其中 $x\in \mathbb{R}^{3N}$ 是理想的全彩线性图像, $M\in\lbrace0,1\rbrace^{N\times 3N}$ 是 CFA 采样矩阵, $A$ 包含曝光、增益、黑电平归一化等线性因素, $\eta$ 是噪声。

这个式子已经说明了一个基本事实: 从 RAW 到线性 RGB 本身就是欠定问题。每个像素只有一个颜色观测, 却要恢复三个颜色值; 还有噪声、坏点、镜头阴影、饱和和量化。去马赛克与去噪并不是两个互不相关的小步骤, 而是同一个不适定逆问题的两个侧面。

## 传统 ISP 是一个组合函数, 但不是一个可逆函数

传统 ISP 可以抽象成:

$$
y = \mathrm{ISP}_{\phi}(r).
$$

展开一点:

$$
y =
Q_8
\circ J
\circ \Gamma
\circ T
\circ C
\circ W
\circ D_m
\circ D_n
\circ B(r).
$$

其中:

- $B$: black level subtraction 和归一化;
- $D_n$: denoising;
- $D_m$: demosaicking;
- $W$: white balance;
- $C$: color correction / camera RGB 到标准颜色空间;
- $T$: tone mapping;
- $\Gamma$: gamma encoding;
- $J$: sharpening, local contrast, style rendering 等工程处理;
- $Q_8$: 8-bit 量化和可能的 JPEG 压缩。

这个组合函数里有些步骤近似可逆, 例如在没有裁剪的情况下, 白平衡可以看作对角矩阵:

$$
W = \mathrm{diag}(w_R,w_G,w_B).
$$

颜色校正常常可以近似为 $3\times 3$ 矩阵:

$$
c_{out} = C c_{in}.
$$

但很多步骤不是可逆的。比如:

- $M$ 的 CFA 采样少测了颜色通道;
- 去噪会丢掉被判断为噪声的高频成分;
- tone mapping 把宽动态范围压到窄动态范围;
- clipping 把过曝区域截断;
- $Q_8$ 把 10 到 16 bit 的测量压到 8 bit;
- JPEG 压缩进一步丢弃高频信息。

如果 $y=H(r)$ 是从 RAW 到 JPEG 的确定性处理, 那么由数据处理不等式:

$$
I(x;y) \le I(x;r).
$$

也就是说, JPEG 不可能比 RAW 包含更多关于原始场景 $x$ 的信息。如果 $H$ 是非单射并且发生量化、裁剪、压缩, 这个不等式通常会严格成立。

这解释了一个看似朴素但非常重要的结论:

> 从 JPEG 恢复 RAW 或真实场景, 本质上比从 RAW 恢复最终图像更困难。

## Learned ISP 的问题形式

learned ISP 最直接的形式是学习一个函数:

$$
\hat{y} = F_{\theta}(r).
$$

给定训练集:

$$
\mathcal{D}=\{(r_i,y_i)\}_{i=1}^{N},
$$

经验风险最小化写成:

$$
\hat{\theta}
=
\arg\min_{\theta}
\frac{1}{N}
\sum_{i=1}^{N}
\mathcal{L}(F_{\theta}(r_i),y_i).
$$

这个式子看起来很普通, 但它有两个关键隐藏变量。

第一个是目标 $y_i$。它到底是什么?

- 可以是长曝光参考图像, 如低光恢复任务;
- 可以是手机厂商 ISP 输出;
- 可以是 DSLR 拍摄结果;
- 可以是 Lightroom/Adobe Camera Raw 调出的图;
- 可以是人类专家 retouch 结果;
- 也可以不是图像, 而是检测、分割等下游任务标签。

第二个是损失函数 $\mathcal{L}$。它决定了“好”的数学含义:

- L2 倾向高 PSNR;
- L1 倾向更稳健的像素中位数;
- MS-SSIM 倾向结构相似;
- perceptual loss 倾向特征空间相似;
- GAN loss 倾向输出落在自然图像分布上;
- task loss 倾向下游模型表现好。

所以 learned ISP 并没有在学习某种唯一正确的“真实照片”。它学习的是:

$$
\text{sensor measurement}
\longrightarrow
\text{target distribution under a chosen loss}.
$$

## Bayes 视角: 网络最优解到底是什么

为了看清数学本质, 不妨假设有无限数据和足够大的模型。若使用 L2 损失:

$$
\min_F \mathbb{E}\left[\|F(R)-Y\|_2^2\right],
$$

则最优解是条件期望:

$$
F^\ast(r)=\mathbb{E}[Y\mid R=r].
$$

推导很简单。固定 $R=r$, 要最小化:

$$
\mathbb{E}\left[\|a-Y\|_2^2 \mid R=r\right].
$$

对 $a$ 求导:

$$
\frac{\partial}{\partial a}
\mathbb{E}\left[\|a-Y\|_2^2 \mid R=r\right]
=
2(a-\mathbb{E}[Y\mid R=r]).
$$

令导数为 0, 得:

$$
a^\ast=\mathbb{E}[Y\mid R=r].
$$

这给 learned ISP 一个很清楚的解释:

> 用 L2 训练的 ISP 学到的是训练分布中给定 RAW 后目标图像的条件均值。

如果使用 L1 损失:

$$
\min_F \mathbb{E}\left[\|F(R)-Y\|_1\right],
$$

逐像素最优解会变成条件中位数。若使用负对数似然:

$$
\min_{\theta} -\mathbb{E}[\log p_{\theta}(Y\mid R)],
$$

模型学到的是条件分布 $p(Y\mid R)$。

这很关键。相机渲染不是单值问题。同一份 RAW 可以被渲染成偏暖、偏冷、高对比、低对比、保守肤色、夸张色彩等多种合理输出。设隐藏风格变量为 $u$, 则:

$$
Y = \rho_u(X).
$$

如果训练时不显式提供 $u$, 那么模型看到的是混合分布:

$$
p(Y\mid R=r)
=
\sum_u p(Y\mid R=r,u)p(u\mid r).
$$

L2 最优解会成为:

$$
F^\ast(r)
=
\sum_u p(u\mid r)\mathbb{E}[Y\mid R=r,u].
$$

也就是多种风格的平均。这解释了为什么像素级损失训练出的图像容易保守、发灰、细节偏软。不是网络“不懂审美”, 而是目标函数在数学上要求它输出平均解。

如果希望输出可控, 更合理的形式是:

$$
\hat{y}=F_{\theta}(r,u),
$$

或者直接建模:

$$
p_{\theta}(y\mid r,u).
$$

这也是 controllable ISP 或 image enhancement 工作的基本动机: 把风格、偏好或任务条件显式放进模型, 不要让它们混在不可见的数据分布里。

## RAW 低光恢复为什么和 JPEG 低光增强不是一回事

低光场景中, RAW 信号可以写成:

$$
r = \epsilon + n,
$$

其中 $\epsilon$ 是很小但仍可能存在的真实信号。若 RAW 是 14 bit, 那么它仍可能保留一些弱强度差异。

但 JPEG 输出是:

$$
y=Q_8(H(r)),
$$

其中 $H$ 是包含 tone mapping、gamma、压缩前处理等的 ISP 映射。若低光区域经过处理后低于一个量化阈值, 则:

$$
Q_8(H(r))=0
\quad
\text{for all } r\in [0,\delta).
$$

于是任意 $r_1,r_2\in[0,\delta)$ 都有:

$$
Q_8(H(r_1))=Q_8(H(r_2)).
$$

这说明许多不同的 RAW 输入在 JPEG 中变成完全相同的值。此时从 JPEG 恢复场景, 后验分布 $p(X\mid Y=0)$ 会非常宽。最优估计只能依赖自然图像先验, 而不是依赖输入中真实保留的信息。

所以低光 JPEG 增强更像:

$$
\hat{x}
=
\arg\max_x p(x\mid y_{jpeg})
\propto
p(y_{jpeg}\mid x)p(x),
$$

当 $p(y_{jpeg}\mid x)$ 提供的信息很少时, $p(x)$ 这个先验会主导结果。网络看起来是在“恢复”, 实际上很大程度上是在根据训练分布补全。

而低光 RAW 恢复更像:

$$
\hat{x}
=
\arg\max_x p(r_{raw}\mid x)p(x),
$$

其中 $p(r_{raw}\mid x)$ 仍然包含传感器测量信息。LSID 的价值就在这里: 它直接从低光 RAW 出发, 而不是从已经被 8 bit 量化和压缩损伤的 JPEG 出发。U-Net 是实现手段, RAW 域才是问题成立的关键。

可以把这个结论压成一句话:

> 当信息还留在 RAW 里时, 深度学习主要是在做带先验的恢复; 当信息已经在 JPEG 中丢掉时, 深度学习更多是在做基于先验的生成。

这也是为什么计算摄像学喜欢 RAW。RAW 不是更“高级”的文件格式而已, 它在数学上保留了更多关于场景和传感器测量的信息。

## Learned ISP 其实是 Bayes 决策问题

更完整地说, RAW 到最终图像可以拆成两个随机过程。

第一步是物理估计:

$$
p(x\mid r)
\propto
p(r\mid x)p(x).
$$

这里 $p(r\mid x)$ 是传感器观测模型, $p(x)$ 是自然图像或场景先验。传统算法往往显式写出某种 $p(x)$, 例如平滑先验、稀疏先验、非局部相似性、边缘模型等。深度学习则从数据里隐式学习这个先验。

第二步是渲染决策:

$$
y = \rho_u(x).
$$

其中 $u$ 代表显示设备、审美风格、相机厂商偏好或下游任务目标。

于是 learned ISP 的理想输出不是简单的 $x$, 而是:

$$
F^\ast(r,u)
=
\arg\min_{\hat{y}}
\mathbb{E}
\left[
\ell(\hat{y}, \rho_u(X))
\mid R=r
\right].
$$

这才是问题的数学本质:

> learned ISP 是在后验不确定性下, 面向某个渲染目标和损失函数做决策。

这个形式也解释了为什么不同论文看起来都在做 RAW-to-RGB, 但实际不是同一个问题。只要 $u$、$\ell$、训练数据分布或目标 $Y$ 不同, 学到的 ISP 就不是同一个 ISP。

## 为什么恢复和增强应该分开

传统 ISP 中的操作可以粗略分成两类。

第一类是 restoration:

$$
s = R_{\theta}(r).
$$

它的目标是恢复一个更干净、更完整、更接近线性场景的中间表示 $s$。典型任务包括去噪、去马赛克、坏点修复、白平衡和部分颜色校正。

第二类是 enhancement:

$$
y = E_{\psi}(s).
$$

它的目标是把 $s$ 渲染成适合观看或适合任务的输出。典型任务包括 tone mapping、gamma、对比度、饱和度、局部增强和风格调整。

如果把两者混成一个网络:

$$
y = F_{\theta}(r),
$$

理论上当然可行。但这样会把两类目标的梯度混在一起。恢复希望保留物理信号, 增强则有意改变信号; 恢复希望避免幻觉, 增强可能鼓励更讨喜的局部对比和色彩。两者并不总是方向一致。

两阶段方法可以写成:

$$
\hat{s}=R_{\theta}(r),
\quad
\hat{y}=E_{\psi}(\hat{s}),
$$

训练目标:

$$
\min_{\theta,\psi}
\mathcal{L}_{R}(R_{\theta}(r),s^\ast)
+
\mathcal{L}_{E}(E_{\psi}(R_{\theta}(r)),y^\ast).
$$

其中 $s^\ast$ 是线性恢复目标, $y^\ast$ 是最终增强目标。

从概率图模型看, 这是在假设:

$$
p(y,s\mid r)
=
p(y\mid s)p(s\mid r).
$$

也就是说, $s$ 是连接 RAW 和最终渲染图像的中间物理表示。这个假设不一定完美, 但它很有用: 它把“估计场景信号”和“渲染给人看”分成两个目标, 让网络结构和 ISP 物理结构对齐。

CameraNet 的意义就在这里。它不是简单说一个网络不够强, 所以堆两个网络; 它是在承认 ISP 内部存在两类性质不同的子问题: restoration 和 enhancement。

这给 learned ISP 一个很重要的设计原则:

> 如果一个步骤有明确的物理意义和解析形式, 不一定要交给网络; 如果一个步骤依赖复杂先验、主观偏好或任务目标, 学习才更有价值。

## 为什么不存在一个对所有任务都最优的 ISP

传统相机 ISP 默认优化的是人类观看质量:

$$
\min_{\phi}
\mathbb{E}
\left[
\mathcal{L}_{human}
(\mathrm{ISP}_{\phi}(R),Y_{photo})
\right].
$$

但如果图像不是给人看, 而是给检测器、分割器、三维重建算法或光度立体算法使用, 目标函数就变了。

例如目标检测可以写成:

$$
\min_{\phi}
\mathbb{E}
\left[
\mathcal{L}_{det}
(G(\mathrm{ISP}_{\phi}(R)),Z)
\right],
$$

其中 $G$ 是检测模型, $Z$ 是检测标签。

这两个目标不一定一致。对人好看的图像可能有平滑肤色、抑制噪声、增强局部对比; 但对机器来说, 某些被抹掉的纹理、边缘或线性亮度关系可能很重要。反过来, 给机器最优的 ISP 也可能输出一张人看起来奇怪的图。

所以更一般的 learned ISP 应写成:

$$
\hat{y}
=
F_{\theta}(r; \tau),
$$

其中 $\tau$ 是任务条件。若 $\tau=\text{human viewing}$, 输出应适合显示; 若 $\tau=\text{detection}$, 输出应服务于检测损失; 若 $\tau=\text{photometric stereo}$, 输出则应尽量保留线性光度关系。

这也是 ReconfigISP 的数学动机。设有一组候选 ISP 模块:

$$
\mathcal{M}=\{m_1,m_2,\ldots,m_K\}.
$$

一条 ISP pipeline 是模块的组合:

$$
F_{\alpha,\phi}
=
m_{\alpha_L,\phi_L}
\circ
\cdots
\circ
m_{\alpha_2,\phi_2}
\circ
m_{\alpha_1,\phi_1}.
$$

目标是:

$$
\min_{\alpha,\phi}
\mathbb{E}
\left[
\mathcal{L}_{task}
(G(F_{\alpha,\phi}(R)),Z)
\right]
+
\lambda C(\alpha,\phi).
$$

其中 $C$ 可以是计算量、延迟、能耗或模块复杂度。由于 $\alpha$ 是离散结构选择, ReconfigISP 使用可微代理和类似 NAS 的方法搜索模块组合。

这个推导给出一个很强的结论:

> ISP 不是中性的图像前处理。ISP 是任务目标的一部分。目标函数改变, 最优 ISP 也会改变。

## 端到端输出正确, 不代表内部模块可辨识

端到端 learned ISP 有一个解释性问题: 最终输出对了, 不等于内部学到了我们熟悉的 ISP 模块。

举一个简单例子。白平衡 $W$ 和颜色校正 $C$ 可以写成:

$$
y = CWx.
$$

如果只观察最终乘积:

$$
A = CW,
$$

那么分解 $A=CW$ 不一定唯一。存在许多 $C'$、$W'$ 满足:

$$
C'W' \approx CW.
$$

因此, 就算网络输出颜色正确, 也不能说明它内部真的学会了人类意义上的白平衡、颜色校正和 tone mapping。它可能学到了某种等效映射, 也可能学到了数据集捷径。

更一般地, 若:

$$
F_{\theta}: r\mapsto y,
$$

只用最终输出监督, 则网络内部表示有大量等价变换。只要整体函数接近目标, 中间层是否对应去噪、去马赛克、白平衡、颜色校正, 并没有被目标函数约束。

这就是 identifiability 问题。模块化 ISP 的优势不只是工程可控, 也是数学约束。它限制了假设空间:

$$
F \in \mathcal{F}_{modular}
\subset
\mathcal{F}_{all\ neural}.
$$

假设空间变小, 可能牺牲一部分表达能力, 但会换来:

- 更好的可解释性;
- 更少的数据需求;
- 更容易跨传感器迁移;
- 更容易定位失败原因;
- 更容易满足硬件延迟和功耗约束。

这也是为什么 learned ISP 不应该被粗暴理解为“用一个大网络替代所有相机工程”。更好的问题是: 哪些结构先验应该保留, 哪些步骤应该学习, 哪些目标应该显式条件化?

## 文献脉络: 它们其实在改变同一个优化问题

把相关工作放在同一个数学框架里, 会比按年代列论文更清楚。

### FlexISP: 从串联流程到联合优化

传统 ISP 是级联模块。FlexISP 指出这种 divide-and-conquer 会累积误差: 每一步只看上一步输出, 不再直接看原始传感器数据。它尝试把相机模型、自然图像先验和多种处理步骤放进一个端到端优化框架。用抽象形式写就是:

$$
\hat{x}
=
\arg\min_x
\|AMx-r\|^2
+
\lambda \Phi(x),
$$

再把输出映射到目标表示。这里 $\Phi(x)$ 是图像先验。它不是典型神经网络 ISP, 但它预示了一个思想: ISP 不必是每个步骤各管各的, 可以围绕最终目标联合求解。

### Deep Joint Demosaicking and Denoising: 早期模块耦合

去马赛克和去噪在数学上本来耦合。若先去马赛克再去噪, 噪声会被插值传播; 若先去噪再去马赛克, CFA 结构又会限制去噪判断。Deep Joint Demosaicking and Denoising 直接学习:

$$
F_{\theta}: r_{mosaic,noisy}\mapsto x_{rgb,clean}.
$$

它说明深度学习的一个优势是学习联合先验, 而不是手工拆成独立步骤。

### DeepISP 和 LSID: 端到端 learned pipeline

DeepISP 学习从低光 mosaiced RAW 到最终视觉图像的映射。它把低层任务, 如去马赛克和去噪, 与高层任务, 如颜色校正和图像调整, 放进一个端到端模型。

LSID 则在极低光场景中展示了 RAW 域的重要性。它的形式可以写成:

$$
\hat{y}
=
F_{\theta}
\left(
g\cdot \mathrm{pack}(r_{short}-b)
\right),
$$

其中 $g$ 是曝光补偿增益, `pack` 是把 Bayer RAW 的 $2\times2$ pattern 打包为多通道输入。目标是长曝光参考图像经过处理后的结果。

LSID 的核心不是“网络能看见黑暗”, 而是低光 RAW 仍有可恢复信息, 网络学到的是从弱信号和噪声中做后验估计。

### RISP/PyNET: target 变成 DSLR 风格

RISP/PyNET 的目标不是复现某个手机 ISP, 而是把手机 RAW 映射到 DSLR 拍摄的高质量 RGB:

$$
F_{\theta}(r_{phone})
\approx
y_{DSLR}.
$$

这改变了 learned ISP 的目标分布。网络学到的不只是 RAW-to-sRGB, 还包含手机传感器到 DSLR 风格的跨设备映射。它提醒我们: 数据集的配对方式本身就是问题定义。

### CameraNet: 分解 restoration 与 enhancement

CameraNet 把 ISP 分成两个相对弱相关的子问题:

$$
\hat{s}=R_{\theta}(r),
\quad
\hat{y}=E_{\psi}(\hat{s}).
$$

这对应前面说的概率分解 $p(y,s\mid r)=p(y\mid s)p(s\mid r)$。它的价值在于让网络结构尊重 ISP 的物理层次: 先恢复线性或近似线性的中间表示, 再做非线性增强。

### ReconfigISP: 从学习函数到学习管线

ReconfigISP 保留 ISP 模块库, 通过可微代理和结构搜索决定模块选择、参数和连接方式。它本质上是在解:

$$
\min_{\alpha,\phi}
\mathcal{L}_{task}(F_{\alpha,\phi}(r))
+
\lambda C(\alpha,\phi).
$$

这把 learned ISP 从“拟合一个 RAW-to-RGB 函数”推进到“为具体任务搜索一条成像管线”。

### Unprocessing, CycleISP, InvISP: 从反方向看 ISP

很多任务缺少 RAW 数据, 因此出现了从 sRGB 合成或恢复 RAW 的工作。

Unprocessing 试图按相反顺序近似逆转 ISP:

$$
\hat{r}=H^{-1}_{approx}(y).
$$

CycleISP 同时学习 forward ISP 和 reverse ISP, 用循环一致性生成更真实的合成训练对:

$$
r \xrightarrow{F} y,
\quad
y \xrightarrow{G} r,
\quad
G(F(r))\approx r,
\quad
F(G(y))\approx y.
$$

InvISP 则更进一步: 既然传统 ISP 不可逆, 那就设计一个可逆 ISP, 让 forward 过程得到好看的 sRGB, inverse 过程又能恢复 RAW。数学上它把 ISP 约束在可逆函数族里:

$$
y=f_{\theta}(r),
\quad
r=f_{\theta}^{-1}(y).
$$

这条线从反面证明了前面的结论: 标准 ISP 最大的问题之一就是信息损失。如果想事后拿回 RAW, 要么存额外信息, 要么近似反推, 要么从一开始就设计可逆流程。

## 再看理论文献: 它们怎样分析 learned ISP

如果把“理论工作”理解成不是简单提出一个新网络, 而是试图解释为什么某类解法成立, 相关文献大致可以分成五条线。它们共同指向一个判断: learned ISP 的核心不是 neural network, 而是如何定义观测模型、先验、信息损失和目标风险。

### ISP 先是逆问题, 不是普通图像到图像翻译

更理论的分析通常从观测模型开始。令 $x$ 表示理想的线性场景辐照或线性 RGB 图像, $M$ 表示 CFA 采样矩阵, $A$ 表示模糊、曝光、镜头衰减和传感器响应等线性近似, 则 RAW 可以写成:

$$
r = MAx + n.
$$

在真实传感器里, $n$ 不是简单的常方差高斯噪声。更接近 RAW 的模型是 Poisson-Gaussian 噪声:

$$
r_i = (MAx)_i + \epsilon_i,
\qquad
\mathrm{Var}(\epsilon_i\mid x)
\approx
\alpha (MAx)_i + \sigma_r^2.
$$

也就是说, 信号越强, shot noise 方差越大; 读出噪声又提供一个近似常量底噪。于是恢复问题的 MAP 形式是:

$$
\hat{x}
=
\arg\min_x
\frac{1}{2}
\|MAx-r\|_{\Sigma(x)^{-1}}^2
-
\log p(x).
$$

若把 $-\log p(x)$ 写成正则项 $\lambda\Phi(x)$, 就得到更常见的逆问题形式:

$$
\hat{x}
=
\arg\min_x
\frac{1}{2}
\|MAx-r\|_{\Sigma^{-1}}^2
+
\lambda\Phi(x).
$$

FlexISP 和 Khashabi 等人的随机场方法可以放在这个框架里理解 [1,13]: 它们不是把 RAW 直接当作普通输入图片, 而是显式利用相机观测模型、噪声模型和自然图像统计。差别只在于 $\Phi(x)$ 怎么来: 可以是手工先验、可学习随机场、非参数 patch 统计, 也可以是神经网络隐式表示的先验。

Plug-and-Play、RED 和 Deep Image Prior 这几类工作进一步把“先验”这件事抽象出来 [16-20]。以半二次分裂或 ADMM 为例:

$$
x^{k+1}
=
\arg\min_x
\frac{1}{2}\|MAx-r\|_{\Sigma^{-1}}^2
+
\frac{\rho}{2}
\|x-z^k+u^k\|^2,
$$

$$
z^{k+1}
=
\mathrm{prox}_{\lambda\Phi/\rho}(x^{k+1}+u^k).
$$

Plug-and-Play 的关键动作是把 proximal operator 换成一个去噪器:

$$
z^{k+1}
=
D_{\sigma}(x^{k+1}+u^k).
$$

这在 learned ISP 里很有启发: 一个去噪网络不只是“去噪模块”, 它也可以被看作自然图像先验的近似推理器。RED 则尝试把 denoiser 写进显式正则化中, 经典形式近似为:

$$
R_{RED}(x)
=
\frac{1}{2}x^\top(x-D(x)),
$$

在一定假设下, 其梯度可以写成 $x-D(x)$。后续 RED-PRO 等工作又提醒我们: denoiser 是否真的对应某个显式能量函数, 需要非扩张性、局部齐次性、固定点集合等条件。这一点对 learned ISP 很重要: 不是所有神经模块都天然等价于一个良定义的优化目标。

Deep Image Prior 的视角更极端。它不先写 $\Phi(x)$, 而是把待恢复图像重参数化为:

$$
x = f_{\theta}(z),
$$

再解:

$$
\hat{\theta}
=
\arg\min_\theta
\frac{1}{2}\|MAf_{\theta}(z)-r\|^2.
$$

这里先验来自网络结构和优化轨迹本身。放到 ISP 语境里, 这说明一个端到端 RAW-to-RGB 网络即使没有显式物理模块, 也仍然携带结构先验; 只是这种先验更难解释、更依赖架构和数据。

### 模块顺序本身是数学问题

去马赛克和去噪看上去只是两个模块的排序问题, 但理论文献把它写成非交换算子问题。令 $D_m$ 表示去马赛克算子, $D_n$ 表示去噪算子, 一般有:

$$
D_nD_m(r)
\ne
D_mD_n(r).
$$

原因不只是“先后顺序会影响效果”, 而是去马赛克会改变噪声分布。若把某个去马赛克步骤局部线性化为矩阵 $B$, CFA RAW 噪声为 $n\sim\mathcal{N}(0,\Sigma_n)$, 则去马赛克后的噪声为:

$$
n_{rgb}=Bn,
\qquad
\Sigma_{rgb}
=
B\Sigma_nB^\top.
$$

即使 RAW 噪声在像素上近似独立, 经过插值后也会变成空间相关、跨通道相关的 RGB 噪声。因此, 一个为 i.i.d. RGB 高斯噪声设计的去噪器, 在 demosaicked RGB 上其实已经模型失配。

Guo、Jin、Morel 和 Facciolo 关于 demosaicing/denoising 顺序的分析, 以及两阶段训练策略的论文, 都是在认真处理这个问题 [14,15]。它们得到的结论不是简单的“联合网络最好”。在中等噪声下, 先去马赛克、再使用适配后的 RGB 去噪器往往更合理; 在高噪声下, 先做部分 CFA 去噪、再去马赛克、再 RGB 去噪可能更有利。

这给 learned ISP 一个很有价值的推论: 模块化不是保守工程习惯, 而是一种关于噪声传播和条件独立性的建模选择。端到端网络当然可以学习这种顺序, 但如果没有显式约束, 它学到的是数据集内有效的等效映射, 不一定是跨相机、跨噪声水平稳定的推理结构。

### 可逆性决定 RGB-to-RAW 到底是“反变换”还是“估计”

传统 ISP 中的很多步骤都不是单射。黑电平裁剪、白点裁剪、tone mapping、gamma、量化和 JPEG 压缩都会把多个 RAW 状态映到同一个 RGB 值。只要存在:

$$
r_1\ne r_2,
\qquad
f(r_1)=f(r_2)=y,
$$

就不存在真正的 $f^{-1}(y)$。此时所谓 RGB-to-RAW 不是求逆, 而是求一个后验估计:

$$
p(r\mid y)
\propto
p(y\mid r)p(r).
$$

换句话说, learned reverse ISP 必须依赖先验 $p(r)$ 在多个可能 RAW 中选一个“合理”的解释。Unprocessing 和 CycleISP 属于近似反推 [8,9]; InvISP 的思路则是从设计上把 ISP 限制在可逆函数族里 [10]:

$$
y=f_\theta(r),
\qquad
r=f_\theta^{-1}(y).
$$

Model-Based ISP with Learnable Dictionaries 走的是中间路线 [21]: 它保留白平衡、颜色校正、gamma、lens shading 等可解释模块, 再用可学习字典表达内部参数。它的理论意味不是“又一个网络”, 而是把可逆性、可解释性和少样本学习放进同一个模型族里。

这里可以得到一个很硬的结论: 如果标准 ISP 已经把信息丢掉了, 再大的网络也不能凭空恢复唯一 RAW。网络能做的只是利用自然图像先验、相机先验和数据集偏差, 给出一个后验意义上的最可能解释。

### RAW 分布可以作为经验先验

All You Need is RAW 从对抗鲁棒性的角度提出了一个很有意思的观点 [24]: 自然 RGB 图像不是自然界直接给出的对象, 而是从 RAW CFA 观测经过 ISP 恢复出来的。于是 RAW 分布本身可以作为经验先验。

可以把这个思路写成一个投影过程。普通 RGB 图像 $y$ 可能来自真实相机管线:

$$
r \sim p_{RAW},
\qquad
y = f_{ISP}(r).
$$

若一个输入 $y'$ 含有不符合相机成像过程的扰动, 可以先映射到 RAW 空间, 再经 learned ISP 回到 RGB:

$$
y'
\xrightarrow{G_\psi}
\hat{r}
\xrightarrow{F_\theta}
\hat{y}.
$$

这个过程不是为了“复原真实 RAW”本身, 而是把图像重新约束到相机可生成的流形附近:

$$
\hat{y}
\in
F_\theta(\mathrm{supp}(p_{RAW})).
$$

这条线对 learned ISP 的启发是: RAW 不只是文件格式, 也是自然图像分布被相机物理过程约束后的表示。只在 sRGB 上做增强, 会丢掉很多关于 photon statistics、CFA 采样、光学模糊和传感器读出的结构信息。

### 任务最优 ISP: 目标函数决定成像前端

VisionISP、ISP4ML、hardware-in-the-loop ISP optimization 和 Neural Auto-Exposure 这条线讨论的是另一个理论问题 [22,23,25,26]: ISP 到底是为人眼优化, 还是为下游任务优化?

传统相机通常隐含地解:

$$
\min_{\phi}
\mathbb{E}
\left[
\mathcal{L}_{human}
\left(
ISP_\phi(R),Y
\right)
\right],
$$

其中 $Y$ 是好看的参考图、人类偏好或某种图像质量标准。但如果输出图像要给检测器、分割器或自动驾驶系统使用, 问题应该改写成:

$$
\min_{\phi,\theta}
\mathbb{E}_{(R,Z)}
\left[
\mathcal{L}_{task}
\left(
G_\theta(ISP_\phi(R)),Z
\right)
\right]
+
\lambda C(\phi).
$$

这里 $G_\theta$ 是下游模型, $Z$ 是任务标签, $C(\phi)$ 是功耗、带宽、延迟、bit-depth 或硬件实现成本。若真实 ISP 是黑箱、不可微或含有离散参数, hardware-in-the-loop 方法还会把它写成黑箱优化:

$$
\phi^\star
=
\arg\min_{\phi}
\mathbb{E}
\left[
\mathcal{L}_{task}(G_\theta(H_\phi(R)),Z)
\right],
$$

其中 $H_\phi$ 是真实硬件或硬件仿真管线。

Neural Auto-Exposure 甚至把曝光也纳入这个优化。此时曝光不再是拍摄前的辅助设置, 而是任务感知成像系统的一部分:

$$
e^\star
=
\arg\min_e
\mathbb{E}
\left[
\mathcal{L}_{det}
\left(
G_\theta(ISP_\phi(R(e))),Z
\right)
\right].
$$

这解释了前面那个结论: 不存在一个对所有目标都最优的 ISP。人眼喜欢的 tone mapping 未必保留检测器需要的暗部或高光特征; 最适合分类的压缩前端也未必适合摄影审美。

### 这些理论工作能归纳成同一个形式吗?

可以。它们都在修改下面这个决策问题的某一部分:

$$
\hat{u}
=
\delta^\star(r)
=
\arg\min_u
\mathbb{E}
\left[
\ell(u,S)
\mid R=r
\right].
$$

其中:

- $R$ 是传感器观测;
- $S$ 是我们真正关心但不可直接观测的状态, 可以是线性场景、好看的照片、RAW 后验、检测标签或三维结构;
- $u$ 是系统输出, 可以是 RGB 图像、可逆表示、下游特征或任务预测;
- $\ell$ 定义什么叫损失。

不同文献的区别, 可以归纳为五个选择:

1. 观测模型 $p(r\mid s)$: 是否显式建模 CFA、噪声、曝光、光学退化和传感器响应。
2. 先验 $p(s)$: 用自然图像统计、随机场、denoiser、网络结构、RAW 分布, 还是数据集监督来表达。
3. 推理结构 $\mathcal{F}$: 用端到端网络、模块化管线、两阶段网络、可逆网络、PnP/RED 迭代, 还是硬件黑箱搜索。
4. 输出变量 $u$: 输出给人看的 RGB, 还是给机器看的任务中间表示。
5. 损失函数 $\ell$: 优化 PSNR/SSIM、perceptual quality、后验概率、任务准确率、鲁棒性, 还是硬件成本。

这比“传统 ISP vs 深度学习 ISP”的二分法更准确。深度学习只是改变了先验和推理结构的表达能力; 它没有取消观测模型、信息损失和目标函数。真正的理论问题是: 对某个相机系统, 我们到底要估计什么状态, 在什么先验下估计, 又为谁承担损失?

### 那深度学习论文和这些理论是什么关系?

现在可以把前面的理论和深度学习 ISP 论文接起来了。它们不是两套互不相关的叙事。理论给出问题的坐标系; 深度学习论文是在这个坐标系里选择一个可训练的函数族, 再用数据把原本逐图求解的推理过程摊销掉。

传统逆问题通常是对每一张 RAW 单独求解:

$$
\hat{x}(r)
=
\arg\min_x
E(x;r)
=
\arg\min_x
\left[
\frac{1}{2}\|MAx-r\|_{\Sigma^{-1}}^2
+
\lambda\Phi(x)
\right].
$$

深度学习 ISP 则学习一个函数 $F_\theta$, 让它在数据分布上近似这个求解器:

$$
\theta^\star
=
\arg\min_\theta
\mathbb{E}_{(R,T)}
\left[
\ell(F_\theta(R),T)
\right].
$$

也就是说, $F_\theta(r)$ 不是凭空替代成像模型, 而是在学习一个 amortized inference map:

$$
F_\theta(r)
\approx
\delta^\star(r)
=
\arg\min_u
\mathbb{E}[\ell(u,S)\mid R=r].
$$

如果 $T=x$, 且损失是 L2, 最优网络逼近的是条件均值:

$$
F^\star(r)
=
\mathbb{E}[X\mid R=r].
$$

如果损失是 L1, 它更接近条件中位数。如果损失包含 perceptual loss、GAN loss 或下游 task loss, 那么网络逼近的就不再是“物理真实图像”的后验均值, 而是某个评价系统偏好的 Bayes 决策。这一点解释了为什么不同 learned ISP 论文看似都在做 RAW-to-RGB, 实际学到的东西却很不一样。

可以把这些论文放进下面这张对应表:

| 方法类型 | 深度学习论文在做什么 | 理论上改动了哪一项 |
| --- | --- | --- |
| Deep Joint Demosaicking and Denoising | 用 CNN 直接从 noisy mosaic RAW 估计 clean RGB | 把 demosaicing 与 denoising 的联合后验 $p(x\mid r)$ 摊销成一次前向传播; 隐式学习联合先验 $\Phi_\theta$ |
| DeepISP / LSID | 从低光 RAW 直接输出目标 RGB 或长曝光效果 | 学习 $\mathbb{E}[Y\mid R=r]$ 或相应 Bayes 决策; 数据中的曝光、噪声和参考图决定了目标变量 $S$ |
| RISP / PyNET | 把手机 RAW 映射到 DSLR 风格 RGB | 改变目标分布 $T$: 不是恢复物理真实, 而是学习跨设备、跨风格的条件映射 |
| CameraNet | 分成 restoration 与 enhancement 两阶段 | 在结构上引入潜变量 $S$, 近似 $p(y,s\mid r)=p(y\mid s)p(s\mid r)$, 降低不可辨识性 |
| ReconfigISP | 搜索模块、参数和连接方式 | 不只学习参数 $\theta$, 还学习假设空间 $\mathcal{F}_\alpha$, 同时加入成本约束 $C(\alpha,\phi)$ |
| Unprocessing / CycleISP | 学习或近似 sRGB-to-RAW 与 RAW-to-sRGB 的循环 | 把不可逆的 $p(r\mid y)$ 写成带先验的后验估计, 用循环一致性约束可行解 |
| InvISP | 设计可逆 RAW-to-RGB 映射 | 直接改变函数族: 要求 $f_\theta$ 是双射, 用结构约束减少信息丢失 |
| Model-Based ISP with Learnable Dictionaries | 保留可解释 ISP 模块, 学习模块参数字典 | 在端到端学习和物理模块之间折中: 缩小 $\mathcal{F}$, 换取可逆性、可解释性和少样本泛化 |
| VisionISP / ISP4ML / HIL ISP / Neural Auto-Exposure | 为检测、分类等下游任务优化 ISP 或曝光 | 改变损失函数 $\ell$ 和输出变量 $u$: ISP 不再为人眼图像质量服务, 而为任务风险服务 |

所以, 深度学习方法大致可以分成四种理论角色。

第一类是“摊销优化器”。Deep Joint Demosaicking、DeepISP 和 LSID 都可以这样理解。传统方法显式解一个 MAP/MMSE 问题; 神经网络把很多训练样本上的求解经验压进参数 $\theta$, 测试时直接输出估计。它快, 但代价是它的先验和噪声假设藏在数据与网络里。

第二类是“可学习先验”。PnP/RED 把 denoiser 当作先验或 proximal 近似; CNN ISP 则把更大的 RAW-to-RGB 推理过程做成一个隐式先验。两者的差别在于: PnP/RED 仍然保留 data fidelity 项, 所以观测模型还在优化循环里; 纯端到端 ISP 常常只保留训练损失, 因而更依赖数据覆盖。

第三类是“结构化假设空间”。CameraNet、ReconfigISP、InvISP 和 Model-Based ISP 都不是简单追求更大的网络, 而是在限制 $F_\theta$ 的形状。CameraNet 用两阶段结构表达 restoration/enhancement 分解; ReconfigISP 用模块图表达可搜索管线; InvISP 用可逆结构表达信息守恒; Model-Based ISP 用传统模块表达可解释性。理论上, 它们都是在选择一个更有偏置的 $\mathcal{F}$:

$$
F_\theta
\in
\mathcal{F}_{structured}
\subset
\mathcal{F}_{all}.
$$

这会牺牲一部分任意拟合能力, 但换来泛化、可解释性、可控性或硬件可部署性。

第四类是“重定义目标变量”。RISP/PyNET、VisionISP、ISP4ML、hardware-in-the-loop ISP 和 Neural Auto-Exposure 都在提醒我们: learned ISP 的输出不一定是“真实照片”。如果目标是 DSLR 风格, 网络学的是风格化 Bayes 决策; 如果目标是检测准确率, ISP 学的是任务充分表示; 如果目标是鲁棒性, RAW 分布就成了过滤不自然扰动的经验先验。

这也解释了一个容易误解的点: 深度学习论文的贡献常常不是“发现了更真实的 ISP”, 而是改变了下面某一项:

$$
\underbrace{p(r\mid s)}_{\text{观测模型}},
\quad
\underbrace{p(s)}_{\text{先验}},
\quad
\underbrace{\mathcal{F}}_{\text{可学习函数族}},
\quad
\underbrace{\ell}_{\text{损失}},
\quad
\underbrace{T}_{\text{监督目标}}.
$$

一旦这么看, 我们就能更冷静地读这些论文。问一个 learned ISP 方法好不好, 不应该只问 PSNR 高不高, 而应该问:

1. 它假设 RAW 中有哪些信息还可恢复?
2. 它的训练目标 $T$ 到底代表物理真实、相机风格、人类偏好, 还是任务标签?
3. 它把哪些先验显式写进模型, 又把哪些先验交给数据学习?
4. 它的结构约束会不会帮助跨传感器、跨噪声、跨曝光泛化?
5. 它有没有把不可逆信息丢失误写成可逆变换?

因此, 理论分析和深度学习论文之间的关系可以压缩成一句话:

> 理论告诉我们 learned ISP 在估计什么、损失什么、约束什么; 深度学习论文则是在不同数据、结构和任务目标下, 给这个估计问题构造可训练的近似求解器。

### 网络结构也是一种先验

还有一个更容易被忽略的问题: 很多 learned ISP 论文看上去只是在换神经网络结构。U-Net、pyramid network、two-stage network、cycle network、invertible network、reconfigurable pipeline, 表面上都是 architecture choice。那这些结构能不能被理论解释?

我的看法是: 可以, 但不要试图把每一层卷积都解释成某个传统 ISP 模块。那样会很牵强。更合适的解释是:

> 网络结构定义了可学习函数族 $\mathcal{F}_A$, 因而定义了 learned ISP 的隐式先验和推理策略。

设 $A$ 是某种 architecture, 它对应的函数族是:

$$
\mathcal{F}_A
=
\{F_\theta:\theta\in\Theta_A\}.
$$

训练 learned ISP 实际是在解:

$$
\hat{F}_A
=
\arg\min_{F\in \mathcal{F}_A}
\widehat{\mathbb{E}}_{(R,T)}
\left[
\ell(F(R),T)
\right].
$$

如果把所有可测函数里的最优解记为 $F^\star$, 把结构 $A$ 内部的最优解记为 $F_A^\star$, 那么可以把误差粗略分成两项:

$$
\mathcal{R}(\hat{F}_A)-\mathcal{R}(F^\star)
=
\underbrace{\mathcal{R}(F_A^\star)-\mathcal{R}(F^\star)}_{\text{结构偏差}}
+
\underbrace{\mathcal{R}(\hat{F}_A)-\mathcal{R}(F_A^\star)}_{\text{估计与优化误差}}.
$$

这个分解很有用。一个过于自由的网络, 结构偏差可能小, 但估计误差大: 它需要更多数据, 也更容易学到数据集捷径。一个过于受限的网络, 估计误差可能小, 但结构偏差大: 它无法表达真实 ISP 需要的非线性和上下文依赖。所谓“好结构”, 不是参数更多, 而是在这两项之间找到更适合成像问题的折中。

所以读这些结构时, 可以问一个更理论的问题:

> 这个 architecture 到底把哪些先验写进了 $\mathcal{F}_A$?

下面逐类看。

#### U-Net / encoder-decoder: 多尺度后验估计

LSID 和很多 RAW-to-RGB 网络会使用 U-Net 或 encoder-decoder。它的理论意义不是“图像任务常用 U-Net”, 而是 learned ISP 本来就同时需要局部和全局信息。

去马赛克、坏点修复、细节去噪依赖局部邻域; 白平衡、曝光补偿、色调映射、全局对比度又依赖整张图的统计。可以把隐藏变量粗略写成:

$$
G = (\text{exposure}, \text{white balance}, \text{tone}, \text{scene context}),
$$

局部待恢复信号写成 $S_p$。那么单个像素的输出并不是:

$$
y_p = f(r_p),
$$

而更接近:

$$
y_p
=
f(r_{\mathcal{N}(p)}, G).
$$

encoder 的作用是从整张 RAW 估计全局变量 $G$; decoder 的作用是把 $G$ 和局部证据合成输出; skip connection 则把高频空间细节绕过 bottleneck 直接传给重建端。用函数形式写:

$$
F_A(R)
=
D_\theta
\left(
E_\theta(R),
\{S_\theta^{(l)}(R)\}_{l=1}^L
\right),
$$

其中 $E_\theta(R)$ 是低分辨率全局表示, $S_\theta^{(l)}(R)$ 是不同尺度的 skip feature。

这对应一种隐式假设: 全局渲染决策可以被压缩到低维上下文里, 但局部纹理、边缘和 CFA 相位信息不能完全通过 bottleneck。对 RAW 来说, 这点尤其重要, 因为 demosaicing 和 denoising 都很依赖像素级结构。

所以 U-Net 的理论解释是:

> 它假设 ISP 后验 $p(Y\mid R)$ 可以分解为“全局渲染变量 + 局部恢复证据”的多尺度估计。

#### Pyramid / coarse-to-fine: 把 ISP 分成尺度问题

RISP/PyNET 这类 pyramid 结构更明确地把问题分到不同尺度。理论上, 它近似了一个多分辨率分解:

$$
Y
\approx
U_L Y_L
+
\sum_{l=0}^{L-1}
U_l \Delta_l,
$$

其中 $Y_L$ 是低分辨率的全局颜色、曝光和 tone 估计, $\Delta_l$ 是各尺度的细节修正。对应的网络可以理解为:

$$
F(R)
=
U_L F_L(R_{\downarrow L})
+
\sum_{l=0}^{L-1}
U_l
\Delta_l(R_{\downarrow l}, F_{l+1}).
$$

这和 ISP 的结构很贴合。颜色风格和曝光不需要在 full resolution 上决定; 去马赛克、锐化、纹理恢复却必须回到高分辨率。pyramid 的 inductive bias 是:

1. 低频决定全局外观;
2. 高频负责局部细节;
3. 后续高分辨率阶段只需要做 residual correction。

这能解释为什么 pyramid network 很适合手机 RAW 到 DSLR 风格图像的映射: DSLR 风格不仅是局部清晰度, 还包含全局颜色、动态范围和 tone curve。普通浅层局部 CNN 很难同时处理这些尺度。

#### Residual / refinement: 学习相对传统 ISP 的修正

很多 learned ISP 或 enhancement 模型并不是完全从零生成图像, 而是学一个 residual 或 refinement:

$$
F_\theta(R)
=
B(R)
+
\Delta_\theta(R),
$$

其中 $B$ 可以是简单传统 ISP、bilinear demosaicing、粗糙 RGB 或前一阶段输出。这个形式的理论含义是: 假设已有 baseline 已经接近目标, 网络只需要学习误差项。

如果目标写成:

$$
T = B(R)+\epsilon,
$$

那么直接学习 $T$ 的难度变成学习 $\epsilon$。当 $\epsilon$ 比 $T$ 更稀疏、更低幅度、更局部时, residual 结构会降低估计难度:

$$
\mathcal{F}_{res}
=
\{B+\Delta_\theta\}
\subset
\mathcal{F}_{all}.
$$

这是一种很明确的结构先验: 传统 ISP 或粗恢复结果不是被抛弃, 而是作为低频主解; 网络学习传统管线无法处理的非线性残差。

#### Two-stage network: 显式引入潜变量

CameraNet 这类两阶段结构可以被更干净地写成变分分解。设 $S$ 是中间物理状态, 例如 denoised/demosaicked linear RGB 或 clean sensor representation。端到端模型直接学:

$$
p(Y\mid R).
$$

两阶段模型则假设:

$$
p(Y,S\mid R)
=
p(Y\mid S)p(S\mid R).
$$

对应的网络是:

$$
\hat{S}=R_\theta(R),
\qquad
\hat{Y}=E_\psi(\hat{S}).
$$

如果训练时对 $\hat{S}$ 也有约束, 例如 linear RGB loss、颜色一致性、噪声约束, 那么这个结构会减少不可辨识性。端到端网络只需要最后图像对, 它可以用很多内部捷径达成相似输出; 两阶段网络则强迫中间表示更接近某个物理状态。

这可以看作在优化:

$$
\min_{\theta,\psi}
\mathcal{L}_{render}(E_\psi(R_\theta(R)),Y)
+
\lambda
\mathcal{L}_{latent}(R_\theta(R),S).
$$

它的理论意义是: 用潜变量 $S$ 把 restoration 和 enhancement 分开。这个结构不是单纯“堆两个网络”, 而是在告诉模型: 先估计较客观的信号, 再做较主观的渲染。

#### Cycle / reverse ISP: 约束不可观测的后验

Unprocessing 和 CycleISP 面对的是另一个问题: 从 sRGB 反推 RAW。由于标准 ISP 不可逆, $p(R\mid Y)$ 通常是多峰的:

$$
p(R\mid Y=y)
\not=
\delta(R-r^\star).
$$

也就是说, 一个 RGB 可以对应很多可能 RAW。Cycle 结构不能让不可逆问题真的可逆, 但它能排除一部分不自洽的解。设 forward ISP 是 $F$, reverse ISP 是 $G$, cycle loss 是:

$$
\mathcal{L}_{cyc}
=
\|G(F(R))-R\|
+
\|F(G(Y))-Y\|.
$$

这相当于在后验估计中加入一致性约束:

$$
\hat{R}
=
\arg\max_R
\log p(Y\mid R)
+
\log p(R)
-
\lambda
d(F(R),Y).
$$

因此, CycleISP 的理论角色不是“学会真实逆 ISP”, 而是把 reverse ISP 的可行解限制在与 forward ISP 互相一致的子空间里。

#### Invertible network: 把信息保留写进函数族

InvISP 更强。它不满足于 cycle consistency, 而是直接要求:

$$
Y=f_\theta(R),
\qquad
R=f_\theta^{-1}(Y).
$$

若忽略量化和数值误差, 这意味着:

$$
H(R\mid Y)=0,
\qquad
I(R;Y)=H(R).
$$

这和传统 ISP 的信息损失形成对照。传统 sRGB 因为 clipping、tone mapping、gamma、8-bit 量化和压缩, 往往满足:

$$
H(R\mid Y)>0.
$$

Invertible architecture 的 inductive bias 是: 输出图像不仅要好看, 还必须保留足够信息以恢复 RAW。它牺牲了一部分普通 RGB pipeline 的自由度, 换来可逆性和信息守恒。

这里也有一个边界: 如果最终文件仍然是普通 8-bit JPEG, 完整可逆当然不可能。可逆 ISP 往往需要更高维表示、隐藏通道、side information 或特殊编码方式。理论上它解决的是函数族的可逆性, 不是魔法般取消量化损失。

#### Reconfigurable / NAS: 学习假设空间本身

ReconfigISP 这类方法比固定网络更进一步。它不是只在一个 $\mathcal{F}_A$ 里学参数, 而是在多个结构之间选择:

$$
\mathcal{F}
=
\bigcup_{\alpha\in\mathcal{A}}
\mathcal{F}_\alpha.
$$

其中 $\alpha$ 可以表示模块选择、连接方式、执行顺序或模块参数。目标函数变成:

$$
\min_{\alpha,\theta}
\mathbb{E}
\left[
\ell(F_{\alpha,\theta}(R),T)
\right]
+
\lambda C(\alpha,\theta).
$$

这对应一个很清楚的理论观点: learned ISP 不只是在学习一个函数, 也在学习哪种管线结构对当前传感器、目标和算力预算最合适。传统 ISP 中“模块顺序是否合理”的问题, 在这里被写成了结构搜索问题。

#### Task-aware / modulation: 学习条件化决策规则

VisionISP、ISP4ML、TA-ISP、RAM 这类方法把 ISP 目标从人类视觉质量改成任务表现。结构上常见的是 modulation、parallel branch 或轻量可调模块。理论上, 它们不是普通的:

$$
Y=F_\theta(R),
$$

而更接近条件化决策规则:

$$
Z_\tau
=
F_\theta(R,\tau,m),
$$

其中 $\tau$ 是任务, $m$ 是相机 metadata 或场景状态。目标是:

$$
\min_{\theta,\phi}
\mathbb{E}
\left[
\ell_\tau
\left(
G_{\phi,\tau}(F_\theta(R,\tau,m)),
Y_\tau
\right)
\right]
+
\lambda C(F_\theta).
$$

这种结构的先验是: 不同任务不需要同一个 sRGB 图像, 而需要不同的任务充分表示。parallel branch 可以理解为同时保留多种图像统计: 有的分支偏低频亮度, 有的偏局部边缘, 有的偏高动态范围。modulation 则是在不同图像区域或尺度上自适应选择处理强度。

这和前面 Bayes 决策视角完全一致。若任务不同, 损失函数 $\ell_\tau$ 不同, 最优输出也就不同:

$$
\delta_\tau^\star(r)
=
\arg\min_u
\mathbb{E}
[
\ell_\tau(u,S)
\mid R=r
].
$$

所以 task-aware architecture 的理论角色是: 把“没有通用最优 ISP”这件事写进网络结构。

#### 怎么读 learned ISP 的 architecture?

因此, 看到一篇 learned ISP 论文换了一个网络结构, 我们可以不急着问“这个结构是不是更先进”, 而是按下面的顺序读:

1. 它的 receptive field 假设是什么? 它认为 ISP 主要依赖局部邻域, 还是需要全局场景统计?
2. 它有没有显式潜变量? 如果有, 这个潜变量是物理状态、渲染风格, 还是任务表示?
3. 它是否保留信息? 是普通 many-to-one RGB, cycle consistency, 还是严格 invertible?
4. 它是否引入尺度分解? 低频颜色和高频细节是否被分开处理?
5. 它是否是 task-conditioned? 输出是给人看的图, 还是给某个下游模型的充分表示?
6. 它的约束是什么? 速度、延迟、功耗、bit-depth、模块可解释性, 还是跨相机泛化?

这样一来, “换网络结构”就不再是杂乱的工程选择, 而是不同理论偏置的显式化。可以把它们归纳成一张表:

| 结构 | 写进 $\mathcal{F}_A$ 的先验 | 对 learned ISP 的含义 |
| --- | --- | --- |
| U-Net / encoder-decoder | 全局上下文 + 局部细节 | 同时估计曝光/色调和像素级恢复 |
| Pyramid / coarse-to-fine | 多尺度分解 | 低频决定颜色风格, 高频恢复纹理 |
| Residual / refinement | baseline 已接近目标 | 网络学习传统 ISP 的误差项 |
| Two-stage | 存在中间物理潜变量 $S$ | 分开 restoration 和 enhancement |
| Cycle / reverse ISP | forward/reverse 一致性 | 在不可逆后验中选择自洽 RAW |
| Invertible network | 信息保留 / 双射约束 | 尽量避免 RAW 到 RGB 的信息损失 |
| Reconfigurable pipeline | 管线结构可学习 | 搜索模块顺序、参数和成本折中 |
| Task-aware modulation | 目标条件化 | 为任务风险而不是人眼 RGB 优化 |

这也是为什么我觉得“architecture”应该被放进理论分析里。它不是附属实现细节, 而是 learned ISP 的核心假设之一:

$$
\text{architecture}
\quad
\Longleftrightarrow
\quad
\text{implicit prior}
\quad
\Longleftrightarrow
\quad
\text{which Bayes decision can be efficiently approximated}.
$$

当我们说某个 neural ISP 结构有效时, 更准确的说法应该是: 它选择的函数族 $\mathcal{F}_A$ 与这个成像任务的观测模型、先验、损失函数和计算约束更匹配。

### CNN、Transformer、Diffusion、Flow Matching: 它们到底在建模什么?

进一步说, CNN、Transformer、Diffusion 和 Flow Matching 不只是四种“网络架构”。它们在数学上对应的是四种不同的建模对象:

| 方法 | 数学对象 | 在 learned ISP 中的角色 |
| --- | --- | --- |
| CNN / U-Net | 局部、平移等变的确定性算子 | 快速近似 MAP/MMSE, 适合去噪、去马赛克和局部恢复 |
| Transformer | 内容自适应的非局部核 | 建模全局颜色、长程依赖、自相似纹理和场景条件 |
| Diffusion | 条件分布的 score / reverse process | 从 $p(Y\mid R)$ 采样, 处理多解、纹理和感知质量 |
| Flow Matching | 条件分布之间的连续输运 ODE | 学习 RAW/RGB/latent 之间的向量场, 更像快速可控的生成式域变换 |

这四者的区别, 可以从同一个问题出发:

$$
R \sim p(r\mid S),
\qquad
Y \sim p(y\mid S,u),
$$

其中 $R$ 是 RAW 观测, $S$ 是不可见场景状态, $u$ 是渲染风格、相机偏好或任务目标。learned ISP 想得到的不是一个抽象的“好图像”, 而是某个条件决策:

$$
\delta^\star(r)
=
\arg\min_{\hat{y}}
\mathbb{E}
[
\ell(\hat{y},Y)
\mid R=r
].
$$

不同结构的差别在于: 它们用什么方式近似 $\delta^\star(r)$ 或 $p(Y\mid R=r)$。

#### CNN / U-Net: 局部 Markov 先验和快速摊销推理

CNN 的基本算子是卷积:

$$
h_{l+1}(p)
=
\sigma
\left(
\sum_{q\in\mathcal{K}}
W_l(q)h_l(p+q)
+b_l
\right).
$$

这个形式有两个很强的先验。

第一, 它是局部的。输出 $h_{l+1}(p)$ 主要依赖邻域 $\mathcal{N}(p)$。这和许多 ISP 子问题吻合: demosaicing 看 Bayer 邻域, denoising 看局部纹理与边缘, sharpening 看局部频率。

第二, 它是平移等变的:

$$
F(T_aR)
=
T_aF(R).
$$

也就是说, 同一种边缘、纹理和 CFA pattern 无论出现在图像哪个位置, 处理规则都应相同。这对传感器网格上的局部恢复非常合理。

从先验角度看, CNN 很像在学习一个局部能量函数或局部后验估计:

$$
\Phi(x)
\approx
\sum_p
\phi_\theta(x_{\mathcal{N}(p)}),
$$

并把逐图优化:

$$
\hat{x}
=
\arg\min_x
\|MAx-r\|^2
+
\lambda\Phi(x)
$$

摊销成一次前向传播:

$$
\hat{x}
\approx
F_\theta(r).
$$

U-Net 在 CNN 上加了多尺度 encoder-decoder 和 skip connection。它并没有改变“局部恢复”的根基, 但补上了 CNN 原本较弱的全局上下文。可以把 U-Net 写成:

$$
F_{\theta}(R)
=
D_\theta
\left(
E_\theta(R),
\{S_\theta^{(l)}(R)\}_{l=1}^L
\right).
$$

这里 $E_\theta(R)$ 估计曝光、白平衡、场景亮度等全局变量; $S_\theta^{(l)}(R)$ 保留不同尺度的局部细节。对 learned ISP 来说, U-Net 的理论角色是:

> 用一个多尺度、平移等变的函数族, 快速近似 RAW 条件下的 Bayes 点估计。

它的弱点也很清楚: 如果颜色风格依赖全局语义, 或者纹理恢复需要很远位置的自相似结构, 纯 CNN 的固定局部核会比较吃力。

#### Transformer: 内容自适应的非局部成像算子

Transformer 的核心是 self-attention。把图像分成 token 后, 每个位置 $i$ 的输出是:

$$
h_i'
=
\sum_j
A_{ij}v_j,
$$

其中:

$$
A_{ij}
=
\frac{
\exp(q_i^\top k_j/\sqrt{d})
}{
\sum_{j'}
\exp(q_i^\top k_{j'}/\sqrt{d})
}.
$$

这和卷积有根本区别。卷积核 $W(q)$ 通常只依赖相对位置; attention 权重 $A_{ij}$ 依赖图像内容。于是 Transformer 可以被看成一种内容自适应的非局部滤波:

$$
h_i'
=
\sum_j
K_\theta(R;i,j)h_j.
$$

这个形式和传统图像处理里的 non-local means 有相似味道: 若两个区域内容相似, 即使距离很远, 也可以互相提供信息。对 ISP 来说, 这特别适合几件事:

1. 全局白平衡和颜色恒常性: 颜色判断可能需要整张图的统计。
2. 重复纹理恢复: 远处相似 patch 可以帮助当前区域去噪和补细节。
3. HDR / tone mapping: 局部压缩需要知道全局亮度分布。
4. 任务感知 ISP: 某些语义区域, 如天空、皮肤、车灯, 应有不同处理偏好。

问题是标准 attention 的复杂度是:

$$
O(N^2),
$$

而 RAW 图像的 $N$ 很大。因此 SwinIR、Uformer、Restormer 这类低层视觉 Transformer 都在做同一个折中: 保留非局部或内容自适应能力, 但用 window attention、hierarchical encoder-decoder、channel attention 或高效 feed-forward block 控制成本 [27-29]。

理论上, Transformer 不是简单替代 CNN, 而是在改变假设空间:

$$
\mathcal{F}_{CNN}
\subset
\mathcal{F}_{local},
\qquad
\mathcal{F}_{Transformer}
\subset
\mathcal{F}_{content\ adaptive}.
$$

CNN 假设相同局部 pattern 用相同规则处理; Transformer 允许处理规则随整张图内容改变。对 learned ISP 来说, 这意味着:

> Transformer 把 ISP 从“固定局部滤波器”推进到“内容自适应的非局部估计器”。

但它也有代价: 更高的算力、更强的数据需求, 以及可能更弱的物理可解释性。

#### Diffusion: 从点估计变成条件后验采样

CNN 和 Transformer 通常学习一个确定性映射:

$$
\hat{y}
=
F_\theta(r).
$$

Diffusion 的建模对象不同。它关心的是整个条件分布:

$$
p_\theta(y\mid r).
$$

对 ISP 来说, 这很自然。因为同一个 RAW 可以有多种合理渲染: 偏暖或偏冷, 高对比或低对比, 保守降噪或保留颗粒, 甚至在反向 RGB-to-RAW 中有多个可能 RAW 解释。

DDPM/score-based diffusion 的 forward process 可以写成:

$$
q(y_t\mid y_0)
=
\mathcal{N}
\left(
\alpha_t y_0,
\sigma_t^2 I
\right).
$$

训练时学习噪声或 score:

$$
\min_\theta
\mathbb{E}_{y_0,r,t,\epsilon}
\left[
\left\|
\epsilon
-
\epsilon_\theta(y_t,t,r)
\right\|^2
\right],
$$

等价地, 学习:

$$
s_\theta(y_t,t,r)
\approx
\nabla_{y_t}\log p_t(y_t\mid r).
$$

生成时从噪声出发, 沿 reverse SDE 或 probability-flow ODE 回到图像分布 [30,31]:

$$
dy
=
\left[
f(y,t)
-
g(t)^2
\nabla_y\log p_t(y\mid r)
\right]dt
+
g(t)d\bar{w}_t.
$$

因此, diffusion ISP 的理论角色不是“更大的 U-Net”, 而是:

> 用一个生成式后验 $p_\theta(Y\mid R=r)$ 替代单点回归。

这能解释为什么 diffusion 适合补纹理、低光细节和感知质量。L2 回归倾向输出条件均值:

$$
\mathbb{E}[Y\mid R=r],
$$

当后验多峰时, 条件均值会过平滑。Diffusion 则可以从不同模态采样:

$$
y^{(k)}
\sim
p_\theta(Y\mid R=r).
$$

但这也带来风险。ISP 不是纯生成任务, RAW 是真实测量。若 diffusion prior 太强, 它可能生成“看起来合理但传感器并未测到”的纹理。更严格的写法应该是后验:

$$
p(y\mid r)
\propto
p(r\mid y)p(y).
$$

于是 inverse-problem diffusion / posterior sampling 会把 score 分成两项:

$$
\nabla_y\log p(y\mid r)
=
\nabla_y\log p(y)
+
\nabla_y\log p(r\mid y).
$$

前一项来自自然图像 diffusion prior, 后一项来自相机观测模型。DDRM、DPS 等工作就是在尝试把 diffusion prior 和测量一致性结合起来 [32,33]。对 learned ISP 来说, 这给出一个重要判断:

> Diffusion 很适合表达“多种可能输出”, 但必须被 RAW likelihood、颜色一致性、噪声模型或物理 forward model 约束, 否则容易从恢复滑向幻觉。

最近的 ISPDiffuser、RAW-Diffusion、DarkDiff 等工作正是在 RAW-to-sRGB、RGB-to-RAW 或低光 RAW enhancement 中利用 diffusion 的生成先验 [37,38]。它们的共同动机是: 回归式 ISP 容易平滑和颜色漂移, diffusion 可以更好地建模细节分布。但它们也必须额外处理颜色一致性、RAW 条件注入和物理测量约束。

#### Flow Matching: 把 ISP 看成分布输运

Flow Matching 和 diffusion 关系很近, 但数学对象不完全一样。它不先定义随机反向去噪过程, 而是学习一个连续时间向量场:

$$
\frac{dz_t}{dt}
=
v_\theta(z_t,t,r).
$$

这个 ODE 把一个简单分布 $p_0$ 运输到目标分布 $p_1(\cdot\mid r)$:

$$
z_0\sim p_0,
\qquad
z_1\sim p_1(\cdot\mid r).
$$

概率密度满足连续性方程:

$$
\partial_t p_t(z\mid r)
+
\nabla\cdot
\left(
p_t(z\mid r)v_t(z\mid r)
\right)
=
0.
$$

Flow Matching 的训练目标是直接回归某条 probability path 的速度场 [34]:

$$
\min_\theta
\mathbb{E}_{t,z_t,r}
\left[
\|v_\theta(z_t,t,r)-u_t(z_t\mid z_0,z_1,r)\|^2
\right].
$$

最简单的 rectified flow 使用直线路径 [35]:

$$
z_t
=
(1-t)z_0+t z_1,
\qquad
u_t
=
z_1-z_0.
$$

于是模型学的是:

$$
v_\theta(z_t,t,r)
\approx
z_1-z_0.
$$

它和 diffusion 的区别可以这样理解:

- Diffusion 学 score: “在当前噪声尺度下, 往哪里去更像数据?”
- Flow Matching 学 velocity: “沿着一条输运路径, 当前点应该以什么速度移动?”

在 learned ISP 中, Flow Matching 很自然, 因为 ISP 本来就是域变换:

$$
\text{RAW distribution}
\longrightarrow
\text{sRGB distribution},
$$

或反过来:

$$
\text{sRGB distribution}
\longrightarrow
\text{RAW distribution}.
$$

如果我们在 latent space 中编码 RAW 和 RGB:

$$
z_R=E_R(R),
\qquad
z_Y=E_Y(Y),
$$

那么 RGB-to-RAW 或 RAW-to-sRGB 可以被写成 latent transport:

$$
\frac{dz_t}{dt}
=
v_\theta(z_t,t,\text{condition}),
\qquad
z_0=z_Y,
\quad
z_1=z_R.
$$

这正是 RAW-Flow 这类近期工作的关键思路: RGB-to-RAW 不是一个普通回归问题, 因为标准 ISP 丢失了信息; 可以把它改写为 latent space 中的确定性 flow matching, 学习从 RGB 表示到 RAW 表示的输运向量场 [39]。

Flow Matching 对 ISP 的吸引力在于:

1. 它保留生成模型的分布建模能力;
2. 采样通常可以比 diffusion 少步;
3. ODE 形式更适合 deterministic mapping 和可控部署;
4. 对 paired RAW/RGB 数据, 直线路径或 OT path 很容易构造;
5. 对 reverse ISP, latent transport 比像素回归更能表达 ill-posedness。

但它也不是银弹。如果 RGB-to-RAW 本来是多解的, deterministic flow 只能在某个 coupling 下选择一种解释。更完整的模型应该保留条件分布:

$$
R
\sim
p_\theta(R\mid Y),
$$

或者在 latent flow 中引入随机初值:

$$
z_0
\sim
p_0(z\mid Y),
\qquad
z_1
=
\mathrm{Flow}_\theta(z_0;Y).
$$

也就是说, Flow Matching 给了我们一个非常漂亮的数学语言: ISP 不只是函数拟合, 也可以是从一个条件分布到另一个条件分布的输运问题。

#### 这四类结构怎么选择?

如果把 learned ISP 目标写成:

$$
\hat{y}
\sim
p_\theta(Y\mid R=r),
$$

那么四种结构对应四种近似层级:

| 结构 | 近似对象 | 适合场景 | 主要风险 |
| --- | --- | --- | --- |
| CNN / U-Net | Bayes 点估计 $\delta^\star(r)$ | 实时 ISP、去噪、去马赛克、移动端 | 全局语义和长程依赖弱 |
| Transformer | 内容自适应点估计或表示 | 全局颜色、HDR、复杂纹理、任务感知前端 | 算力高, 数据需求大 |
| Diffusion | 条件后验 $p(Y\mid R)$ | 多解渲染、低光细节、感知质量、逆问题采样 | 慢, 可能幻觉, 需要物理约束 |
| Flow Matching | 条件分布输运 ODE | 快速生成式 ISP、RAW/RGB latent translation、reverse ISP | coupling 选择敏感, 多解性需额外建模 |

因此, 这几类方法不是简单的竞品关系。更像是不同层级的理论选择:

$$
\text{CNN}
\rightarrow
\text{Transformer}
\rightarrow
\text{Diffusion}
\rightarrow
\text{Flow Matching}
$$

并不是越往右越好, 而是建模对象越来越从“点估计”走向“分布输运”。如果目标是手机相机实时出图, CNN/U-Net 或轻量 Transformer 可能最合适; 如果目标是低光照片的感知质量, diffusion 更有意义; 如果目标是 RGB-to-RAW、RAW-to-sRGB 的生成式域转换, flow matching 会变得非常自然。

把它压缩成一句话:

> CNN 和 Transformer 主要在学习 $F_\theta:R\mapsto Y$; Diffusion 在学习 $p_\theta(Y\mid R)$; Flow Matching 在学习把一个条件分布连续运输到另一个条件分布的向量场。

## 一个统一形式

这些工作表面上差异很大, 但可以统一成:

$$
\hat{F}
=
\arg\min_{F\in\mathcal{F}}
\mathbb{E}_{(R,T)}
\left[
\mathcal{L}
\left(
A_{\tau}(F(R)), T
\right)
\right]
+
\lambda \Omega(F).
$$

其中:

- $R$ 是 RAW 或中间图像;
- $F$ 是 ISP, 可以是端到端网络、两阶段网络、模块图、可逆网络或传统优化管线;
- $\mathcal{F}$ 是假设空间, 决定可解释性和表达能力;
- $A_{\tau}$ 是任务头, 可以是显示、JPEG 压缩、检测器、分割器或评价模型;
- $T$ 是目标, 可以是长曝光图、DSLR 图、人类 retouch 图或任务标签;
- $\mathcal{L}$ 定义什么叫好;
- $\Omega(F)$ 约束速度、可逆性、平滑性、模块成本、颜色一致性或硬件实现。

于是 learned ISP 的关键选择不是“用哪个网络”, 而是五个问题:

1. 输入域是什么: RAW、packed RAW、linear RGB, 还是 sRGB?
2. 目标是什么: 保真、好看、像某个相机, 还是有利于下游任务?
3. 损失函数是什么: L1/L2、perceptual、GAN、task loss, 还是 NLL?
4. 结构先验是什么: 端到端、两阶段、模块化、可逆, 还是可重构?
5. 数据分布是什么: 哪个传感器、哪个镜头、哪个曝光范围、哪个 ISP 风格?

如果不回答这些问题, “深度学习建模 ISP”就会变成一句空话。

## 我得到的结论

第一, learned ISP 不是简单的图像增强。它是一个从传感器观测出发, 在不确定性下做恢复和渲染决策的问题。

第二, RAW 和 JPEG 的差别是信息论层面的差别。RAW 保留了更接近物理测量的线性高 bit-depth 数据; JPEG 是经过非线性、量化和压缩后的显示结果。低光 RAW 恢复和低光 JPEG 增强不是同一个问题。

第三, 用监督学习训练出的 ISP 不是“真实 ISP”, 而是某个数据集、目标和损失函数下的 Bayes 决策器。目标来自 Canon DSLR, 它就学 Canon 风格; 目标来自长曝光, 它就学长曝光恢复; 目标来自人类修图, 它就学人的偏好。

第四, restoration 和 enhancement 应该被区分。前者面向物理信号恢复, 后者面向显示、审美或任务目标。把二者全塞进黑箱可以工作, 但会失去结构解释, 也容易混淆目标。

第五, 不存在一个对所有任务最优的 ISP。给人看的图像、给检测器看的图像、给三维重建用的图像, 可能需要不同的前端处理。ISP 是任务定义的一部分, 不是中性的预处理。

第六, 深度学习没有让成像模型变得不重要。恰恰相反, 越要学习 ISP, 越需要知道哪些信息在 RAW 中, 哪些信息在 JPEG 中已经丢失, 哪些步骤有明确物理意义, 哪些步骤是主观渲染, 哪些目标会引入幻觉。

第七, 网络结构不是附属实现细节。U-Net、pyramid、two-stage、cycle、invertible、reconfigurable 或 task-aware modulation, 都是在选择不同的函数族 $\mathcal{F}_A$。它们把多尺度性、潜变量分解、信息保留、可逆性、任务条件化和硬件成本写进 learned ISP 的假设空间。换结构, 本质上是在换一种隐式先验。

第八, CNN、Transformer、Diffusion 和 Flow Matching 对 learned ISP 的建模层级不同。CNN/U-Net 更像快速的 Bayes 点估计; Transformer 把处理规则变成内容自适应的非局部核; Diffusion 建模条件后验 $p(Y\mid R)$; Flow Matching 则把 RAW、RGB 或 latent 表示之间的关系写成连续分布输运。它们不是简单替代关系, 而是在点估计、条件分布和概率流之间选择不同数学对象。

如果把这篇文章压缩成一句话, 我会写:

> learned ISP 的本质, 是把相机内部从 RAW 到图像的工程流水线, 重新表述为一个带物理观测模型、自然图像先验、渲染偏好和任务损失的 Bayes 决策问题。

这也是它最有意思的地方。它不是让相机“更会修图”, 而是逼我们重新定义: 对一个相机系统来说, 什么才是值得输出的图像?

## 参考文献

[1] Heide, F., Steinberger, M., Tsai, Y.-T., et al. FlexISP: A Flexible Camera Image Processing Framework. SIGGRAPH Asia 2014. <https://research.nvidia.com/publication/2014-12_flexisp-flexible-camera-image-processing-framework>

[2] Gharbi, M., Chaurasia, G., Paris, S., & Durand, F. Deep Joint Demosaicking and Denoising. SIGGRAPH Asia 2016. <https://groups.csail.mit.edu/graphics/demosaicnet/>

[3] Schwartz, E., Giryes, R., & Bronstein, A. M. DeepISP: Toward Learning an End-to-End Image Processing Pipeline. IEEE Transactions on Image Processing, 2019. <https://arxiv.org/abs/1801.06724>

[4] Chen, C., Chen, Q., Xu, J., & Koltun, V. Learning to See in the Dark. CVPR 2018. <https://arxiv.org/abs/1805.01934>

[5] Ignatov, A., Van Gool, L., & Timofte, R. Replacing Mobile Camera ISP with a Single Deep Learning Model. CVPR Workshops 2020. <https://openaccess.thecvf.com/content_CVPRW_2020/papers/w31/Ignatov_Replacing_Mobile_Camera_ISP_With_a_Single_Deep_Learning_Model_CVPRW_2020_paper.pdf>

[6] Liang, Z., Cai, J., Cao, Z., & Zhang, L. CameraNet: A Two-Stage Framework for Effective Camera ISP Learning. IEEE Transactions on Image Processing, 2021. <https://arxiv.org/abs/1908.01481>

[7] Yu, K., Li, Z., Peng, Y., Loy, C. C., & Gu, J. ReconfigISP: Reconfigurable Camera Image Processing Pipeline. ICCV 2021. <https://openaccess.thecvf.com/content/ICCV2021/papers/Yu_ReconfigISP_Reconfigurable_Camera_Image_Processing_Pipeline_ICCV_2021_paper.pdf>

[8] Brooks, T., Mildenhall, B., Xue, T., Chen, J., Sharlet, D., & Barron, J. T. Unprocessing Images for Learned Raw Denoising. CVPR 2019. <https://openaccess.thecvf.com/content_CVPR_2019/html/Brooks_Unprocessing_Images_for_Learned_Raw_Denoising_CVPR_2019_paper.html>

[9] Zamir, S. W., Arora, A., Khan, S., Hayat, M., Khan, F. S., Yang, M.-H., & Shao, L. CycleISP: Real Image Restoration via Improved Data Synthesis. CVPR 2020. <https://openaccess.thecvf.com/content_CVPR_2020/html/Zamir_CycleISP_Real_Image_Restoration_via_Improved_Data_Synthesis_CVPR_2020_paper.html>

[10] Xing, Y., Qian, Z., & Chen, Q. Invertible Image Signal Processing. CVPR 2021. <https://openaccess.thecvf.com/content/CVPR2021/papers/Xing_Invertible_Image_Signal_Processing_CVPR_2021_paper.pdf>

[11] Ronneberger, O., Fischer, P., & Brox, T. U-Net: Convolutional Networks for Biomedical Image Segmentation. MICCAI 2015. <https://arxiv.org/abs/1505.04597>

[12] Kim, H., & Lee, K. M. Controllable Image Enhancement. arXiv 2022 / IEEE Transactions on Image Processing 2023. <https://arxiv.org/abs/2206.08488>

[13] Khashabi, D., Nowozin, S., Jancsary, J., & Fitzgibbon, A. W. Joint Demosaicing and Denoising via Learned Non-parametric Random Fields. IEEE Transactions on Image Processing, 2014. <https://www.microsoft.com/en-us/research/publication/joint-demosaicing-and-denoising-via-learned-non-parametric-random-fields/>

[14] Guo, Y., Jin, Q., Morel, J.-M., & Facciolo, G. How to Best Combine Demosaicing and Denoising? Inverse Problems and Imaging, 2024. <https://www.aimsciences.org/article/doi/10.3934/ipi.2023044>

[15] Guo, Y., Jin, Q., Morel, J.-M., Zeng, T., & Facciolo, G. Joint Demosaicking and Denoising Benefits from a Two-stage Training Strategy. Journal of Computational and Applied Mathematics, 2023. <https://arxiv.org/abs/2009.06205>

[16] Venkatakrishnan, S. V., Bouman, C. A., & Wohlberg, B. Plug-and-Play Priors for Model Based Reconstruction. IEEE GlobalSIP, 2013. <https://docs.lib.purdue.edu/ecetr/448/>

[17] Romano, Y., Elad, M., & Milanfar, P. The Little Engine That Could: Regularization by Denoising. SIAM Journal on Imaging Sciences, 2017. <https://epubs.siam.org/doi/10.1137/16M1102884>

[18] Cohen, R., Elad, M., & Milanfar, P. Regularization by Denoising via Fixed-Point Projection. SIAM Journal on Imaging Sciences, 2021. <https://arxiv.org/abs/2008.00226>

[19] Ulyanov, D., Vedaldi, A., & Lempitsky, V. Deep Image Prior. CVPR 2018. <https://openaccess.thecvf.com/content_cvpr_2018/html/Ulyanov_Deep_Image_Prior_CVPR_2018_paper.html>

[20] Zhang, K., Li, Y., Zuo, W., Zhang, L., Van Gool, L., & Timofte, R. Plug-and-Play Image Restoration with Deep Denoiser Prior. IEEE Transactions on Pattern Analysis and Machine Intelligence, 2022. <https://arxiv.org/abs/2008.13751>

[21] Conde, M. V., McDonagh, S., Maggioni, M., Leonardis, A., & Pérez-Pellitero, E. Model-Based Image Signal Processors via Learnable Dictionaries. AAAI 2022. <https://arxiv.org/abs/2201.03210>

[22] Wu, C.-T., Isikdogan, L. F., Rao, S., Nayak, B., Gerasimow, T., Sutic, A., Ain-kedem, L., & Michael, G. VisionISP: Repurposing the Image Signal Processor for Computer Vision Applications. ICIP 2019. <https://arxiv.org/abs/1911.05931>

[23] Hansen, P., Vilkin, A., Khrustalev, Y., Imber, J., Talagala, D. S., Hanwell, D., Mattina, M., & Whatmough, P. N. ISP4ML: The Role of Image Signal Processing in Efficient Deep Learning Vision Systems. ICPR 2020. <https://arxiv.org/abs/1911.07954>

[24] Zhang, Y., Dong, B., & Heide, F. All You Need is RAW: Defending Against Adversarial Attacks with Camera Image Pipelines. ECCV 2022. <https://light.princeton.edu/publication/allyouneedisraw/>

[25] Mosleh, A., Sharma, A., Onzon, E., Mannan, F., Robidoux, N., & Heide, F. Hardware-in-the-loop End-to-end Optimization of Camera Image Processing Pipelines. CVPR 2020. <https://light.princeton.edu/publication/hil_image_optimization/>

[26] Onzon, E., Mannan, F., & Heide, F. Neural Auto-Exposure for High-Dynamic Range Object Detection. CVPR 2021. <https://light.princeton.edu/publication/neural_auto_exposure/>

[27] Liang, J., Cao, J., Sun, G., Zhang, K., Van Gool, L., & Timofte, R. SwinIR: Image Restoration Using Swin Transformer. ICCV Workshops 2021. <https://arxiv.org/abs/2108.10257>

[28] Wang, Z., Cun, X., Bao, J., Zhou, W., Liu, J., & Li, H. Uformer: A General U-Shaped Transformer for Image Restoration. CVPR 2022. <https://arxiv.org/abs/2106.03106>

[29] Zamir, S. W., Arora, A., Khan, S., Hayat, M., Khan, F. S., Yang, M.-H., & Shao, L. Restormer: Efficient Transformer for High-Resolution Image Restoration. CVPR 2022. <https://arxiv.org/abs/2111.09881>

[30] Ho, J., Jain, A., & Abbeel, P. Denoising Diffusion Probabilistic Models. NeurIPS 2020. <https://arxiv.org/abs/2006.11239>

[31] Song, Y., Sohl-Dickstein, J., Kingma, D. P., Kumar, A., Ermon, S., & Poole, B. Score-Based Generative Modeling through Stochastic Differential Equations. ICLR 2021. <https://arxiv.org/abs/2011.13456>

[32] Kawar, B., Elad, M., Ermon, S., & Song, J. Denoising Diffusion Restoration Models. NeurIPS 2022. <https://arxiv.org/abs/2201.11793>

[33] Chung, H., Sim, B., Ryu, D., & Ye, J. C. Diffusion Posterior Sampling for General Noisy Inverse Problems. ICLR 2023. <https://arxiv.org/abs/2209.14687>

[34] Lipman, Y., Chen, R. T. Q., Ben-Hamu, H., Nickel, M., & Le, M. Flow Matching for Generative Modeling. ICLR 2023. <https://arxiv.org/abs/2210.02747>

[35] Liu, X., Gong, C., & Liu, Q. Flow Straight and Fast: Learning to Generate and Transfer Data with Rectified Flow. ICLR 2023. <https://arxiv.org/abs/2209.03003>

[36] Tong, A., Malkin, N., Fatras, K., Atanackovic, L., Zhang, Y., Huguet, G., Wolf, G., & Bengio, Y. Improving and Generalizing Flow-Based Generative Models with Minibatch Optimal Transport. Transactions on Machine Learning Research, 2024. <https://arxiv.org/abs/2302.00482>

[37] Ren, Y., Jiang, H., Yang, M., Li, W., & Liu, S. ISPDiffuser: Learning RAW-to-sRGB Mappings with Texture-Aware Diffusion Models and Histogram-Guided Color Consistency. AAAI 2025. <https://arxiv.org/abs/2503.19283>

[38] Reinders, C., et al. RAW-Diffusion: RGB-Guided Diffusion Models for High-Fidelity RAW Image Generation. WACV 2025. <https://arxiv.org/abs/2411.13150>

[39] Liu, Z., Feng, D., Jiang, H., Zeng, L., Wang, H., Feng, C., Lei, L., Zeng, B., & Liu, S. RAW-Flow: Advancing RGB-to-RAW Image Reconstruction with Deterministic Latent Flow Matching. AAAI 2026. <https://arxiv.org/abs/2601.20364>
