---
title: "相机如何把光变成数据: 从投影、曝光到神经场的统一数学视角"
date: 2026-07-10
categories:
  - tech
tags:
  - computational-photography
  - camera-geometry
  - computational-optics
  - light-field
  - inverse-rendering
  - deep-learning
excerpt: "从一条光线和一次有限测量出发, 把投影几何、镜头曝光、焦点堆栈、光场与光度成像统一成同一个反问题, 再用零空间、Bayes 风险和可辨识性解释深度学习论文为什么这样设计。"
custom_css:
  - comp-photo-first-principles
---

我们看到的世界不是像素组成的。像素是相机把连续世界压缩以后留下的数字。

上一篇[《从 RAW 到图像: 相机前端的统一数学视角》]({% post_url 2026-07-10-learned-isp-mathematical-view %})从传感器观测出发，把 learned ISP 写成 Bayes 决策。这篇把视野再往前推一步: 在 RAW 出现以前，相机究竟怎样把连续光线变成有限观测?

文章仍然从《计算摄像学: 成像模型理论与深度学习实践》中关于相机几何、镜头与曝光、焦点堆栈、光场和光度成像的内容出发 [1]，但我不想按教材目录逐节复述。更有意思的问题是:

> 一台相机究竟丢掉了光的哪些维度；为了完成某个任务，我们应该用额外测量找回它们，还是用先验去猜它们?

这个问题可以把几件看似分散的事情连起来。投影几何研究三维位置怎样被压到二维；孔径和曝光把方向、时间与光子数积分掉；焦点堆栈和光场用额外采样找回方向或深度；光度模型追问每个光子来自怎样的光照、形状和材质。深度学习并没有创造另一套成像规律，它主要做三件事:

1. 用网络参数化难以手写的场景先验；
2. 用可微成像模型把物理一致性变成训练信号；
3. 让任务风险反过来选择相机应该怎样测量。

下面只围绕一套符号展开, 并按四步推进:

1. 先写清世界怎样经过测量核变成像素;
2. 再从零空间、Bayes 风险和 Fisher 信息推出三条共同结论;
3. 然后分别看几何、光学、光线场和光度成像如何改变测量或先验;
4. 最后把固定输入的重建问题闭合成“估计不确定性、选择下一次测量、用新证据检验模型”的主动相机。

这样组织的目的不是把所有任务变成同一种算法, 而是让每一类论文都回答同样三个问题: 它测到了什么, 它依赖什么先验, 它怎样处理不可辨识性。

## 从一条光线到一个像素

### 世界不是二维图像，而是光线的集合

设场景状态为:

$$
X
=
\left(
G,\rho,f_r,E,m
\right),
$$

其中 $G$ 表示几何和可见性，$\rho$ 表示反照率，$f_r$ 表示更一般的 BRDF，$E$ 表示光照，$m$ 表示运动。场景状态决定空间中沿方向 $\omega$ 传播的光谱辐亮度:

$$
\mathcal{L}_X(q,\omega,\lambda,t).
$$

这里 $q$ 是空间位置，$\omega$ 是方向，$\lambda$ 是波长，$t$ 是时间。普通照片没有保留这个高维函数。它只保留一组由镜头、孔径、快门、传感器和采样方式共同定义的积分。

令一次拍摄动作写成:

$$
a_k
=
\left(
K_k,T_k,f_k,z_{f,k},\mathcal{A}_k,\tau_k,g_k,c_k
\right),
$$

其中 $K_k,T_k$ 是内外参，$f_k$ 是焦距，$z_{f,k}$ 是对焦距离，$\mathcal{A}_k$ 是孔径，$\tau_k$ 是曝光时间，$g_k$ 是增益，$c_k$ 是颜色通道。第 $k$ 次拍摄中，像素 $p$ 的期望光电子数可以统一写成:

$$
\mu_{k,p,c}(X,a_k)
=
\eta_c
\int_{t_k}^{t_k+\tau_k}
\int_{\Lambda}
\int_{\mathcal{A}_k}
S_c(\lambda)
W_{k,p}(q,\omega;a_k)
\mathcal{L}_X(q,\omega,\lambda,t)
\,dq\,d\omega\,d\lambda\,dt.
$$

$W_{k,p}$ 是最关键的量。它不是一个抽象权重而已，而是相机的测量核:

- 投影几何决定哪些世界点可能落到像素 $p$；
- 镜头和孔径决定这些光线以怎样的 PSF 混合；
- 对焦位置决定不同深度的失焦程度；
- 曝光决定沿时间积分多长；
- 光谱响应 $S_c$ 决定不同波长如何被压成颜色通道。

光子到达可以近似为 Poisson 过程，读出电路再加入近似高斯噪声:

$$
N_{k,p,c}
\sim
\operatorname{Poisson}
\left(
\mu_{k,p,c}
\right),
$$

$$
R_{k,p,c}
=
Q_B
\left(
b_c+g_kN_{k,p,c}+\epsilon_{r,c}
\right),
\qquad
\epsilon_{r,c}\sim\mathcal{N}(0,\sigma_{r,c}^2).
$$

把所有细节收起来，整台相机就是一个条件分布:

$$
R_a
\sim
p_{\psi}(r\mid X,a).
$$

这里 $a$ 决定测量方式，$\psi$ 表示真实但未必完全已知的相机参数。以后看到深度估计、去模糊、HDR、光场重建、NeRF 或逆渲染，都可以先问一句: 它们假设的 $p_{\psi}(r\mid X,a)$ 到底是什么?

### 从成像反问题到 Bayes 决策

我们通常不需要恢复整个世界状态 $X$。任务只关心某个目标:

$$
T=\tau(X).
$$

$T$ 可以是深度、相机位姿、全焦图、HDR 辐亮度、一个新视角、表面法线、材质参数，也可以是检测标签。给定观测 $R_a=r$，最优输出由损失函数决定:

$$
\delta_a^{\ast}(r)
=
\arg\min_{d}
\mathbb{E}
\left[
\ell(d,T)
\mid
R_a=r,a
\right].
$$

这和上一篇分析 learned ISP 的 Bayes 决策形式是同一件事。L2 损失选择条件均值，L1 选择条件中位数，负对数似然试图恢复条件分布。不同之处在于，这次测量动作 $a$ 也可以被设计。

如果相机能主动选择曝光、焦点、孔径、视角或编码光学，问题会进一步变成:

$$
a^{\ast}
=
\arg\min_a
\left\{
\inf_{\delta}
\mathbb{E}
\left[
\ell(\delta(R_a,a),T)
\right]
+
\lambda C(a)
\right\},
$$

其中 $C(a)$ 可以表示拍摄时间、能耗、运动伪影、硬件复杂度或制造约束。

这个式子比“用神经网络处理照片”更接近计算摄像学的本质:

> 不只学习怎样解释已有像素，还要为目标任务设计应该采哪些光。

## 一张问题架构图: 论文究竟在改什么

有了 $X$、$\mathcal{L}$、$\mathcal{M}_a$、$R$ 和 $T$，相关论文就不必按网络名字排成一条时间线。下面这张图先把世界生成观测和模型解释观测分开，再把几何、光学、光线场与光度分解放成并行的后验分支。

{% include computational-camera-research-map.html %}

图中的四条推断路径分别可以写成:

$$
q_{\theta_G}(G\mid R,a),
\qquad
q_{\theta_S}(S\mid R,a),
\qquad
q_{\theta_L}(\mathcal{L}\mid R,a),
\qquad
q_{\theta_P}(\rho,n,E,f_r\mid R,a).
$$

它们不是四个必须依次执行的网络模块。一个方法可能只估计深度；另一个方法直接恢复清晰图像；NeRF 同时耦合几何与方向相关辐射；逆渲染则希望进一步分离光照、材质和形状。把这些工作画成串行链，会误以为后者总是在前者输出上继续处理。

同样，CNN、Transformer、cost volume、U-Net 也不是新的物理阶段。它们只是参数化上述条件分布或优化更新的不同函数族。真正需要先确定的是: 随机变量是什么，测量算子是什么，目标又是什么。

## 三个结构性推论

在进入具体领域之前, 先把统一模型能直接推出的结论说完。后面的四条技术分支不会再各自发明一套解释; 它们只是用不同物理变量具体化这三件事: 零空间决定单次观测的边界, 互补测量决定哪些歧义能够被消除, 任务风险决定哪些信息值得付成本去获取。

### 没测到的信息，网络只能从先验里补

先看无噪声线性近似:

$$
r=\mathcal{M}_a x.
$$

如果存在两个场景 $x_1\ne x_2$ 满足:

$$
\mathcal{M}_a x_1
=
\mathcal{M}_a x_2,
$$

那么任何只读取 $r$ 的确定性估计器 $F$ 都必须有:

$$
F(\mathcal{M}_a x_1)
=
F(\mathcal{M}_a x_2).
$$

