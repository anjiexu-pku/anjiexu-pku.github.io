---
title: "从 RAW 到图像: 相机前端的统一数学视角"
date: 2026-07-10
categories:
  - tech
tags:
  - computational-photography
  - isp
  - raw
  - deep-learning
excerpt: "这篇文章不把 learned ISP 当成“用神经网络修图”, 而是从 RAW 观测、Bayes 推断、损失函数、结构先验和任务目标出发, 把相机前端统一看成一个带物理模型和渲染偏好的数学决策问题。"
custom_css:
  - learned-isp-map
---

我们平时说“相机拍了一张照片”, 这句话其实省略了太多东西。传感器并不会直接给出一张好看的 RGB 图片。它最初得到的是 RAW: 线性的、带噪声的、经过 CFA 马赛克采样的传感器读数。我们最终看到的 sRGB/JPEG, 则是经过一整套 ISP, Image Signal Processing pipeline, 之后的结果。

所以, 如果我们把现代可学习相机前端放进一个统一的数学框架, 它要回答的问题不是“能不能用神经网络修图”, 而是:

> 给定传感器测量, 如何恢复、解释并渲染出某种目标图像?

这句话里有三个层次: 恢复, 是从有噪声、有缺失的 RAW 中估计场景信号; 解释, 是把相机响应、颜色、曝光、噪声和显示模型放到同一个数学框架里; 渲染, 是决定什么样的输出才算“好图像”。深度学习进入 ISP 的真正意义, 是把这些原本由工程规则、厂商经验和人工调参定义的流程, 变成一个由数据、损失函数、结构先验和任务目标共同决定的优化问题。

下面只围绕一个统一模型展开: 场景 $X$ 同时产生 RAW 观测 $R$ 与目标图像 $Y$; 可学习相机前端根据 $R$ 对不可见场景做推断, 再为某种风格、显示设备或下游任务作决策。文章先建立观测模型与 Bayes 解, 再用一张非串行架构图定位论文, 最后把网络结构拆成管线分解、空间算子和推断语义三个彼此独立的选择。

## 从观测到决策: 相机前端的统一模型

### RAW 不是照片, 而是传感器观测

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
r = M A x + \eta.
$$

其中 $x\in \mathbb{R}^{3N}$ 是理想的全彩线性图像, $M\in\lbrace0,1\rbrace^{N\times 3N}$ 是 CFA 采样矩阵, $A$ 包含曝光、增益、黑电平归一化等线性因素, $\eta$ 是噪声。

这个式子已经说明了一个基本事实: 从 RAW 到线性 RGB 本身就是欠定问题。每个像素只有一个颜色观测, 却要恢复三个颜色值; 还有噪声、坏点、镜头阴影、饱和和量化。去马赛克与去噪并不是两个互不相关的小步骤, 而是同一个不适定逆问题的两个侧面。

### 传统 ISP 是组合函数, 但不是可逆函数

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

### 监督学习定义了哪个目标

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

### 损失函数选择哪个 Bayes 解

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

### RAW 低光恢复为什么和 JPEG 低光增强不同

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

### 统一形式: 后验推断与渲染决策

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

## 非串行问题架构: 论文究竟在改什么

到这里, 我们已经有足够的符号把整篇文章压到一张图里。图的顶部不是网络输入输出, 而是世界产生数据的分叉: 同一场景 $X$ 经过传感器得到 RAW $R$, 经过参考渲染得到目标 $Y$。中部的直接估计、两阶段和生成式模型是三条可替代的 forward 路径; reverse ISP 与任务分支则是旁路。切换图上方的视角, 可以看到每组论文主要修改哪个数学对象。

{% include learned-isp-research-map.html %}

这张图先区分生成过程与推断过程。数据生成侧是:

$$
R\sim p_{\psi}(r\mid X,m),
\qquad
Y=\rho_u(X),
$$

其中 $X$ 是不可见场景, $m$ 是曝光、增益、CFA 和传感器参数, $u$ 是渲染风格或任务条件。给定观测以后, forward ISP 至少有三种不同因子分解:

$$
\begin{aligned}
q_{dir}(\hat y\mid r,u)
&=q_{\theta}(\hat y\mid r,u),
\\
q_{fac}(\hat y\mid r,m,u)
&=\int q_{\theta_e}(\hat y\mid s,u)
q_{\theta_r}(s\mid r,m)\,ds,
\\
q_{gen}(\hat y\mid r,u)
&=\int q_{\theta}(\hat y\mid r,u,\epsilon)
p(\epsilon)\,d\epsilon.
\end{aligned}
$$

这里 $S$ 是恢复后的线性场景或中间表示, $\epsilon$ 是生成过程的随机初值。reverse ISP 建模的是另一个条件方向 $q_{rev}(r\mid y,m)$, 而任务分支既可以消费显示图像, 也可以绕过它:

$$
\hat T=G_{\omega}(\hat Y)
\qquad\text{或}\qquad
\hat T=G_{\omega}(Z_{\eta}(R)).
$$

确定性 CNN 并没有离开这个概率形式; 它只是把条件分布限制成集中在一个点上的退化分布:

$$
q_{\theta}(y\mid r)
=
\delta\!\left(y-F_{\theta}(r)\right).
$$

相反, diffusion 和 flow matching 试图保留一个非退化的 $q_{\theta}(Y\mid R)$, 因而能够表达同一份 RAW 对应多种合理渲染的情况。

训练时, 这些方法大体都在下面的目标中选择不同的项:

