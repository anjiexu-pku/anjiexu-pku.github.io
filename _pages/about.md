---
permalink: /
title: "Anjie Xu / 许安杰"
author_profile: true
redirect_from: 
  - /about/
  - /about.html
---

About Me
========

I am a Ph.D. student supervised by Prof. [Leye Wang](https://wangleye.github.io/) at the School of Computer Science, Peking University.
Prior to this, I completed my bachelor's degree through the Kang Jichang Honors Program in Computer Science at Northwestern Polytechnical University.

My research interests include **Academic Data Management**, **Data Privacy Protection**, and related fields. I am passionate about exploring innovative solutions to challenges in Computer Science, Mathematics, and Physics.
Recently, I have also been working on **AI Agents** and **Agent Skill Evaluation**, especially on practical benchmarking systems for utility and security.

Education
=========

- 2024 - present: Ph.D. student in Computer Science, **Peking University**
- 2020 - 2024: B.S. in Computer Science (Kang Jichang Honors Program), **Northwestern Polytechnical University**

Publications
============

* *SkillFab: An Agent-Native Skill Production Platform* <br/>
<img src="/images/publications/skillfab-abstract-preview.png" alt="SkillFab technical report first page abstract preview" style="display: block; max-width: 100%; border: 1px solid #e5e7eb; border-radius: 6px; margin: 0.75rem 0 1rem;">
**Anjie Xu**, Yifeng Cai, Yi Li, Zixing Wang, Zhiyu Zhang, Jingfan Chen, Ruohan Xu, Leye Wang <br/>
**Technical Report**, 2026 <br/>
[Report](https://github.com/cybtopia/skillfab-report/blob/main/skillfab-system-design.pdf) | [Project](https://skillfab.ai) | [Report Repo](https://github.com/cybtopia/skillfab-report)

SkillFab is an agent-native platform for producing, reviewing, publishing, and reusing Agent Skills. It turns missing capabilities into demand-first issues, lets contributors implement skill packages through repository-backed submissions, captures Git evidence for review, and publishes accepted packages to a reusable skill registry. The platform codebase is planned for open-source release in a future repository.

* *SkillTester: Benchmarking Utility and Security of Agent Skills* <br/>
Leye Wang, Zixing Wang, **Anjie Xu**  
**arXiv:2603.28815**, 2026  
[Paper](https://arxiv.org/abs/2603.28815) | [Code](https://github.com/skilltester-ai/skilltester) | [skilltester.ai](https://skilltester.ai)

SkillTester is an agent-driven benchmark system for evaluating agent skills from both utility and security perspectives. It compares paired baseline and with-skill executions, preserves raw task-level evidence, and generates structured reports that help users judge whether a skill is useful and safe before adoption.

![SkillTester Dashboard](https://github.com/skilltester-ai/skilltester/raw/main/pics/skilltester.png)

* *ChatPD: An LLM-driven Paper-Dataset Networking System* <br/>
**Anjie Xu**, Ruiqing Ding, Leye Wang  
**CCF-A**, KDD 2025 Applied Data Science Track  
[Paper](https://arxiv.org/abs/2505.22349) | [Code](https://github.com/ChatPD-web/ChatPD) | [Deployed Website](https://chatpd-web.github.io/chatpd-web/) | [Video](https://www.bilibili.com/video/BV1jjt8zwE5f/)

![ChatPD System Architecture](https://github.com/ChatPD-web/ChatPD/raw/main/pic/system_arch.png)

<!-- <div style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; max-width: 100%; margin-top: 10px; margin-bottom: 20px;">
  <iframe src="//player.bilibili.com/player.html?isOutside=true&aid=114997917195022&bvid=BV1jjt8zwE5f&cid=31585208959&p=1" 
          scrolling="no" 
          frameborder="0" 
          allowfullscreen 
          allow="fullscreen; picture-in-picture"
          style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;">
  </iframe>
</div> -->

Projects
========

* **CLRS-Lean** <br/>
<img src="/images/projects/clrs-lean-logo.png" alt="CLRS-Lean project mark" style="display: block; max-width: 220px; width: 45%; min-width: 160px; border: 1px solid #e5e7eb; border-radius: 8px; margin: 0.5rem 0 0.75rem;">
[Project](https://tanktechnology.github.io/CLRS-Lean/) | [Code](https://github.com/TankTechnology/CLRS-Lean)

I am currently updating CLRS-Lean, a Lean 4 companion for CLRS-style algorithm correctness proofs. The project explores how classic algorithm reasoning can be represented as machine-checkable formal proofs.


Blog
======

{% for post in site.posts %}
- **{{ post.date | date: "%Y-%m-%d" }}** — [{{ post.title }}]({{ post.url }})
{% endfor %}

Awards
======

- 2024, **Outstanding Graduate Student**, Northwestern Polytechnical University (西北工业大学优秀毕业生)
- 2023, **National Special Prize (University Group)**, CCF Sinan Cup Quantum Computing Competition (CCF量子计算司南杯全国高校组特等奖)

Experience
===========

- Teaching Assistant of *AI Agent Programming Practice* by Dr. [Bojie Li](https://01.me/) (Co-Founder & Chief Scientist of Pine AI), Zhongguancun Academy ([Course Homepage](https://01.me/2025/07/ai-agent-hackathon-2025summer/)), 2025 Summer 
- Teaching Assistant of *Data Structures and Algorithms (A)* by Prof. [Leye Wang](https://wangleye.github.io/), Peking University, 2024 Fall
- Quantitative Trading Intern, MetaLight Inc., Oct 2023 – Jun 2024  
  Built and optimized quantitative trading algorithms for power trading systems

Skills
======

- **Programming Languages**: Rust, Python, C++
- I also have some experience with **Operating Systems**.


Hobbies
=======

Outside of my academic work, I enjoy reading, writing short articles to share my thoughts, and watching anime such as *K-On!* (轻音少女) and *Pretty Derby* (赛马娘).