也就是说，它不可能同时对两个场景都输出正确答案。令 $z=x_1-x_2$，则:

$$
z\in\operatorname{Null}(\mathcal{M}_a).
$$

相机压缩掉的信息正是测量算子的零空间。单目投影丢掉射线深度，有限孔径照片积分掉角度，长曝光积分掉时间，饱和与量化合并不同辐照度。网络可以利用自然场景统计选择零空间中的一个“常见解”，但不能把这个选择说成由输入唯一恢复出的真值。

Bayes 公式把这件事说得更直接:

$$
p(x\mid r,a)
\propto
p(r\mid x,a)p(x).
$$

沿着测量无法区分的方向，likelihood 几乎不变，posterior 的形状就主要由先验 $p(x)$ 决定。训练数据、预训练模型和网络结构都会进入这个先验。

> 物理测量决定哪些结论有证据，学习先验决定证据不足时更愿意相信什么。

### 多拍一张是否有用，取决于零空间有没有改变

假设拍摄 $K$ 次:

$$
\mathbf{r}
=
\begin{bmatrix}
\mathcal{M}_{a_1}\\
\mathcal{M}_{a_2}\\
\vdots\\
\mathcal{M}_{a_K}
\end{bmatrix}
x.
$$

联合测量的零空间满足:

$$
\operatorname{Null}(\mathbf{M})
=
\bigcap_{k=1}^{K}
\operatorname{Null}(\mathcal{M}_{a_k}).
$$

因此，多张几乎相同的照片只是重复采样，未必增加多少信息；改变视角、焦点、曝光、光照或子孔径，才可能让不同测量的零空间互补。

这个结论统一解释了:

- 双目为什么能从视差恢复深度；
- 焦点堆栈为什么能从清晰度随焦距的变化恢复深度；
- 多曝光为什么能覆盖单次拍摄的饱和区和噪声区；
- 光度立体为什么通过改变光照分离法线与反照率；
- Dual Pixel 为什么比单张 RGB 多一个与失焦相关的相位差观测。

所以“多帧网络”是否合理，不能只看它有没有 temporal attention。先要看每一帧的 $\mathcal{M}_{a_k}$ 是否真的提供了互补约束。

### 最优测量由任务定义

在局部高斯近似下，设观测均值为 $\mu_a(X)$，噪声协方差为 $\Sigma_a$，Jacobian 为:

$$
J_a(X)
=
\frac{\partial \mu_a(X)}{\partial X}.
$$

测量对场景参数提供的 Fisher 信息近似为:

$$
\mathcal{I}_a(X)
=
J_a(X)^{\top}
\Sigma_a^{-1}
J_a(X).
$$

增大曝光可能减小相对 shot noise，却会增加运动模糊与饱和；增大孔径会收集更多光子，却会让失焦核对深度更敏感；编码孔径可能降低普通成像质量，却让不同深度的 PSF 更容易区分。不存在脱离目标的“信息最多相机”。

若任务只关心 $T=\tau(X)$，令 $J_{\tau}=\partial\tau/\partial X$。Cramer-Rao bound 在线性化后给出任务变量的协方差下界:

$$
\operatorname{Cov}(\hat T)
\succeq
J_{\tau}
\mathcal{I}_a^{-1}
J_{\tau}^{\top}.
$$

因此，一种局部测量设计准则是最小化任务相关方差:

$$
a^{\ast}
=
\arg\min_a
\operatorname{tr}
\left(
W
J_{\tau}
\mathcal{I}_a^{-1}
J_{\tau}^{\top}
\right)
+
\lambda C(a).
$$

给人看的照片、给检测器的输入、给深度估计器的编码图像，权重 $W$ 和任务 Jacobian 都不同，因此最优曝光和最优镜头也可以不同。Deep Optics、Neural Auto-Exposure 和 Neural Exposure Fusion 的共同点，正是把这个选择交给任务风险，而不是固定图像质量指标 [8,10,11]。

## 光线落在哪里: 投影几何与可微重投影

几何分支首先问: 中心投影把三维位置压成二维以后, 哪些自由度进入了零空间? 单目方法用场景先验选择深度, 多视角方法则通过改变相机位姿, 让原本沿射线不可区分的点产生可测视差。

### 中心投影为什么天然丢失深度

一个世界点的齐次坐标记为 $X_w=(X,Y,Z,1)^{\top}$。它先由外参进入相机坐标系:

$$
X_c
=
RX_w+t.
$$

针孔投影写成:

$$
\tilde p
\sim
K
\begin{bmatrix}
R&t
\end{bmatrix}
X_w.
$$

齐次比例符号 $\sim$ 隐藏了真正的信息损失。若 $X_c=(X_c,Y_c,Z_c)^{\top}$，归一化坐标是:

$$
\pi(X_c)
=
\left(
\frac{X_c}{Z_c},
\frac{Y_c}{Z_c}
\right).
$$

沿同一射线缩放不会改变像素:

$$
\pi(\alpha X_c)
=
\pi(X_c),
\qquad
\alpha>0.
$$

因此，单张图像中的绝对深度和尺度不在投影测量里。单目深度网络能输出深度，是因为它从训练数据中学到了物体尺寸、地面布局、透视纹理等统计先验；这不等于单张图像在几何上突然变得可逆。

<figure class="cp-principle-figure">
  <div class="cp-diagram" aria-label="投影几何、对应关系和可微 bundle adjustment 图">
    <svg viewBox="0 0 1120 560" role="img" aria-labelledby="cp-geom-title cp-geom-desc" xmlns="http://www.w3.org/2000/svg">
      <title id="cp-geom-title">从中心投影到学习式几何优化</title>
      <desc id="cp-geom-desc">两个相机从不同视角观察三个世界点，对应点约束产生深度和位姿，神经网络提供匹配与更新，bundle adjustment 保持投影一致性。</desc>
      <defs>
        <marker id="cp-arrow-geom" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path fill="context-stroke" d="M 0 0 L 10 5 L 0 10 z" />
        </marker>
      </defs>
      <text class="cp-section-label" x="48" y="38">世界点与多视角投影</text>
      <circle cx="120" cy="285" r="8" fill="#172033" />
      <circle cx="355" cy="355" r="8" fill="#172033" />
      <text class="cp-label" x="120" y="312">camera C1</text>
      <text class="cp-label" x="355" y="383">camera C2</text>
      <rect class="cp-plane" x="260" y="115" width="16" height="275" />
      <rect class="cp-plane" x="500" y="115" width="16" height="275" />
      <circle cx="760" cy="145" r="7" fill="#3376a6" />
      <circle cx="760" cy="270" r="7" fill="#3376a6" />
      <circle cx="760" cy="405" r="7" fill="#3376a6" />
      <text class="cp-label" x="810" y="130">3D points X</text>
      <path class="cp-ray" d="M 120 285 L 760 145" />
      <path class="cp-ray" d="M 120 285 L 760 270" />
      <path class="cp-ray" d="M 120 285 L 760 405" />
      <path class="cp-ray cp-ray--alt" d="M 355 355 L 760 145" />
      <path class="cp-ray cp-ray--alt" d="M 355 355 L 760 270" />
      <path class="cp-ray cp-ray--alt" d="M 355 355 L 760 405" />
      <g class="cp-node cp-node--geometry">
        <rect x="70" y="445" width="230" height="68" rx="7" />
        <text x="185" y="473">对应 / cost volume</text>
        <text class="cp-sub" x="185" y="495">learned matching prior</text>
      </g>
      <g class="cp-node cp-node--learning">
        <rect x="445" y="445" width="230" height="68" rx="7" />
        <text x="560" y="473">深度与位姿更新</text>
        <text class="cp-sub" x="560" y="495">amortized / recurrent solver</text>
      </g>
      <g class="cp-node cp-node--loss">
        <rect x="820" y="445" width="230" height="68" rx="7" />
        <text x="935" y="473">重投影 / BA</text>
        <text class="cp-sub" x="935" y="495">geometric consistency</text>
      </g>
      <path class="cp-edge cp-edge--geometry" d="M 300 479 L 445 479" marker-end="url(#cp-arrow-geom)" />
      <path class="cp-edge cp-edge--loss" d="M 675 479 L 820 479" marker-end="url(#cp-arrow-geom)" />
    </svg>
  </div>
  <figcaption><b>图 2:</b> 几何学习不是跳过投影模型。网络可以提供对应关系、置信度和优化更新，但多视角结果仍要在同一套投影约束下对齐。单目方法缺少的绝对尺度，来自数据先验而不是中心投影本身。</figcaption>
</figure>

### 多视角把深度变成对应问题

同一个世界点在两台相机中满足:

$$
\tilde p_j
\sim
K_j(R_jX+t_j),
\qquad j\in\{1,2\}.
$$