$$
\begin{aligned}
\min_{\mathcal{A},\theta,\omega,\psi}
\mathbb{E}
\Big[
&\lambda_{img}\ell_{img}(\hat{Y},Y)
-\lambda_{phys}\log p_{\psi}(R\mid \hat S,m)
\\
&+\lambda_{dist}D\!\left(
q_{\theta,\mathcal{A}}(Y\mid R,u),
p(Y\mid R,u)
\right)
\\
&+\lambda_{task}\ell_{task}(G_{\omega}(\hat{Y}),T)
\Big]
+\lambda_C C(\mathcal{A}).
\end{aligned}
$$

这里的五项分别约束图像保真、物理测量一致性、条件分布、下游任务和计算成本; $\hat S$ 只在模型含有物理中间表示时出现。一篇论文通常只选择其中几项。于是, 论文的重点可以按图中的位置来读:

| 图中位置 | 代表工作 | 数学上主要改变什么 |
| --- | --- | --- |
| 观测与训练数据 $p_{\psi}(R\mid X,m)$ | FlexISP、Unprocessing、CycleISP、RAW prior、ROD、AODRaw、RAWDet-7、ReRAW [1,8,9,13-15,24,42,43,49,50] | 显式写入 CFA、噪声和相机 forward model, 或构造更可信的 RAW/RGB 联合分布 |
| 恢复后验 $q(S\mid R,m)$ | Deep Joint、SID/LSID、PnP/RED/DIP [2,4,16-20] | 用解析先验或摊销网络求解去噪、去马赛克和低光恢复 |
| 函数族与中间分解 $\mathcal{F}_{\mathcal{A}}$ | DeepISP、PyNET、CameraNet、ReconfigISP、InvISP、Learnable Dictionary [3,5-7,10,21] | 选择端到端、两阶段、可重构或可逆结构, 从而改变可辨识性、信息保留和计算成本 |
| 空间算子 $F_{\theta}$ | U-Net、SwinIR、Uformer、Restormer [11,27-29] | 用局部多尺度卷积或非局部注意力参数化恢复器、渲染器、score 或 velocity |
| 条件分布与反向 ISP | Diffusion、DPS、Flow Matching、ISPDiffuser、RAW-Diffusion、RAW-Flow、ReRAW [30-39,50] | 从单点回归转向 $p(Y\mid R)$、$p(R\mid Y)$ 或两种分布之间的概率输运 |
| 消费者、损失与成本 $G_{\omega},\ell,C$ | VisionISP、ISP4ML、HIL、Neural Auto-Exposure、DynamicISP、AdaptiveISP、RAW-Adapter、RAM、Dark-ISP、TA-ISP [22,23,25,26,40,41,44-48] | 把最优输出从“好看的照片”改成任务充分表示, 并联合优化硬件代价 |

这个定位还澄清了两个容易混淆的概念。SwinIR、Uformer 和 Restormer 首先是图像恢复的空间算子, 它们本身没有定义 RAW 的传感器似然或最终渲染目标; [30-36] 首先是 diffusion、逆问题采样和 flow matching 的数学基础, 也不是完整的相机 ISP。只有当这些算子或概率过程与 RAW 条件、目标图像和损失函数结合时, 它们才成为 learned ISP 系统的一部分。

更重要的是, 管线分解、空间算子与推断语义并不是同一层级的互斥选项。一个 two-stage ISP 可以在两段都使用 CNN 或 Transformer; 一个 diffusion ISP 仍需 U-Net 或 Transformer 参数化 score; flow matching 的 velocity network 也一样。后面讨论 architecture 时, 我们会始终把这三个选择分开。

## 三个结构性推论

### 恢复和增强为什么应该分开

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

### 为什么不存在对所有任务都最优的 ISP

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

### 输出正确, 不代表内部模块可辨识

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
F \in \mathcal{F}_{\mathrm{modular}}
\subset
\mathcal{F}_{\mathrm{all}}.
$$

假设空间变小, 可能牺牲一部分表达能力, 但会换来:

- 更好的可解释性;
- 更少的数据需求;
- 更容易跨传感器迁移;
- 更容易定位失败原因;
- 更容易满足硬件延迟和功耗约束。

这也是为什么 learned ISP 不应该被粗暴理解为“用一个大网络替代所有相机工程”。更好的问题是: 哪些结构先验应该保留, 哪些步骤应该学习, 哪些目标应该显式条件化?

## 沿着架构图读理论与方法

逐篇复述网络结构会把同一个数学问题讲很多遍。更紧凑的读法是沿图 1 的分支追问五件事: 观测模型是否可信, 恢复先验从哪里来, 模块顺序如何改变噪声, 反向映射是否可辨识, 最终风险由人眼还是任务定义。FlexISP、Deep Joint、DeepISP、LSID、CameraNet、ReconfigISP、Unprocessing、CycleISP 与 InvISP 都会在下面各自对应到这些问题, 而不是被排成一条“网络升级史”。

如果把“理论工作”理解成试图解释为什么某类解法成立, 相关文献大致可以分成五条线。它们共同指向一个判断: learned ISP 的核心不是 neural network, 而是如何定义观测模型、先验、信息损失和目标风险。

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

## 深度学习方法如何实现这套理论

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

把这些论文放回图 1, 它们并不是在竞争同一个“最佳网络”。Deep Joint、DeepISP 和 LSID 主要把逐图优化摊销成前向推断; CameraNet、ReconfigISP 和 InvISP 改变中间分解或函数族; RISP/PyNET 与 task-aware 方法则改变监督目标和最终消费者。前面的表给出位置, 下面进一步解释它们在这些位置上扮演的理论角色。

所以, 深度学习方法大致可以分成四种理论角色。

第一类是“摊销优化器”。Deep Joint Demosaicking、DeepISP 和 LSID 都可以这样理解。传统方法显式解一个 MAP/MMSE 问题; 神经网络把很多训练样本上的求解经验压进参数 $\theta$, 测试时直接输出估计。它快, 但代价是它的先验和噪声假设藏在数据与网络里。

第二类是“可学习先验”。PnP/RED 把 denoiser 当作先验或 proximal 近似; CNN ISP 则把更大的 RAW-to-RGB 推理过程做成一个隐式先验。两者的差别在于: PnP/RED 仍然保留 data fidelity 项, 所以观测模型还在优化循环里; 纯端到端 ISP 常常只保留训练损失, 因而更依赖数据覆盖。

第三类是“结构化假设空间”。CameraNet、ReconfigISP、InvISP 和 Model-Based ISP 都不是简单追求更大的网络, 而是在限制 $F_\theta$ 的形状。CameraNet 用两阶段结构表达 restoration/enhancement 分解; ReconfigISP 用模块图表达可搜索管线; InvISP 用可逆结构表达信息守恒; Model-Based ISP 用传统模块表达可解释性。理论上, 它们都是在选择一个更有偏置的 $\mathcal{F}$:

$$
F_\theta
\in
\mathcal{F}_{\mathrm{structured}}
\subset
\mathcal{F}_{\mathrm{all}}.
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
\mathcal{F}_{\mathrm{res}}
=
\{B+\Delta_\theta\}
\subset
\mathcal{F}_{\mathrm{all}}.
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

#### 小结: 用函数族阅读 architecture

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

## 把可学习相机前端拆成三个建模选择

图 1 暴露了一个关键区别: one-stage、two-stage 与 invertible 选择随机变量怎样连接; CNN 和 Transformer 选择怎样参数化空间函数; regression、diffusion 和 flow matching 选择模型输出一个决策点还是条件分布。把这些名字排成一条“架构升级路线”并不准确。一个完整系统至少包含三个彼此独立的选择:

| 建模层级 | 选择 | 数学对象 | 在 learned ISP 中的角色 |
| --- | --- | --- | --- |
| 管线分解 | direct / two-stage / reverse / task-aware | 条件独立性、中间变量与信息路径 | 决定 $R,S,Y$ 和任务输出如何连接 |
| 空间算子 | CNN / U-Net | 局部、平移等变的多尺度算子 | 参数化恢复器、渲染器、score 或 velocity |
| 空间算子 | Transformer | 内容自适应的非局部核 | 参数化全局颜色、长程依赖、自相似纹理和场景条件 |
| 推断语义 | regression / diffusion / flow | 条件统计量、score 或 velocity | 决定输出点估计、后验样本还是概率输运 |

这两条轴可以从同一个问题出发:

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

空间算子决定如何参数化 $F_\theta$、score 或 velocity; 推断语义决定模型最终近似点决策 $\delta^\star(r)$, 还是完整条件分布 $p(Y\mid R=r)$。

### CNN / U-Net: 局部 Markov 先验和快速摊销推理

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

### Transformer: 内容自适应的非局部成像算子

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
\mathcal{F}_{\mathrm{CNN}}
\subset
\mathcal{F}_{\mathrm{local}},
\qquad
\mathcal{F}_{\mathrm{Transformer}}
\subset
\mathcal{F}_{\mathrm{content\text{-}adaptive}}.
$$

CNN 假设相同局部 pattern 用相同规则处理; Transformer 允许处理规则随整张图内容改变。对 learned ISP 来说, 这意味着:

> Transformer 把 ISP 从“固定局部滤波器”推进到“内容自适应的非局部估计器”。

但它也有代价: 更高的算力、更强的数据需求, 以及可能更弱的物理可解释性。

### Diffusion: 从点估计变成条件后验采样

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

### Flow Matching: 把 ISP 看成分布输运

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

### 三个选择如何组合?

一个具体模型其实是三个选择的乘积:

$$
\text{learned ISP}
=
\underbrace{\text{inference semantics}}_{\text{regression / diffusion / flow}}
\times
\underbrace{\text{spatial operator}}_{\text{CNN / Transformer / hybrid}}
\times
\underbrace{\text{pipeline factorization}}_{\text{one-stage / two-stage / invertible}}.
$$

因此应该先问输出需要一个点, 还是一个分布, 再选择实现它的空间算子:

| 先做的决定 | 可选形式 | 适合场景 | 主要风险 |
| --- | --- | --- | --- |
| 输出是点估计 | L1/L2 regression, MAP/MMSE 近似 | 实时 ISP、去噪、去马赛克、移动端 | 多解被平均, 感知细节可能偏软 |
| 输出是条件分布 | Diffusion / score model | 多风格渲染、低光细节、逆问题后验采样 | 采样慢, 需要物理约束抑制幻觉 |
| 输出是概率输运 | Flow Matching / rectified flow | 快速生成式 ISP、RAW/RGB latent translation | coupling 决定学到哪种对应关系 |
| 空间算子偏局部 | CNN / U-Net | CFA 邻域、纹理恢复、有限算力 | 全局曝光和长程依赖表达较弱 |
| 空间算子偏非局部 | Transformer / hybrid | 全局颜色、HDR、重复纹理、场景条件 | 显存、算力和数据需求更高 |