若对应点已知，两条射线的交会给出三角化。把深度候选离散为 $d\in\mathcal{D}$，现代 stereo 或 multi-view 网络常构造 cost volume:

$$
C_p(d)
=
\left\|
\phi_1(p)
-
\phi_2
\left(
\pi
\left(
T_{21}
\Pi^{-1}(p,d)
\right)
\right)
\right\|^2.
$$

$\Pi^{-1}(p,d)$ 把像素沿射线提升到深度 $d$，$\phi$ 是图像特征。若把负 cost 归一化成概率:

$$
q(d\mid p,I_1,I_2)
=
\frac{\exp(-C_p(d)/\tau)}
{\sum_{d'}\exp(-C_p(d')/\tau)},
$$

则 soft-argmin 深度是:

$$
\hat d(p)
=
\sum_{d\in\mathcal{D}}
d\,q(d\mid p,I_1,I_2).
$$

这解释了 cost volume 的数学角色: 它不是普通的 feature stack，而是对离散深度后验的显式参数化。3D convolution 在深度和空间邻域上正则化这个后验；attention 则把“找对应点”改写成内容自适应的非局部匹配。

### 自监督深度到底监督了什么

给定目标帧 $I_t$ 和源帧 $I_s$，网络预测深度 $D_{\theta}$ 与位姿 $T_{\phi}$。源图像可以被重投影到目标视角:

$$
\hat I_t(p)
=
I_s
\left(
\pi
\left(
T_{t\leftarrow s}
D_{\theta}(p)K^{-1}\tilde p
\right)
\right).
$$

训练损失常写成:

$$
\mathcal{L}_{photo}
=
\sum_p
m(p)
\rho
\left(
I_t(p)-\hat I_t(p)
\right),
$$

其中 $m(p)$ 用来处理遮挡、动态物体和无效投影，$\rho$ 是鲁棒 photometric loss。SfM-Learner 的关键不是“无标签也能学深度”这句口号，而是把 view synthesis 当作几何 latent variables 的 analysis-by-synthesis 监督 [4]。

但这个损失暗含 brightness constancy:

$$
I_t(p)
\approx
I_s(p'),
$$

曝光变化、高光、阴影、非 Lambertian 反射和遮挡都会破坏它。因此，一个网络即使把重投影误差降得很低，也可能用错误深度解释光度变化。几何与光度并不是互相独立的两块知识；光度模型决定几何自监督是否可信。

### 用同一套公式读四类几何网络

SfM-Learner 直接预测 $D_{\theta}$ 与 $T_{\phi}$，本质是摊销求解器 [4]:

$$
(\hat D,\hat T)
=
F_{\theta}(I_{t-k:t+k}).
$$

DROID-SLAM 则保留迭代优化结构，在 dense bundle adjustment 层中反复更新深度和位姿 [5]:

$$
(D^{n+1},T^{n+1})
=
\mathcal{U}_{\theta}
\left(
D^n,T^n,\nabla\mathcal{L}_{reproj}
\right).
$$

它学的不是最终答案本身，而是特征、置信度和优化更新规则。这个函数族比一次前向回归更接近传统 BA 的算法结构。

BARF 同时优化辐射场参数和相机位姿 [6]:

$$
\min_{\theta,\{T_i\}}
\sum_{i,p}
\left\|
I_i(p)
-
\mathcal{R}
\left(
F_{\theta},T_i,p
\right)
\right\|^2.
$$

高频 positional encoding 会让位姿优化的 basin of attraction 变窄，因此 BARF 使用 coarse-to-fine 频率调度。这个设计不是经验性的“先低频后高频”，而是在改变优化目标对位姿的局部曲率。

DUSt3R 走了另一条路。它不要求先知道相机内外参，而是从图像对直接回归 pointmap [7]:

$$
(\hat X^{1\rightarrow 1},\hat X^{2\rightarrow 1})
=
F_{\theta}(I_1,I_2).
$$

这放松了显式标定和三角化的前置条件，但没有消灭几何约束。多图像时仍需要把 pairwise pointmaps 做全局对齐；绝对尺度和坐标 gauge 也仍需固定。更准确的理解是: DUSt3R 用大规模预训练把“对应 + 标定 + 三角化”的组合先验压进 pointmap 回归，再把跨图一致性留给 alignment。

## 收到多少光: 透镜、孔径、曝光与噪声

光学分支把问题从“落在哪里”推进到“以什么 PSF、多少光子和多长时间被测量”。孔径、焦点与曝光不是拍摄后的元数据, 而是直接改变 likelihood 的测量参数。

### 针孔模型只回答位置，不回答能量

真实镜头首先满足近轴薄透镜近似:

$$
\frac{1}{z}
+
\frac{1}{s(z)}
=
\frac{1}{f},
$$

于是物距 $z$ 的理想像距为:

$$
s(z)
=
\frac{fz}{z-f}.
$$

若传感器放在对焦距离 $z_f$ 对应的像面:

$$
s_f
=
\frac{fz_f}{z_f-f},
$$

那么不在焦平面上的点不会汇聚到一个像素，而会形成直径近似为:

$$
c(z;z_f,D)
=
D
\left|
\frac{s_f}{s(z)}-1
\right|
=
\frac{Df|z-z_f|}
{z(z_f-f)}
$$

的 circle of confusion，其中 $D$ 是孔径直径。这个式子同时说明两件事:

- 增大孔径 $D$ 会让离焦深度更容易区分；
- 同一个增大孔径也会让非焦平面内容更模糊。

把不同深度层的清晰辐照记为 $x_z$，成像可以写成空间变化卷积:

$$
y(p)
=
\int
\left[
h_{z,z_f,D}
\ast
x_z
\right](p)
\,dz.
$$

真实镜头像差会让 $h$ 随位置、颜色和视场变化。单张去失焦不是一个固定 kernel deconvolution，而是同时估计深度相关 PSF 与清晰图像的 blind inverse problem。

<figure class="cp-principle-figure">
  <div class="cp-diagram" aria-label="镜头、曝光、噪声和任务联合设计图">
    <svg viewBox="0 0 1120 560" role="img" aria-labelledby="cp-optics-title cp-optics-desc" xmlns="http://www.w3.org/2000/svg">
      <title id="cp-optics-title">镜头把光线变成深度相关 PSF，曝光把信号沿时间积分</title>
      <desc id="cp-optics-desc">场景点经过孔径和透镜后在传感器形成失焦核，孔径、曝光与增益共同决定光子数、模糊、饱和和噪声，任务损失可以反向优化这些测量参数。</desc>
      <defs>
        <marker id="cp-arrow-optics" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path fill="context-stroke" d="M 0 0 L 10 5 L 0 10 z" />
        </marker>
      </defs>
      <text class="cp-section-label" x="48" y="38">有限孔径与有限曝光的测量</text>
      <circle cx="105" cy="270" r="7" fill="#3376a6" />
      <text class="cp-label" x="105" y="296">scene point</text>
      <ellipse cx="390" cy="270" rx="22" ry="145" fill="#fff7e5" stroke="#a26b12" stroke-width="3" />
      <circle class="cp-aperture" cx="390" cy="205" r="7" />
      <circle class="cp-aperture" cx="390" cy="270" r="7" />
      <circle class="cp-aperture" cx="390" cy="335" r="7" />
      <line class="cp-sensor-line" x1="730" y1="135" x2="730" y2="405" />
      <path class="cp-ray" d="M 105 270 L 390 205 L 730 242" />
      <path class="cp-ray" d="M 105 270 L 390 270 L 730 270" />
      <path class="cp-ray" d="M 105 270 L 390 335 L 730 306" />
      <ellipse cx="730" cy="273" rx="11" ry="43" fill="#f7e5ea" stroke="#a94a65" stroke-width="2" />
      <text class="cp-label" x="830" y="278">depth-dependent PSF</text>
      <g class="cp-node cp-node--optics">
        <rect x="70" y="430" width="220" height="68" rx="7" />
        <text x="180" y="458">镜头参数 phi</text>
        <text class="cp-sub" x="180" y="480">aperture · phase · aberration</text>
      </g>
      <g class="cp-node cp-node--sensor">
        <rect x="340" y="430" width="220" height="68" rx="7" />
        <text x="450" y="458">曝光动作 a</text>
        <text class="cp-sub" x="450" y="480">tau · gain · focus</text>
      </g>
      <g class="cp-node cp-node--learning">
        <rect x="610" y="430" width="220" height="68" rx="7" />
        <text x="720" y="458">神经解码器</text>
        <text class="cp-sub" x="720" y="480">posterior estimator</text>
      </g>
      <g class="cp-node cp-node--loss">
        <rect x="880" y="430" width="180" height="68" rx="7" />
        <text x="970" y="458">任务风险</text>
        <text class="cp-sub" x="970" y="480">image / depth / detection</text>
      </g>
      <path class="cp-edge cp-edge--optics" d="M 290 464 L 340 464" marker-end="url(#cp-arrow-optics)" />
      <path class="cp-edge cp-edge--learning" d="M 560 464 L 610 464" marker-end="url(#cp-arrow-optics)" />
      <path class="cp-edge cp-edge--loss" d="M 830 464 L 880 464" marker-end="url(#cp-arrow-optics)" />
      <path class="cp-edge cp-edge--loss" d="M 970 430 C 1010 365, 1010 90, 390 92 C 220 92, 160 225, 180 430" marker-end="url(#cp-arrow-optics)" />
    </svg>
  </div>
  <figcaption><b>图 3:</b> 光学不是网络之前不可改变的预处理。透镜与孔径决定 PSF，曝光决定光子和时间积分，网络负责解码；在可微成像模型中，任务梯度还可以继续传回镜头、孔径或曝光策略。</figcaption>
</figure>

### 曝光时间既增加光子，也混合运动

若场景在曝光期间运动，观测是时间积分:

$$
y(p)
=
\frac{1}{\tau}
\int_{0}^{\tau}
\left[
h_{z(t)}\ast x_t
\right](p)
dt.
$$

对于平移运动 $u(t)$，可进一步写成:

$$
y(p)
=
\frac{1}{\tau}
\int_0^{\tau}
x_0(p-u(t))dt.
$$

延长曝光让期望光子数近似线性增长:

$$
\mu
=
\lambda\tau,
$$

但 shot noise 标准差只按平方根增长。考虑读噪声后:

$$
\operatorname{SNR}
\approx
\frac{\lambda\tau}
{\sqrt{\lambda\tau+\sigma_r^2}}.
$$

这就是“长曝光更干净”的来源。但当 $x_t$ 随时间变化时，增加的光子与增加的运动模糊同时出现；当响应达到 full-well capacity 或 ADC 上限时，继续曝光还会进入 clipping 的不可逆区域。

因此，曝光并不是一个只控制亮度的标量。令时间积分后的期望光子数为:

$$
m_{\tau}(x)
=
\int_0^{\tau}
\mathcal{M}_{a,z(t)}x_tdt.
$$

更严谨的 likelihood 是对未观测光子计数 $N$ 边缘化:

$$
p(r\mid x,\tau)
=
\sum_{N=0}^{\infty}
p_{sensor}(r\mid N)
\operatorname{Poisson}
\left(
N;m_{\tau}(x)
\right).
$$

运动和失焦进入 $m_{\tau}(x)$，shot noise 由 Poisson 项决定，读噪声、饱和与量化进入 $p_{sensor}$。改变曝光时间会同时改变这三部分，而不是只把最终像素乘一个亮度系数。

### 深度学习方法到底改了哪一个变量

Learning to See in the Dark 使用短曝光低光 RAW 和长曝光参考图训练端到端网络 [9]。在统一模型里，它固定测量动作 $a_{short}$，学习的是:

$$
F_{\theta}(R_{short})
\approx
\mathbb{E}
\left[
Y_{long}
\mid
R_{short}
\right].
$$

它没有增加低光测量中的光子。极暗区域的细节一旦落入宽后验，网络输出就会更多依赖训练先验。长曝光 reference 定义了目标，RAW likelihood 保留了尽可能多的微弱信号。

Deep Optics 则连测量核也一起学习 [8]。令可制造的光学参数为 $\phi$，成像模拟器记为 $\mathcal{M}(\phi)$，解码器记为 $F(\theta)$:

$$
\min_{\phi,\theta}
\mathbb{E}
\left[
\ell
\left(
F_{\theta}(\mathcal{M}_{\phi}(X)),T
\right)
\right]
+
\lambda\Omega(\phi).
$$

$\Omega(\phi)$ 约束相位、表面形状、色散或制造范围。论文用 coded defocus 和色差给单目深度增加可解码的深度相关线索。网络不是凭语义猜深度，而是和镜头一起把原本相似的场景深度映射成更可区分的 PSF。

Neural Auto-Exposure 学习策略:

$$
\tau_t
=
\pi_{\alpha}
\left(
R_{1:t-1},h_{t-1}
\right),
$$

并以检测损失而不是平均亮度驱动曝光 [10]。这意味着隧道出口、逆光车辆与阴影区域的曝光选择，取决于哪些像素对检测风险更重要。

Neural Exposure Fusion 进一步保留多曝光观测，在 feature domain 选择局部信息 [11]:

$$
Z(p)
=
\sum_{k=1}^{K}
\alpha_k(p)
\phi(R_{\tau_k})(p),
\qquad
\sum_k\alpha_k(p)=1.
$$

这里 $\alpha_k(p)$ 是跨曝光 attention。亮区可以读取短曝光，暗区可以读取长曝光，而不必先压成一张面向人眼的 tone-mapped HDR 图。

Dual Pixel 与 Quad Pixel 又代表另一种路线。每个像素从不同子孔径得到两个或四个观测:

$$
R^{(j)}
=
\mathcal{M}^{(j)}_{a}(X)+\eta^{(j)},
\qquad
j=1,\ldots,J.
$$

子孔径间的相位差与失焦方向、大小相关。它们不是把同一张模糊图复制多份，而是改变了联合测量的零空间，因此能为去失焦和深度提供新的物理线索 [12,13]。

## 被压掉的方向如何回来: 焦点堆栈、光场与神经场

光线场分支关心普通照片积分掉的角度维。焦点、子孔径和视角采样提供互补投影; neural field 则选择一种连续表示, 把这些观测约束耦合到同一个场景中。

### 一张普通照片是光场的角度积分

在自由空间中，可以用两个平面参数化一条光线。为简化公式，只写一维空间坐标 $x$ 和一维孔径坐标 $u$:

$$
L(x,u).
$$

普通相机在有限孔径下对方向积分:

$$
I(x)
=
\int_{\mathcal{A}}
L(x,u)du.
$$

不同对焦平面对应对光场先 shear 再积分 [14,15]:

$$
I_{\alpha}(x)
=
\int_{\mathcal{A}}
L(x+\alpha u,u)du.
$$

焦点堆栈是一组不同 $\alpha_k$ 的投影:

$$
\mathbf{I}
=
\begin{bmatrix}
\mathcal{A}_{\alpha_1}\\
\mathcal{A}_{\alpha_2}\\
\vdots\\
\mathcal{A}_{\alpha_K}
\end{bmatrix}
L
+
\eta.
$$

因此，从焦点堆栈恢复光场很像有限角度 tomography；从堆栈估计深度，则是在寻找哪个 shear 让某个场景点的光线重新对齐。

<figure class="cp-principle-figure">
  <div class="cp-diagram" aria-label="焦点堆栈、光场、EPI 和神经场关系图">
    <svg viewBox="0 0 1120 590" role="img" aria-labelledby="cp-rays-title cp-rays-desc" xmlns="http://www.w3.org/2000/svg">
      <title id="cp-rays-title">光线场经过 shear 和积分形成焦点堆栈，神经模型恢复方向与几何结构</title>
      <desc id="cp-rays-desc">双平面参数化的光线在 EPI 中形成与视差相关的斜线，不同重聚焦参数产生焦点堆栈，模型可以估计深度、直接表示光场或通过三维体渲染生成新视角。</desc>
      <defs>
        <marker id="cp-arrow-rays" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path fill="context-stroke" d="M 0 0 L 10 5 L 0 10 z" />
        </marker>
      </defs>
      <text class="cp-section-label" x="48" y="38">光线方向没有消失，只是被积分了</text>
      <rect class="cp-plane" x="150" y="92" width="18" height="320" />
      <rect class="cp-plane" x="540" y="92" width="18" height="320" />
      <text class="cp-label" x="159" y="75">u plane</text>
      <text class="cp-label" x="549" y="75">x plane</text>
      <path class="cp-ray" d="M 159 130 L 549 220" />
      <path class="cp-ray cp-ray--alt" d="M 159 230 L 549 220" />
      <path class="cp-ray" d="M 159 340 L 549 220" />
      <path class="cp-ray" d="M 159 165 L 549 345" />
      <path class="cp-ray cp-ray--alt" d="M 159 300 L 549 345" />
      <circle cx="549" cy="220" r="7" fill="#a94a65" />
      <circle cx="549" cy="345" r="7" fill="#a94a65" />
      <g class="cp-node cp-node--learning">
        <rect x="700" y="75" width="300" height="70" rx="7" />
        <text x="850" y="103">直接光线表示 L(x,u)</text>
        <text class="cp-sub" x="850" y="125">4D CNN · EPI · Light Field Network</text>
      </g>
      <g class="cp-node cp-node--optics">
        <rect x="700" y="205" width="300" height="70" rx="7" />
        <text x="850" y="233">焦点堆栈 I_alpha</text>
        <text class="cp-sub" x="850" y="255">shear + integrate · focus volume</text>
      </g>
      <g class="cp-node cp-node--sensor">
        <rect x="700" y="335" width="300" height="70" rx="7" />
        <text x="850" y="363">三维辐射场 sigma,c</text>
        <text class="cp-sub" x="850" y="385">ray marching · volume rendering</text>
      </g>
      <path class="cp-edge cp-edge--learning" d="M 558 220 C 625 145, 660 112, 700 110" marker-end="url(#cp-arrow-rays)" />
      <path class="cp-edge cp-edge--optics" d="M 558 280 C 620 255, 655 242, 700 240" marker-end="url(#cp-arrow-rays)" />
      <path class="cp-edge cp-edge--sensor" d="M 558 345 C 620 370, 655 372, 700 370" marker-end="url(#cp-arrow-rays)" />
      <g class="cp-node cp-node--loss">
        <rect x="300" y="475" width="520" height="68" rx="7" />
        <text x="560" y="503">共同约束: 同一场景点跨视角 / 焦点的光线一致性</text>
        <text class="cp-sub" x="560" y="525">geometry consistency · refocus consistency · novel-view loss</text>
      </g>
      <path class="cp-edge cp-edge--loss" d="M 550 412 L 550 475" marker-end="url(#cp-arrow-rays)" />
    </svg>
  </div>
  <figcaption><b>图 4:</b> 焦点堆栈、传统光场和神经辐射场不是互相替代的名词。它们分别观测或参数化不同的数学对象，但都依赖同一条约束：属于同一场景点的光线必须在视角、焦点或体渲染下保持一致。</figcaption>
</figure>

### EPI 斜率为什么就是视差

考虑位于深度 $z$ 的 Lambertian 点。当相机或子孔径坐标从 $u$ 移动时，它在图像中的位置近似满足:

$$
x(u)
=
x_0+u d,
$$

其中视差:

$$
d
\propto
\frac{bf}{z}.
$$

于是固定另一维后，epipolar-plane image 中同一个三维点形成一条直线，斜率编码视差。EPINET 沿水平、垂直和对角 EPI 组织卷积，不只是因为“多方向特征更丰富”，而是把已知的 epipolar geometry 写入感受野 [18]。

若直接对 4D 光场做任意 2D CNN，网络必须自己重新发现这种斜线结构。EPI-aware 架构缩小了函数族:

$$
\mathcal{F}_{EPI}
\subset
\mathcal{F}_{generic},
$$

通常能用更少数据学到更稳定的视差先验。

### 焦点体是离散深度后验

设焦点堆栈按对焦距离 $l_1,\ldots,l_K$ 排列。网络可以对每个像素输出“第 $k$ 帧最清晰”的概率:

$$
q_k(p)
=
p(k\text{ is in focus}\mid \mathbf{I},p),
\qquad
\sum_kq_k(p)=1.
$$

深度回归和不确定性分别是:

$$
\hat d(p)
=
\sum_{k=1}^{K}q_k(p)l_k,
$$

$$
\sigma_d(p)
=
\sqrt{
\sum_{k=1}^{K}
q_k(p)
\left(l_k-\hat d(p)\right)^2
}.
$$

Deep Depth from Focus 的 Differential Focus Volume 沿焦点维做一阶差分 [19]:

$$
V_k
=
Q_k-Q_{k+1}.
$$

当清晰度随焦点距离先升后降时，最清晰位置对应差分的零交叉。这个 architecture 的解释不是“3D CNN 更强”，而是它把 focus curve 的导数结构显式提供给网络，并把离散焦距选择写成概率回归。

### 从稀疏视角到完整光场: 必须说明谁在补零空间

Kalantari 等人的光场 view synthesis 把问题分成 disparity estimation 与 color prediction [16]:

$$
\hat I_v
=
\mathcal{W}
\left(
I_{src},\hat d_v
\right)
+
\Delta_{\theta}.
$$

warp 负责满足几何，residual 网络处理遮挡、反射与插值误差。这种 factorization 比直接生成所有像素更容易判断网络在“恢复”还是“补全”。

从单张图像合成 4D RGBD 光场则更加不适定 [17]。它先预测每条光线的深度，渲染 Lambertian 光场，再用第二个 CNN 补遮挡与非 Lambertian 效应。其隐含分解是:

$$
p(L\mid I)
=
\int
p(L\mid D,I)
p(D\mid I)
dD.
$$

几何能解释的部分交给显式渲染，真正没有观测到的遮挡射线交给数据先验。这个边界比一个黑箱 $I\rightarrow L$ 更清楚。

LLFF 用 multiplane image 表示局部光场，并结合 plenoptic sampling 理论给出拍摄密度建议 [20]。它提醒我们: 深度学习不能只优化 reconstruction network，采样轨迹也决定结果是否可恢复。

### 光场网络和 NeRF 的差别

Light Field Network 直接把一条射线 $r$ 映射为颜色 [21]:

$$
C(r)
=
F_{\theta}(r).
$$

它在推理时只需一次网络查询，但三维几何是隐含在射线函数里的。

NeRF 则先定义三维位置和观察方向上的密度与辐射 [22]:

$$
(\sigma,c)
=
F_{\theta}(x,d),
$$

再沿相机射线 $r(s)=o+sd$ 做体渲染:

$$
\hat C(r)
=
\int_{s_n}^{s_f}
T(s)
\sigma(r(s))
c(r(s),d)
ds,
$$

$$
T(s)
=
\exp
\left(
-\int_{s_n}^{s}
\sigma(r(u))du
\right).
$$

NeRF 的优势不是“MLP 能记住照片”，而是多个视角必须共享同一个三维场，遮挡由 transmittance $T(s)$ 处理。它把光场的一致性放进 3D volume rendering factorization 中。

但 NeRF 也不自动等于真实物理场。只要新视角渲染正确，密度、颜色和相机位姿之间仍可能有等价解释；未知曝光、反射和 transient objects 也可能被吸收到辐射场。它解决的是 view synthesis 的可辨识性，不必然解决材质与光照分解。

## 像素为何是这个亮度: 光度成像与逆渲染

光度分支最后追问亮度由谁造成: 几何、材质、光照与可见性在渲染方程里相乘和积分。改变光照或视角能够增加约束, 但 gauge freedom 仍要求我们明确哪些自由度由测量固定, 哪些由先验选择。

### 渲染方程把几何、材质和光照耦合起来

表面点 $x$ 沿观察方向 $\omega_o$ 的出射辐亮度满足:

$$
L_o(x,\omega_o)
=
L_e(x,\omega_o)
+
\int_{\Omega}
f_r(x,\omega_i,\omega_o)
L_i(x,\omega_i)
V(x,\omega_i)
\max(0,n^{\top}\omega_i)
d\omega_i.
$$

这里:

- $L_i$ 是入射光；
- $f_r$ 是材质的 BRDF；
- $V$ 是可见性与阴影；
- $n$ 是表面法线；
- $L_e$ 是自发光项。

一个像素暗，可能因为反照率低、表面背光、光源弱、被遮挡、镜头衰减、曝光不足或相机响应压缩。只看最终 RGB，变量之间天然耦合。

<figure class="cp-principle-figure">
  <div class="cp-diagram" aria-label="光照、形状、材质、可见性和相机响应的逆渲染图">
    <svg viewBox="0 0 1120 570" role="img" aria-labelledby="cp-photo-title cp-photo-desc" xmlns="http://www.w3.org/2000/svg">
      <title id="cp-photo-title">从渲染方程到神经逆渲染</title>
      <desc id="cp-photo-desc">光照照射带材质和法线的表面，阴影与可见性影响出射辐亮度，相机响应产生图像；逆渲染从多视角或多光照图像分解几何、材质和光照。</desc>
      <defs>
        <marker id="cp-arrow-photo" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path fill="context-stroke" d="M 0 0 L 10 5 L 0 10 z" />
        </marker>
      </defs>
      <text class="cp-section-label" x="48" y="38">Forward rendering</text>
      <circle cx="145" cy="110" r="28" fill="#fff0cc" stroke="#a26b12" stroke-width="2" />
      <text class="cp-label" x="145" y="157">illumination E</text>
      <path class="cp-edge cp-edge--optics" d="M 166 128 L 365 250" marker-end="url(#cp-arrow-photo)" />
      <path class="cp-surface" d="M 315 365 C 415 250, 550 225, 675 320 C 585 405, 430 430, 315 365 Z" />
      <path class="cp-edge cp-edge--geometry" d="M 505 315 L 505 220" marker-end="url(#cp-arrow-photo)" />
      <text class="cp-label" x="548" y="226">normal n</text>
      <circle class="cp-highlight" cx="590" cy="307" r="16" />
      <text class="cp-label" x="615" y="287">BRDF / visibility</text>
      <path class="cp-edge" d="M 640 306 L 790 245" marker-end="url(#cp-arrow-photo)" />
      <rect class="cp-chip" x="835" y="165" width="150" height="150" rx="8" />
      <text class="cp-label" x="910" y="340">camera response</text>
      <text class="cp-section-label" x="48" y="450">Inverse rendering</text>
      <g class="cp-node cp-node--optics">
        <rect x="170" y="420" width="190" height="70" rx="7" />
        <text x="265" y="448">光照 E</text>
        <text class="cp-sub" x="265" y="471">direction · spectrum</text>
      </g>
      <g class="cp-node cp-node--geometry">
        <rect x="390" y="420" width="190" height="70" rx="7" />
        <text x="485" y="448">形状 G</text>
        <text class="cp-sub" x="485" y="471">normal · depth · visibility</text>
      </g>
      <g class="cp-node cp-node--world">
        <rect x="610" y="420" width="190" height="70" rx="7" />
        <text x="705" y="448">材质 rho, f_r</text>
        <text class="cp-sub" x="705" y="471">albedo · roughness</text>
      </g>
      <g class="cp-node cp-node--learning">
        <rect x="830" y="420" width="210" height="70" rx="7" />
        <text x="935" y="448">可微重渲染</text>
        <text class="cp-sub" x="935" y="471">analysis by synthesis</text>
      </g>
      <path class="cp-edge cp-edge--learning" d="M 800 455 L 830 455" marker-end="url(#cp-arrow-photo)" />
    </svg>
  </div>
  <figcaption><b>图 5:</b> 逆渲染的难点不是把 RGB 分成几个输出头，而是让这些输出在同一个渲染方程里重新生成所有观测。多视角改变几何约束，多光照改变光度约束，材质和可见性先验负责处理剩余歧义。</figcaption>
</figure>

### Lambertian 光度立体为什么能解

在最简单的 Lambertian、方向光、正交相机假设下，第 $k$ 个光照对像素 $p$ 的观测是:

$$
I_k(p)
=
\rho(p)
s_k^{\top}n(p).
$$

令:

$$
g(p)
=
\rho(p)n(p),
$$

并把 $K$ 个光照堆起来:

$$
\mathbf{i}(p)
=
Sg(p).
$$

当 $S$ 已知且至少包含三个非共面的光照方向时，最小二乘解为:

$$
\hat g(p)
=
\left(S^{\top}S\right)^{-1}
S^{\top}\mathbf{i}(p),
$$

$$
\hat\rho(p)=\|\hat g(p)\|_2,
\qquad
\hat n(p)=\frac{\hat g(p)}{\|\hat g(p)\|_2}.
$$

改变光照使同一个 $\rho,n$ 在多个方程中出现，从而把单张图里的乘法耦合变成可解线性系统。这正是“多次测量缩小零空间”的光度版本。

### 未标定光度为什么仍然有 gauge freedom

若光照 $S$ 也未知，观测矩阵只有分解:

$$
I
=
SG.
$$

对任意可逆矩阵 $A$:

$$
I
=
(SA)
(A^{-1}G).
$$

所以只靠重建误差，光照与法线分解并不唯一。积分性、单位法线、已知材质、光照分布和多视角几何只能逐步缩小 gauge freedom，不能靠增加网络容量自动消除。

更简单的反照率-光照尺度歧义是:

$$
\rho E
=
(c\rho)
\left(\frac{E}{c}\right).
$$

如果论文只展示 relighting 结果好看，却没有说明如何固定尺度、颜色和材质 gauge，那么内部变量未必具有声称的物理含义。

### 可微渲染把网络输出变成可检验假设

令网络或神经场输出:

$$
\hat X_{\theta}
=
(\hat G,\hat\rho,\hat f_r,\hat E).
$$

通过可微渲染器生成第 $k$ 个观测:

$$
\hat I_k
=
\mathcal{R}
\left(
\hat G,\hat\rho,\hat f_r,\hat E;
a_k
\right).
$$

训练目标写成:

$$
\min_{\theta}
\sum_k
\mathcal{L}_{image}
(\hat I_k,I_k)
+
\lambda_G\Phi_G(\hat G)
+
\lambda_R\Phi_R(\hat f_r)
+
\lambda_E\Phi_E(\hat E).
$$

第一项只要求解释观测；后面的 priors 才决定在多个等价解释中选哪一个。网络 architecture 也是 prior，例如:

- smooth normal field 偏好连续表面；
- low-rank tensor 偏好可压缩、跨光照共享的场；
- BRDF latent code 偏好训练材质库中的反射；
- set aggregation 假设输入光照顺序不应改变法线。

### 用可辨识性读 photometric learning

PS-FCN 接受任意数量、任意顺序的光照图像 [23]。它对每个输入提取特征，再用对排列不敏感的 pooling 聚合:

$$
z(p)
=
\operatorname{Pool}_{k}
\phi_{\theta}(I_k(p),s_k).
$$

这是一个很有意义的结构先验: 光照集合是 set，不是 sequence。换输入顺序不应改变法线。

UniPS 不再显式假设某一种物理光照模型，而是从全图提取 global lighting context [24]:

$$
c_k
=
E_{\theta}(I_k),
\qquad
\hat n(p)
=
D_{\theta}
\left(
\{\phi(I_k(p),c_k)\}_{k=1}^{K}
\right).
$$

它扩大了可处理光照的范围，但也把一部分可辨识性从解析模型转移到了训练分布。global context 是否真的对应物理光照，需要看跨材质、跨场景和跨相机泛化，而不能只看法线误差。

NeRFactor 在 NeRF 几何基础上显式分解法线、可见性、反照率、BRDF 与环境光 [25]:

$$
L_o
=
\mathcal{R}
\left(
n_{\theta},V_{\theta},\rho_{\theta},f_{r,\theta},E
\right).
$$

它通过多视角重渲染、平滑先验与 learned BRDF prior 缩小解空间。其贡献不只是多输出几个 neural fields，而是把阴影从 albedo 中分离所需的 visibility 显式写进 factorization。

TensoIR 用低秩 tensor factorization 表示几何、材质和光照共享特征 [26]:

$$
\mathcal{F}(x,y,z)
\approx
\sum_{r=1}^{R}
v_r^{x}(x)
v_r^{y}(y)
v_r^{z}(z).
$$

低秩结构同时带来效率和正则化。它假设场景属性可以由较少的分离因子表达，从而比纯 MLP 更容易共享跨视角、跨光照信息。

最后要区分 NeRF 与 inverse rendering。标准 NeRF 只需找到一个能生成新视角的 $(\sigma,c)$；NeRFactor、TensoIR 还要求 $c$ 被解释成光照、材质、法线和可见性的组合。后者的目标更强，也更容易受到 gauge ambiguity 影响。

## 深度学习设计其实是五个数学选择

四条分支到这里重新汇合。几何网络、光学联合设计、光场重建和逆渲染处理的 latent variable 不同, 但一篇论文都可以拆成五个互相独立的选择。这个表不是另一套分类法, 而是前面统一模型的阅读接口:

| 选择 | 数学问题 | 常见设计 | 不能混淆的地方 |
| --- | --- | --- | --- |
| 测量 | $p(R\mid X,a)$ 怎样产生? | 视角、曝光、焦点、编码孔径、子孔径 | 多一帧不一定多信息 |
| 状态 | 要估计哪个 latent variable? | depth、pose、PSF、light field、BRDF | 输出图像好不代表内部变量正确 |
| 分解 | 条件分布怎样 factorize? | disparity+warp、geometry+residual、shape+material+light | 多阶段不是天然更物理 |
| 算子 | 用什么函数族表示先验? | CNN、cost volume、attention、neural field、low-rank tensor | backbone 不是物理成像阶段 |
| 语义 | 输出点估计还是后验? | regression、uncertainty、sampling | 不适定问题不能假装成唯一真值 |

### CNN、attention 和 neural field 分别编码什么

CNN 偏好局部、平移等变结构:

$$
F(T_{\Delta}I)
\approx
T_{\Delta}F(I).
$$

这与局部 PSF、纹理和空间平稳噪声相容，但对大视差、长程遮挡和全局光照需要多尺度或更大感受野。

Attention 计算内容相关的核:

$$
z_i
=
\sum_j
\operatorname{softmax}_j
\left(
\frac{q_i^{\top}k_j}{\sqrt d}
\right)
v_j.
$$

在几何里，它近似非局部对应；在多曝光里，它选择哪个曝光保留局部信息；在多光照里，它聚合全局 lighting context。相同算子因为随机变量不同，数学角色也不同。

Neural field 把连续坐标映射为场值:

$$
F_{\theta}:\xi\mapsto y(\xi).
$$

$\xi$ 可以是三维位置、射线、时间或光照方向。它提供连续表示与可微查询，但“坐标连续”不等于“物理可辨识”。真正的物理约束仍来自渲染方程、跨视角共享和先验。

### 点估计为什么会隐藏多解性

若使用 L2 训练深度、HDR 或光场:

$$
\min_F
\mathbb{E}
\left[
\|F(R)-T\|_2^2
\right],
$$

最优解是:

$$
F^{\ast}(r)
=
\mathbb{E}[T\mid R=r].
$$

当后验多峰时，条件均值可能对应一个并不存在的平均几何、平均遮挡或平均纹理。确定性回归可以在 benchmark 上得到较低误差，却不能表达“这个区域根本没有被测到”。

更完整的模型应该至少估计不确定性:

$$
q_{\theta}(T\mid R)
=
\mathcal{N}
\left(
\mu_{\theta}(R),
\Sigma_{\theta}(R)
\right),
$$

或学习条件分布的样本。对几何和逆渲染来说，不确定性不是锦上添花，而是区分测量证据与数据先验的必要输出。

## 从固定重建到闭环相机

### 第一步: 维护后验并选择下一次测量

到目前为止，我们一直在讨论一个固定测量之后的反问题: 相机已经拍完了，模型怎样从 $R_a$ 估计 $T$。前面的 one-shot 测量设计是在拍摄前选择一个全局最优动作; 闭环相机则在看到当前观测后, 根据剩余不确定性继续选择焦点、曝光、孔径、视角或光照。于是“下一张怎么拍”本身成为推断的一部分。

设前 $k$ 次拍摄形成历史:

$$
\mathcal{H}_k
=
\left\{
(a_1,R_1),
\ldots,
(a_k,R_k)
\right\}.
$$

相机此时不必急着输出唯一答案，而可以维护一个关于世界的 belief:

$$
b_k(X)
=
p(X\mid\mathcal{H}_k).
$$

一次新测量会把 belief 更新为:

$$
b_{k+1}(X)
\propto
p(R_{k+1}\mid X,a_{k+1})
b_k(X).
$$

这时，相机要解决的问题不再只是“当前最可能的深度是多少”，而是:

> 当前有哪些场景解释仍然无法区分，下一次测量怎样最有效地把它们分开?

令当前 belief 下的最小任务风险为:

$$
\mathcal{B}(b_k)
=
\min_d
\mathbb{E}_{X\sim b_k}
\left[
\ell(d,\tau(X))
\right].
$$

若选择动作 $a$，还没有看到结果时，它的期望价值可以定义为风险下降:

$$
\mathcal{V}(a\mid b_k)
=
\mathcal{B}(b_k)
-
\mathbb{E}_{r\sim p(r\mid b_k,a)}
\left[
\mathcal{B}(b_{k+1}^{a,r})
\right]
-
\lambda C(a).
$$

于是下一次拍摄动作是:

$$
a_{k+1}^{\ast}
=
\arg\max_a
\mathcal{V}(a\mid b_k).
$$

这个公式把前面的内容真正连成了一个闭环。若深度后验沿射线很宽，相机可以移动基线或改变焦点；若暗区被 read noise 淹没而亮区已经饱和，可以选择另一档曝光；若反照率与光照仍然纠缠，可以改变光源方向；若高光让法线解释不稳定，可以换观察方向。几何、光学、光场与光度模型在这里不再是四类离线知识，而是四种可以主动消除不确定性的动作空间。

### 已有方法只是闭环的不同切片

用这个视角回看前面的论文，会发现它们已经触碰到闭环相机的不同部分，但通常只优化其中一段。

| 方法 | 相机能改变什么 | 新增的证据 | 学习发生在哪里 | 仍然没有闭合的部分 |
| --- | --- | --- | --- | --- |
| DROID-SLAM / DUSt3R [5,7] | 输入视角通常已给定 | 多视角对应与几何一致性 | 后验更新、匹配和全局对齐 | 不主动决定下一视角 |
| Deep Optics [8] | 部署前固定镜头编码 | 深度相关 PSF | 光学 encoder 与神经 decoder 联合训练 | 拍摄时不根据当前场景适应 |
| Neural Auto-Exposure [10] | 在线改变曝光 | 不同亮度区间的有效光子 | 任务驱动的曝光策略 | 动作主要仍是一维曝光 |
| Neural Exposure Fusion [11] | 采集有限组曝光 | 饱和区与低信噪区的互补观测 | 跨曝光特征选择 | 曝光组通常预先给定 |
| DFV / EPINET [18,19] | 焦点或子孔径采样已给定 | 清晰度变化与 EPI 斜率 | 深度后验估计 | 不决定还需要哪个焦平面 |
| NeRFactor / TensoIR [25,26] | 视角和光照集合已给定 | 重渲染与跨观测共享 | 几何、材质、光照分解 | 不主动选择最能打破 gauge 的光照 |

这张表指向一个比“更强 backbone”更有意思的研究方向: 把 estimator 和 acquisition policy 放进同一个系统。模型不仅给出答案，还要指出当前答案依赖了多少先验、哪种额外测量最可能推翻它，以及这次测量是否值得它的时间与硬件成本。

### 第二步: 输出不确定性, 而不只输出一个答案

当前许多系统最终只输出一张 depth map、一张 HDR 图或一组材质参数。这个接口过早地把后验压成了一个点。更可信的计算相机至少应该区分三种不同的不确定性。

第一种来自光子和电路噪声。它由 likelihood 决定，增加曝光或重复采样通常能够降低。

第二种来自测量零空间。即使完全没有噪声，单目尺度、遮挡区域、饱和辐照度或未知光照下的材质分解仍可能有多个等价解释。它只能通过改变测量或引入先验处理。

第三种来自模型失配。训练数据没有覆盖的新镜头、透明材质、复杂多次反射或异常运动，可能让网络在错误答案上仍然非常自信。

把这些情况都压进一个 per-pixel variance 并不够。更有意义的输出应该接近:

$$
\mathcal{O}_k
=
\left(
\hat T_k,
q_{\theta}(T\mid\mathcal{H}_k),
a_{k+1}^{\ast}
\right).
$$

它同时包含当前决策、尚未消除的后验，以及建议进行的下一次测量。此时相机输出的核心对象不再只是 JPEG，而是一个可以继续更新的 belief state。

### 第三步: 让新观测检验模型

主动拍摄的价值不只在提高重建质量。它还可以检验模型是否真的理解了当前场景。

根据当前后验，模型可以预测动作 $a$ 下可能看到的图像分布:

$$
p_{\theta}(R_{new}\mid\mathcal{H}_k,a)
=
\int
p_{\psi}(R_{new}\mid X,a)
q_{\theta}(X\mid\mathcal{H}_k)
dX.
$$

当真实新观测到来后，可以计算 posterior predictive surprise:

$$
S_{new}
=
-\log
p_{\theta}
\left(
R_{new}=r_{new}
\mid
\mathcal{H}_k,a
\right).
$$

若 $S_{new}$ 很大，说明问题不只是原有图像噪声高，而是模型的场景表示、物理 forward model 或训练先验无法解释新证据。传统 benchmark 常用同分布测试集衡量平均误差；闭环相机则能通过一次专门选择的反事实拍摄，主动暴露自己的错误。

例如，一个模型可能把白色物体处在阴影中解释成灰色材质。只看原图，两种解释都成立；改变光照后，它们预测的像素不同。一次新测量既缩小后验，也在检验网络内部的 albedo-light factorization 是否真实。

### 把闭环写进实验设计

如果沿这条思路继续推进，一项好的计算摄像研究可以从一对“当前相机无法区分的世界”开始，而不是从一个网络模块开始。

设 $X_1$ 与 $X_2$ 对任务给出不同答案:

$$
\tau(X_1)
\ne
\tau(X_2),
$$

但默认相机 $a_0$ 几乎无法区分它们:

$$
p(R\mid X_1,a_0)
\approx
p(R\mid X_2,a_0).
$$

研究问题就可以被精确地改写为: 是否存在一个成本可接受的动作 $a$，让两个观测分布分开? 一种直接的设计目标是:

$$
a^{\ast}
=
\arg\max_a
\operatorname{JS}
\left(
p(R\mid X_1,a)
\,\|\,
p(R\mid X_2,a)
\right)
-
\lambda C(a),
$$

其中 $\operatorname{JS}$ 是 Jensen-Shannon divergence。

这给计算摄像一个很具体的研究程序。先构造会被现有相机混淆、但对任务意义不同的场景对；再设计能够分离它们的孔径、曝光、焦点、视角、光照或传感器编码；最后才训练一个足够高效的 posterior estimator。网络架构仍然重要，但它不再负责凭空弥补一个从未被定义清楚的观测缺陷。

深度估计中的模糊边界、HDR 中的亮部饱和、光场中的遮挡射线、逆渲染中的光照-材质歧义，都可以用同一种方式变成“假设区分实验”。评价也应随之改变: 不只比较固定输入上的平均误差，还要比较一次额外测量能减少多少任务风险、后验是否校准、预测能否被新观测验证，以及硬件为这些信息付出了多少成本。

## 结尾: 从拍照到提问

传统相机的工作流程在按下快门时基本结束: 光已经被积分，方向和时间已经被压缩，剩下的是把像素处理成图像。计算摄像最初做的是逆向补救，试图从这些像素中恢复更多信息。深度学习又把可学习先验带进这个过程，使许多原本困难的反问题得到更好的近似解。

但再往前一步，相机不必永远接受第一次测量留下的歧义。它可以识别当前有哪些世界仍然与观测相容，判断哪种不确定性来自噪声、哪种来自零空间、哪种可能是模型自己的偏见，然后选择一次最有价值的新观测。

于是，投影几何告诉它移动视角会区分什么；镜头与曝光告诉它怎样重新分配光子预算；焦点堆栈和光场告诉它如何找回被积分的方向；光度模型告诉它改变光照后哪些材质与形状解释会分离。深度学习的角色也随之改变: 它不再只是把一次压缩测量翻译成答案，而是帮助相机在不确定性中组织证据、设计实验并修正自己。

真正值得追求的下一代计算相机，或许不是一次就猜得最准的相机，而是最清楚自己还不知道什么、也最知道下一眼该看哪里的相机。

> 它的核心输出不只是一张图，而是一份关于世界的信念，以及为了改变这份信念而应进行的下一次测量。

## 参考文献

[1] 北京大学计算摄像学研究团队. 《计算摄像学: 成像模型理论与深度学习实践》. <https://camera.pku.edu.cn/book>

[2] Adelson, E. H., & Bergen, J. R. The Plenoptic Function and the Elements of Early Vision. 1991.

[3] Hartley, R., & Zisserman, A. Multiple View Geometry in Computer Vision. Cambridge University Press, 2004.

[4] Zhou, T., Brown, M., Snavely, N., & Lowe, D. G. Unsupervised Learning of Depth and Ego-Motion from Video. CVPR 2017. <https://openaccess.thecvf.com/content_cvpr_2017/html/Zhou_Unsupervised_Learning_of_CVPR_2017_paper.html>

[5] Teed, Z., & Deng, J. DROID-SLAM: Deep Visual SLAM for Monocular, Stereo, and RGB-D Cameras. NeurIPS 2021. <https://proceedings.neurips.cc/paper_files/paper/2021/hash/89fcd07f20b6785b92134bd6c1d0fa42-Abstract.html>

[6] Lin, C.-H., Ma, W.-C., Torralba, A., & Lucey, S. BARF: Bundle-Adjusting Neural Radiance Fields. ICCV 2021. <https://openaccess.thecvf.com/content/ICCV2021/html/Lin_BARF_Bundle-Adjusting_Neural_Radiance_Fields_ICCV_2021_paper.html>

[7] Wang, S., Leroy, V., Cabon, Y., Chidlovskii, B., & Revaud, J. DUSt3R: Geometric 3D Vision Made Easy. CVPR 2024. <https://openaccess.thecvf.com/content/CVPR2024/html/Wang_DUSt3R_Geometric_3D_Vision_Made_Easy_CVPR_2024_paper.html>

[8] Chang, J., & Wetzstein, G. Deep Optics for Monocular Depth Estimation and 3D Object Detection. ICCV 2019. <https://openaccess.thecvf.com/content_ICCV_2019/html/Chang_Deep_Optics_for_Monocular_Depth_Estimation_and_3D_Object_Detection_ICCV_2019_paper.html>

[9] Chen, C., Chen, Q., Xu, J., & Koltun, V. Learning to See in the Dark. CVPR 2018. <https://openaccess.thecvf.com/content_cvpr_2018/html/Chen_Learning_to_See_CVPR_2018_paper.html>

[10] Onzon, E., Mannan, F., & Heide, F. Neural Auto-Exposure for High-Dynamic Range Object Detection. CVPR 2021. <https://light.princeton.edu/publication/neural_auto_exposure/>

[11] Onzon, E., Boemer, M., Mannan, F., & Heide, F. Neural Exposure Fusion for High-Dynamic Range Object Detection. CVPR 2024. <https://openaccess.thecvf.com/content/CVPR2024/html/Onzon_Neural_Exposure_Fusion_for_High-Dynamic_Range_Object_Detection_CVPR_2024_paper.html>

[12] Abuolaim, A., Delbracio, M., Kelly, D., Brown, M. S., & Milanfar, P. Learning to Reduce Defocus Blur by Realistically Modeling Dual-Pixel Data. ICCV 2021. <https://openaccess.thecvf.com/content/ICCV2021/html/Abuolaim_Learning_To_Reduce_Defocus_Blur_by_Realistically_Modeling_Dual-Pixel_Data_ICCV_2021_paper.html>

[13] Chen, H., Xie, Y., Peng, X., et al. Quad-Pixel Image Defocus Deblurring: A New Benchmark and Model. CVPR 2025. <https://openaccess.thecvf.com/content/CVPR2025/html/Chen_Quad-Pixel_Image_Defocus_Deblurring_A_New_Benchmark_and_Model_CVPR_2025_paper.html>

[14] Levoy, M., & Hanrahan, P. Light Field Rendering. SIGGRAPH 1996. <https://graphics.stanford.edu/papers/light/>

[15] Ng, R. Digital Light Field Photography. PhD thesis, Stanford University, 2006. <https://graphics.stanford.edu/papers/lfcamera/>

[16] Kalantari, N. K., Wang, T.-C., & Ramamoorthi, R. Learning-Based View Synthesis for Light Field Cameras. SIGGRAPH Asia 2016. <https://cseweb.ucsd.edu/~viscomp/projects/LF/papers/SIGASIA16/>

[17] Srinivasan, P. P., Wang, T., Sreelal, A., Ramamoorthi, R., & Ng, R. Learning to Synthesize a 4D RGBD Light Field from a Single Image. ICCV 2017. <https://openaccess.thecvf.com/content_iccv_2017/html/Srinivasan_Learning_to_Synthesize_ICCV_2017_paper.html>

[18] Shin, C., Jeon, H.-G., Yoon, Y., Kweon, I. S., & Kim, S. J. EPINET: A Fully-Convolutional Neural Network Using Epipolar Geometry for Depth from Light Field Images. CVPR 2018. <https://openaccess.thecvf.com/content_cvpr_2018/html/Shin_EPINET_A_Fully-Convolutional_CVPR_2018_paper.html>

[19] Yang, F., Huang, X., & Zhou, Z. Deep Depth from Focus with Differential Focus Volume. CVPR 2022. <https://openaccess.thecvf.com/content/CVPR2022/html/Yang_Deep_Depth_From_Focus_With_Differential_Focus_Volume_CVPR_2022_paper.html>

[20] Mildenhall, B., Srinivasan, P. P., Ortiz-Cayon, R., et al. Local Light Field Fusion: Practical View Synthesis with Prescriptive Sampling Guidelines. SIGGRAPH 2019. <https://bmild.github.io/llff/index.html>

[21] Sitzmann, V., Rezchikov, S., Freeman, W. T., Tenenbaum, J. B., & Durand, F. Light Field Networks: Neural Scene Representations with Single-Evaluation Rendering. NeurIPS 2021. <https://papers.nips.cc/paper/2021/hash/a11ce019e96a4c60832eadd755a17a58-Abstract.html>

[22] Mildenhall, B., Srinivasan, P. P., Tancik, M., Barron, J. T., Ramamoorthi, R., & Ng, R. NeRF: Representing Scenes as Neural Radiance Fields for View Synthesis. ECCV 2020. <https://arxiv.org/abs/2003.08934>

[23] Chen, G., Han, K., & Wong, K.-Y. K. PS-FCN: A Flexible Learning Framework for Photometric Stereo. ECCV 2018. <https://openaccess.thecvf.com/content_ECCV_2018/html/Guanying_Chen_PS-FCN_A_Flexible_ECCV_2018_paper.html>

[24] Ikehata, S. Universal Photometric Stereo Network Using Global Lighting Contexts. CVPR 2022. <https://openaccess.thecvf.com/content/CVPR2022/html/Ikehata_Universal_Photometric_Stereo_Network_Using_Global_Lighting_Contexts_CVPR_2022_paper.html>

[25] Zhang, X., Srinivasan, P. P., Deng, B., Debevec, P., Freeman, W. T., & Barron, J. T. NeRFactor: Neural Factorization of Shape and Reflectance under an Unknown Illumination. SIGGRAPH Asia 2021. <https://xiuming.info/projects/nerfactor/>

[26] Jin, H., Liu, I., Xu, P., et al. TensoIR: Tensorial Inverse Rendering. CVPR 2023. <https://openaccess.thecvf.com/content/CVPR2023/html/Jin_TensoIR_Tensorial_Inverse_Rendering_CVPR_2023_paper.html>