例如, ISPDiffuser 的“diffusion”决定它学习条件 score, 但 score network 仍然需要某种 U-Net、Transformer 或混合骨干; RAW-Flow 的“flow matching”决定 velocity 的训练目标, 但 $v_\theta$ 同样要由空间网络参数化。手机实时出图可以选择 regression + lightweight CNN, 多解的感知渲染可以选择 diffusion + U-Net, reverse ISP 则可能选择 flow matching + Transformer。它们是组合关系, 不是一条从旧到新的替代链。

## 用统一坐标读一篇新论文

有了图 1, 一篇 learned ISP 论文可以被压缩成一个建模坐标:

$$
\mathcal{P}_{paper}
=
\left(
p_{\psi}(R\mid X,m),
\mathcal{A},
q_{\theta}(Y\mid R,u),
Y,
\ell,
C
\right).
$$

它依次记录观测与数据模型、计算架构、推断对象、监督目标、决策损失和系统成本。所谓论文贡献, 通常就是改变这个六元组中的一项或几项。读一篇新工作时, 可以直接追问:

1. 输入真的是 sensor RAW, 还是 unprocessed/synthetic RAW? 这决定 $p_{\psi}$ 是否可信。
2. 输出是点估计 $F_\theta(R)$、条件分布 $q_\theta(Y\mid R)$, 还是 reverse conditional $q_\theta(R\mid Y)$?
3. CNN/Transformer 改变的是空间算子, 还是作者还同时改变了中间变量和 pipeline factorization?
4. 目标 $Y$ 是物理参考、长曝光、DSLR 风格、人工 retouch, 还是任务标签?
5. loss 在奖励保真、感知真实性、分布匹配还是下游准确率? 这些目标是否互相冲突?
6. 性能提升来自更合适的数学假设, 还是参数量、训练数据、算力或采样步数的增加?

如果一篇论文无法回答这些问题, 那么“更好的 architecture”往往只是一个不完整的结论。反过来, 一旦能指出它修改了图中的哪一块, 不同方法就有了可比较的共同坐标。

## 从 Bayes risk 推出这些论文的族谱

上面的六元组还只是论文阅读坐标。要让它真正有解释力, 需要再往前推一步: 什么叫一个相机前端“保留了任务需要的信息”?

设任务为 $\tau$, 任务标签或目标变量为 $Y_{\tau}=h_{\tau}(S)$, 损失为 $\ell_{\tau}$。一个相机前端把 RAW 观测 $R$ 变成表示:

$$
Z = F(R).
$$

对这个表示而言, 下游最优风险是:

$$
\mathcal{R}_{\tau}(Z)
=
\inf_g
\mathbb{E}
\left[
\ell_{\tau}(g(Z),Y_{\tau})
\right].
$$

如果直接让下游模型使用完整 RAW, 可得到 RAW oracle 风险:

$$
\mathcal{R}_{\tau}(R)
=
\inf_g
\mathbb{E}
\left[
\ell_{\tau}(g(R),Y_{\tau})
\right].
$$

于是一个前端 $F$ 对任务 $\tau$ 的信息损失可以定义为:

$$
\Delta_{\tau}(F)
=
\mathcal{R}_{\tau}(F(R))
-
\mathcal{R}_{\tau}(R)
\ge 0.
$$

这个量比 PSNR 更接近我们真正关心的问题。若 $\Delta_{\tau}(F)=0$, 就说明 $F(R)$ 对任务 $\tau$ 来说和 RAW 一样充分; 若 $\Delta_{\tau}(F)>0$, 就说明前端丢掉了某些任务必要信息。VisionISP、ISP4ML、RAW object detection、TA-ISP 这些工作真正挑战的就是传统人眼 ISP 的这个 risk gap。

如果同时考虑人类渲染、检测、分割、鲁棒性和硬件成本, 统一目标可以写成:

$$
\min_F
\sum_{\tau\in\mathcal{T}}
\lambda_{\tau}
\mathcal{R}_{\tau}(F(R))
+
\beta I(R;F(R))
+
\gamma C(F).
$$

这里 $\mathcal{R}_{\tau}$ 衡量任务性能, $I(R;F(R))$ 或码率约束衡量表示大小, $C(F)$ 衡量延迟、功耗和硬件复杂度。不同论文其实是在这个目标里打开不同的系数: 摄影 ISP 让 human rendering 权重大; RAW detection 让 task loss 权重大; mobile / edge 方法让 $C(F)$ 权重大; invertible ISP 则把信息保留约束推到极端。

### 为什么不存在通用最优 ISP

如果两个任务 $\tau_1,\tau_2$ 的损失不同, 它们的 Bayes 决策一般不同:

$$
\delta_{\tau}^{\star}(r)
=
\arg\min_u
\mathbb{E}
[
\ell_{\tau}(u,Y_{\tau})
\mid R=r
].
$$

给人看的图像希望有舒服的 tone、颜色和噪声观感; 检测器可能更需要暗部边缘、高光区域和物体纹理。若传统 ISP 是:

$$
Y_{rgb}=H(R),
$$

并且 $H$ 包含 clipping、tone mapping、gamma、8-bit quantization 和 JPEG compression, 那么由数据处理不等式:

$$
I(Y_{\tau};H(R))
\le
I(Y_{\tau};R).
$$

只要这个不等式是严格的, 就会出现:

$$
\mathcal{R}_{\tau}(H(R))
>
\mathcal{R}_{\tau}(R).
$$

这就是 task-aware ISP 的理论起点。它不是说 RGB 不好, 而是说人眼 RGB 不是所有任务的充分统计量。VisionISP、ISP4ML、DynamicISP、AdaptiveISP、RAW-Adapter、RAM、Dark-ISP、TA-ISP 都可以看成在寻找另一个 $F$ 让 $\Delta_{\tau}(F)$ 变小, 同时不让 $C(F)$ 爆掉。

### 串行管线为什么危险, 并行管线为什么合理

传统 ISP 是串行组合:

$$
Z_K
=
F_K\circ F_{K-1}\circ\cdots\circ F_1(R).
$$

如果中间某一步是不可逆的, 之后所有模块都无法恢复它丢掉的信息。形式化地:

$$
I(Y_{\tau};Z_K)
\le
I(Y_{\tau};Z_{K-1})
\le
\cdots
\le
I(Y_{\tau};R).
$$

所以串行管线的每一步都在承担一个不可回滚的表示选择。去马赛克、降噪、tone mapping 和压缩不是中性操作, 而是在修改后续任务能看到的统计量。

RAM 这类并行 RAW processing 的理论意义正在这里 [45]。如果并行地产生:

$$
Z=(F_1(R),F_2(R),\ldots,F_K(R)),
$$

那么它至少不必过早承诺唯一处理路径。融合器 $H_{\theta}$ 可以在任务监督下选择哪些统计有用:

$$
\hat{Y}_{\tau}
=
G_{\omega}(H_{\theta}(Z)).
$$

这不是模仿人眼视觉系统这么简单, 而是在降低串行不可逆决策带来的 risk gap。DynamicISP 和 AdaptiveISP 走的是另一条路: 不保留所有分支, 而是学习一个输入相关策略:

$$
a \sim \pi_{\alpha}(a\mid R),
\qquad
Z=F_a(R),
$$

再用 $\mathcal{L}_{task}+\lambda C(a)$ 在任务性能和计算成本之间折中。并行分支是“保留多种候选统计”, 动态策略是“按场景选择处理路径”; 二者都是对固定串行 ISP 的理论回应。

### 两阶段和模块化为什么提高可解释性

端到端 RAW-to-RGB 网络只约束整体映射:

$$
Y \approx F_{\theta}(R).
$$

如果存在任意可逆变换 $T$, 那么分解:

$$
F_{\theta}
=
D_{\psi}\circ E_{\phi}
=
(D_{\psi}\circ T^{-1})\circ(T\circ E_{\phi})
$$

给出的最终输出完全一样, 但中间表示含义完全不同。因此, 只用最终 RGB 监督时, 中间层是否真的对应去噪、去马赛克、白平衡或颜色校正, 在数学上不可辨识。

两阶段或模块化方法的价值, 是给中间变量加约束:

$$
\min_{\phi,\psi}
\mathcal{L}_{render}(D_{\psi}(E_{\phi}(R)),Y)
+
\lambda
\mathcal{L}_{latent}(E_{\phi}(R),S).
$$

CameraNet、Model-Based ISP、Dark-ISP 都可以这样理解 [6,21,46]。它们不是迷信传统模块, 而是在缩小等价解空间。物理中间变量 $S$ 越明确, 模型越不容易用数据集捷径解释训练集, 跨相机和跨曝光泛化也更有希望。

### 可逆、reverse ISP、diffusion 与 flow 的共同问题

如果 forward ISP $H$ 是 many-to-one, 则:

$$
H(R_1)=H(R_2)=Y,
\qquad
R_1\ne R_2.
$$

这意味着:

$$
H(R\mid Y)>0.
$$

因此 RGB-to-RAW 不能被理解为求一个确定性逆函数, 而应理解为后验建模:

$$
p(R\mid Y,m).
$$

Unprocessing、CycleISP、ReRAW、RAW-Flow 都在处理这个后验, 只是选择不同近似 [8,9,39,50]。Cycle consistency 给后验加自洽约束; ReRAW 通过多头和采样权重改善经验后验拟合; RAW-Flow 把后验近似写成 latent transport。它们都不能消除 $H(R\mid Y)>0$ 这个事实, 只能选择一种合理的 coupling 或显式保留多解性。

同理, RAW-to-sRGB 也未必是单峰的。若同一份 RAW 可以有多种合理渲染风格, 则:

$$
p(Y\mid R)
\text{ is multi-modal}.
$$

L2 regression 给出条件均值:

$$
F_{L2}^{\star}(R)=\mathbb{E}[Y\mid R],
$$

这会把多种合理渲染平均掉。Diffusion 和 flow matching 的理论价值, 是把目标从点估计改成条件分布或概率路径:

$$
q_{\theta}(Y\mid R)
\approx
p(Y\mid R).
$$

这解释了为什么 ISPDiffuser、RAW-Diffusion、RAW-Flow 这类方法不是简单“生成模型更强”, 而是在处理多解后验。它们的风险也由此而来: 如果 RAW likelihood 或颜色一致性约束太弱, 生成先验会从“补足不确定性”滑向“制造传感器没有测到的细节”。

### Adapter 和 task-oriented ISP 是先验迁移

RAW-Adapter 和 TA-ISP 还揭示了另一个问题: 下游模型 $G_{\omega}$ 通常已经在 sRGB 分布上预训练。它隐含了一个输入分布先验:

$$
Z_{rgb}\sim P_{\mathrm{sRGB}}.
$$

直接把 RAW 或 RAW-like 表示喂给它, 会产生分布错配。adapter 的作用不是把 RAW 变成“漂亮图”, 而是找一个低成本映射 $A_{\theta}$, 使得:

$$
A_{\theta}(R)
\sim
\text{a distribution usable by } G_{\omega},
$$

同时尽量保持任务充分性:

$$
\mathcal{R}_{\tau}(A_{\theta}(R))
-
\mathcal{R}_{\tau}(R)
\approx 0.
$$

因此 RAW-Adapter、TA-ISP 与传统 RAW-to-RGB 的目标不同。它们输出的不是摄影意义上的最终图像, 而是“预训练视觉模型可消费的充分表示”。这也解释了为什么它们强调轻量、modulation、input-level / model-level adapter: 论文贡献在于用很小的 $C(F)$ 换取较小的 task risk gap。

### 用 risk gap 重新整理论文

现在可以把收录的论文整理成一条理论链:

| 理论问题 | 数学对象 | 代表论文 | 解释 |
| --- | --- | --- | --- |
| RAW 比 sRGB 多保留什么? | $I(Y_{\tau};R)$ vs. $I(Y_{\tau};H(R))$ | VisionISP、ISP4ML、ROD、AODRaw、RAWDet-7 | 证明或评估传统 ISP 对任务的 risk gap |
| 如何近似 RAW oracle? | $\mathcal{R}_{\tau}(F(R))-\mathcal{R}_{\tau}(R)$ | RAM、Dark-ISP、TA-ISP、RAW-Adapter | 学一个低成本任务充分表示 |
| 管线应固定还是自适应? | $F_a(R),\, a\sim\pi(a\mid R)$ | DynamicISP、AdaptiveISP | 把 ISP 结构和参数变成条件化策略 |
| 中间模块是否可解释? | $F=D\circ E$ 的 identifiability | CameraNet、Model-Based ISP、Dark-ISP | 用潜变量或物理模块缩小等价解空间 |
| 信息能否保留? | $H(R\mid Z)$ 或 $I(R;Z)$ | InvISP、ReconfigISP | 把可逆性、结构搜索和硬件约束写入函数族 |
| 多解后验如何表达? | $p(Y\mid R)$ 或 $p(R\mid Y)$ | ISPDiffuser、RAW-Diffusion、ReRAW、RAW-Flow | 从点估计转向分布、采样或概率输运 |

这样看, 这些论文之间不是散点关系, 而是在回答同一个理论问题的不同切面:

> 在给定传感器观测 $R$、任务损失 $\ell_{\tau}$ 和系统成本 $C$ 时, 怎样学习一个尽可能接近 RAW oracle、又足够便宜和可部署的表示 $Z=F(R)$?

## 回到具体近作: 每篇论文改了哪一项

有了 risk gap 和表示充分性的推导, 最近几篇 RAW / ISP for vision 的论文就不只是“又做了一个模块”, 而是在不同位置上改写成像系统的数学定义。

### DynamicISP 与 AdaptiveISP: ISP 变成策略

DynamicISP 和 AdaptiveISP 都把 ISP 从固定函数变成输入相关的策略 [40,41]。固定 ISP 可以写成:

$$
Z = F_{\phi}(R).
$$

动态 ISP 更接近:

$$
\phi_t \sim \pi_{\alpha}(\phi\mid R_t,h_{t-1}),
\qquad
Z_t = F_{\phi_t}(R_t),
$$

其中 $h_{t-1}$ 可以是上一帧识别结果、场景状态或轻量控制器的隐藏变量。AdaptiveISP 进一步让策略选择模块结构与参数, 目标不再是图像质量, 而是检测风险和计算成本:

$$
\min_{\alpha}
\mathbb{E}
\left[
\mathcal{L}_{det}
\left(
G_{\omega}(F_{\pi_{\alpha}(R)}(R)),
Y_{det}
\right)
+ \lambda C(\pi_{\alpha}(R))
\right].
$$

在我们的框架里, 这类工作的贡献不是“强化学习调参”本身, 而是把 $\mathcal{A}$ 和 $C$ 变成逐图条件化变量。它承认一个事实: 暗光、高动态范围、普通白天场景不需要同一条 ISP 路径。最优 ISP 不是一个全局常数, 而是随观测和任务风险改变的 policy。

### RAW object detection: 输出不再服务人眼

Toward RAW Object Detection、AODRaw、RAM、Dark-ISP 和 TA-ISP 这组工作把消费者从人眼改成 detector / segmenter [42-48]。这时输出变量最好不要叫 RGB, 而应叫任务表示:

$$
Z = F_{\theta}(R),
\qquad
\hat{Y}_{task}=G_{\omega}(Z).
$$

目标也从

$$
\mathcal{L}_{render}(F_{\theta}(R),Y_{rgb})
$$

变成

$$
\mathcal{L}_{task}(G_{\omega}(F_{\theta}(R)),Y_{task})
+
\lambda C(F_{\theta}).
$$

ROD 和 AODRaw 的价值首先在 $p_{\psi}(R,Y_{task},m)$: 它们让“RAW 是否真的比 sRGB 更适合检测”变成可测问题, 而不是直觉问题 [42,43]。RAWDet-7 又把 bit-depth 写进评估, 等价于显式研究

$$
Q_b(R), \qquad b\in\{4,6,8,\ldots\},
$$

对任务信息的影响 [49]。这和前面数据处理不等式呼应: 低 bit quantized RAW 仍可能比 sRGB 更接近传感器观测, 但它已经不是完整 RAW, 必须把量化成本放进 $C$ 或观测模型里。

RAM 的特殊性在于它拒绝把 ISP 看成一条串行管线 [45]。它更像并行地产生多种任务候选表示:

$$
Z_k = F_k(R),
\qquad
Z = H_{\theta}(Z_1,\ldots,Z_K).
$$

这相当于把“哪一种处理最适合检测”推迟到融合器里决定。用统一框架看, RAM 改的是 pipeline factorization: 不再假设白平衡、去噪、tone mapping 必须排成固定顺序, 而是把多个统计视角并行保留给任务头。

Dark-ISP 则更接近“有物理约束的任务 ISP” [46]。它把传统 ISP 拆成线性 sensor calibration 和非线性 tone mapping, 再让每个模块带内容自适应能力。数学上, 它不是完全放弃物理管线, 而是在

$$
F_{\theta}
=
F_{\mathrm{nonlinear},\theta}
\circ
F_{\mathrm{linear},\theta}
$$

这个受限函数族内优化检测损失。这个限制很重要: 低光检测需要 RAW 信息, 但如果任由大网络直接拟合, 很容易把传感器噪声、tone 偏好和检测捷径混在一起。Dark-ISP 的线性/非线性分解就是在给 $\mathcal{F}_{\mathcal{A}}$ 加可解释约束。

TA-ISP 的位置又不同 [48]。它面对的是部署约束: 不想用一个重型 dense ISP, 又想让预训练视觉模型吃到更合适的输入。于是它用全局、区域、像素级的轻量 modulation 来近似空间变化变换:

$$
Z(p)
=
a_{\theta}(R,p)\odot T(R,p)
+
b_{\theta}(R,p),
$$

其中 $a_{\theta},b_{\theta}$ 的自由度被控制在很小的参数量里。统一框架下, TA-ISP 是在 $\mathcal{F}_{\mathcal{A}}$ 和 $C$ 之间找折中: 表达能力要比手调 ISP 强, 但不能像完整 RAW-to-RGB 网络那样重。

### RAW-Adapter: 问题不只是输入适配, 也是先验迁移

RAW-Adapter 处理的是另一个常见现实: 大量强视觉模型都在 sRGB 上预训练, 但 RAW 和 sRGB 的统计不一样 [44]。如果直接把 RAW 输入预训练模型, 等价于让 $G_{\omega}$ 在训练分布外工作。RAW-Adapter 可以写成:

$$
Z = A_{\theta}^{in}(R),
\qquad
\hat{Y}=G_{\omega,A_{\theta}^{model}}(Z).
$$

这里有两层适配: 输入级 adapter 把 RAW 拉近预训练模型可理解的表征; 模型级 adapter 则把 ISP 阶段信息注入下游网络。用我们的术语说, 它不是单纯学习 $F_{\theta}(R)$, 而是在迁移一个 sRGB 先验:

$$
p_{\mathrm{sRGB-pretrain}}(Y)
\quad
\rightarrow
\quad
p_{\mathrm{RAW-task}}(Y\mid R).
$$

这提醒我们: 预训练权重本身也是先验。RAW 任务中的 domain gap 不只发生在像素空间, 也发生在 backbone 的特征空间。

### ReRAW 与 RAW-Flow: 反向 ISP 是后验建模, 不是求逆

ReRAW 和 RAW-Flow 都服务于一个数据问题: 标注好的 RGB 数据很多, 标注好的 RAW 数据少 [39,50]。因此它们试图从 RGB 构造可用于训练的 RAW。统一框架下, 这不是 $R=f^{-1}(Y)$, 而是估计:

$$
p(R\mid Y,m).
$$

ReRAW 用多头预测 RAW candidates, 再用 stratified sampling 强调高亮 RAW 像素 [50]。这可以理解为改变经验风险权重:

$$
\widehat{\mathbb{E}}_{(Y,R)}
\left[
w(R)\ell(\hat{R},R)
\right],
$$

其中 $w(R)$ 让训练不要只被大量暗部/中间亮度像素主导。RAW-Flow 则把 RGB-to-RAW 写成 latent transport [39]。两者共同说明: 反向 ISP 的核心困难不是网络容量, 而是 coupling。一个 RGB 对应多个可能 RAW, 模型必须选择或表达这种多解性。

### 这些论文合起来说明了什么?

把这些近作放进同一张坐标系, 可以得到一个更强的判断:

| 论文方向 | 改写的数学对象 | 对统一视角的补充 |
| --- | --- | --- |
| DynamicISP / AdaptiveISP | $\pi(\mathcal{A},\phi\mid R)$ | ISP 是输入相关的策略, 不是固定函数 |
| ROD / AODRaw / RAWDet-7 | $p(R,Y_{task},m)$ 与 $Q_b(R)$ | RAW-for-vision 需要真实观测分布和 bit-depth 约束 |
| RAM | $\{F_k(R)\}_{k=1}^K$ 与融合器 | 串行 ISP 不是唯一合理分解, 并行任务表示也成立 |
| Dark-ISP | 受限的线性/非线性 $\mathcal{F}$ | 任务优化仍然可以保留物理可解释模块 |
| RAW-Adapter / TA-ISP | adapter / modulation 函数族 | 重点是低成本地把 RAW 映射到预训练模型可用的任务表示 |
| ReRAW / RAW-Flow | $p(R\mid Y,m)$ 或 latent transport | 反向 ISP 是多解后验建模, 不是确定性求逆 |

这些工作共同把 learned ISP 推向同一个方向: ISP 不再是“把 RAW 做成漂亮 RGB”的固定前处理, 而是一个可条件化、可部署、可任务化的决策层。它连接传感器物理、数据分布、模型先验、任务损失和硬件成本。也正因为如此, 用一个统一数学视角来读它们, 比按年份罗列网络结构更有解释力。

## 我得到的结论

第一, learned ISP 不是简单的图像增强。它是一个从传感器观测出发, 在不确定性下做恢复和渲染决策的问题。

第二, RAW 和 JPEG 的差别是信息论层面的差别。RAW 保留了更接近物理测量的线性高 bit-depth 数据; JPEG 是经过非线性、量化和压缩后的显示结果。低光 RAW 恢复和低光 JPEG 增强不是同一个问题。

第三, 用监督学习训练出的 ISP 不是“真实 ISP”, 而是某个数据集、目标和损失函数下的 Bayes 决策器。目标来自 Canon DSLR, 它就学 Canon 风格; 目标来自长曝光, 它就学长曝光恢复; 目标来自人类修图, 它就学人的偏好。

第四, restoration 和 enhancement 应该被区分。前者面向物理信号恢复, 后者面向显示、审美或任务目标。把二者全塞进黑箱可以工作, 但会失去结构解释, 也容易混淆目标。

第五, 不存在一个对所有任务最优的 ISP。给人看的图像、给检测器看的图像、给三维重建用的图像, 可能需要不同的前端处理。ISP 是任务定义的一部分, 不是中性的预处理。

第六, 深度学习没有让成像模型变得不重要。恰恰相反, 越要学习 ISP, 越需要知道哪些信息在 RAW 中, 哪些信息在 JPEG 中已经丢失, 哪些步骤有明确物理意义, 哪些步骤是主观渲染, 哪些目标会引入幻觉。

第七, 网络结构不是附属实现细节。U-Net、pyramid、two-stage、cycle、invertible、reconfigurable 或 task-aware modulation, 都是在选择不同的函数族 $\mathcal{F}_A$。它们把多尺度性、潜变量分解、信息保留、可逆性、任务条件化和硬件成本写进 learned ISP 的假设空间。换结构, 本质上是在换一种隐式先验。

第八, 一个完整 learned ISP 由三个独立选择组成: 管线分解决定变量怎样连接, CNN/Transformer 参数化空间算子, regression/diffusion/flow 定义点估计或条件分布怎样学习。它们可以自由组合, 不是一条从旧到新的架构替代链。

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

[40] Yoshimura, M., Otsuka, J., Irie, A., & Ohashi, T. DynamicISP: Dynamically Controlled Image Signal Processor for Image Recognition. ICCV 2023. <https://arxiv.org/abs/2211.01146>

[41] Wang, Y., Xu, T., Zhang, F., Xue, T., & Gu, J. AdaptiveISP: Learning an Adaptive Image Signal Processor for Object Detection. NeurIPS 2024. <https://arxiv.org/abs/2410.22939>

[42] Xu, R., Chen, C., Peng, J., Li, C., Huang, Y., Song, F., Yan, Y., & Xiong, Z. Toward RAW Object Detection: A New Benchmark and a New Model. CVPR 2023. <https://openaccess.thecvf.com/content/CVPR2023/html/Xu_Toward_RAW_Object_Detection_A_New_Benchmark_and_a_New_CVPR_2023_paper.html>

[43] Li, Z.-Y., Jin, X., Sun, B., Guo, C.-L., & Cheng, M.-M. Towards RAW Object Detection in Diverse Conditions. CVPR 2025. <https://arxiv.org/abs/2411.15678>

[44] Cui, Z., & Harada, T. RAW-Adapter: Adapting Pre-trained Visual Model to Camera RAW Images. ECCV 2024. <https://arxiv.org/abs/2408.14802>

[45] Gamrian, S., Barel, H., Li, F., Yoshimura, M., & Iso, D. Beyond RGB: Adaptive Parallel Processing for RAW Object Detection. ICCV 2025. <https://arxiv.org/abs/2503.13163>

[46] Guo, J., Gao, X., Yan, Y., Li, G., & Pu, J. Dark-ISP: Enhancing RAW Image Processing for Low-Light Object Detection. ICCV 2025. <https://arxiv.org/abs/2509.09183>

[47] Ljungbergh, W., Johnander, J., Petersson, C., & Felsberg, M. Raw or Cooked? Object Detection on RAW Images. SCIA 2023. <https://arxiv.org/abs/2301.08965>

[48] Chen, K., Xiao, J., Zhang, L., Shi, K., & Gu, S. Task-Aware Image Signal Processor for Advanced Visual Perception. CVPR 2026. <https://arxiv.org/abs/2509.13762>

[49] Fatima, M., Agnihotri, S., Gandikota, K. V., Moeller, M., & Keuper, M. RAWDet-7: A Multi-Scenario Benchmark for Object Detection and Description on Quantized RAW Images. 2026. <https://arxiv.org/abs/2602.03760>

[50] Berdan, R., Besbinar, B., Reinders, C., Otsuka, J., & Iso, D. ReRAW: RGB-to-RAW Image Reconstruction via Stratified Sampling for Efficient Object Detection on the Edge. CVPR 2025. <https://arxiv.org/abs/2503.03782>
