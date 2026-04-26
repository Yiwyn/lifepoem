---
title: "关于"
layout: "about"
summary: about
---

<style>
/* ===== 全局重置与主题变量 ===== */
.about-root {
  --bg-primary: #0a0e17;
  --bg-card: rgba(16, 24, 40, 0.7);
  --bg-card-hover: rgba(22, 33, 55, 0.85);
  --border-glow: rgba(56, 189, 248, 0.25);
  --accent-cyan: #38bdf8;
  --accent-purple: #a78bfa;
  --accent-green: #34d399;
  --accent-orange: #fb923c;
  --accent-pink: #f472b6;
  --text-primary: #e2e8f0;
  --text-secondary: #94a3b8;
  --text-dim: #64748b;
  --gradient-main: linear-gradient(135deg, #38bdf8 0%, #a78bfa 50%, #f472b6 100%);
  --gradient-card: linear-gradient(145deg, rgba(56,189,248,0.08) 0%, rgba(167,139,250,0.05) 100%);
  font-family: 'Inter', 'SF Pro Display', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  color: var(--text-primary);
  max-width: 900px;
  margin: 0 auto;
  padding: 20px;
}

/* ===== 粒子背景 ===== */
.about-root::before {
  content: '';
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background:
    radial-gradient(ellipse at 20% 20%, rgba(56,189,248,0.06) 0%, transparent 50%),
    radial-gradient(ellipse at 80% 80%, rgba(167,139,250,0.06) 0%, transparent 50%),
    radial-gradient(ellipse at 50% 50%, rgba(244,114,182,0.03) 0%, transparent 70%);
  pointer-events: none;
  z-index: -1;
}

/* ===== Hero 区域 ===== */
.about-hero {
  text-align: center;
  padding: 50px 20px 40px;
  position: relative;
}

.about-hero .avatar-ring {
  width: 120px;
  height: 120px;
  border-radius: 50%;
  margin: 0 auto 24px;
  padding: 3px;
  background: var(--gradient-main);
  animation: ring-rotate 6s linear infinite;
  position: relative;
}

@keyframes ring-rotate {
  0% { box-shadow: 0 0 20px rgba(56,189,248,0.3), 0 0 60px rgba(167,139,250,0.1); }
  50% { box-shadow: 0 0 30px rgba(167,139,250,0.4), 0 0 80px rgba(56,189,248,0.15); }
  100% { box-shadow: 0 0 20px rgba(56,189,248,0.3), 0 0 60px rgba(167,139,250,0.1); }
}

.about-hero .avatar-inner {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  background: var(--bg-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 48px;
}

.about-hero h1 {
  font-size: 2.2em;
  font-weight: 700;
  background: var(--gradient-main);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  margin: 0 0 8px;
  letter-spacing: -0.5px;
}

.about-hero .tagline {
  font-size: 1.1em;
  color: var(--text-secondary);
  margin-bottom: 16px;
}

.about-hero .motto {
  font-size: 0.95em;
  color: var(--text-dim);
  font-style: italic;
  padding: 12px 24px;
  border-left: 3px solid var(--accent-purple);
  background: rgba(167,139,250,0.05);
  border-radius: 0 8px 8px 0;
  display: inline-block;
  max-width: 500px;
}

/* ===== 状态指示条 ===== */
.about-status-bar {
  display: flex;
  justify-content: center;
  gap: 24px;
  margin: 24px 0 8px;
  flex-wrap: wrap;
}

.status-item {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.85em;
  color: var(--text-secondary);
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  animation: pulse-dot 2s ease-in-out infinite;
}

.status-dot.green { background: var(--accent-green); box-shadow: 0 0 8px var(--accent-green); }
.status-dot.cyan { background: var(--accent-cyan); box-shadow: 0 0 8px var(--accent-cyan); }
.status-dot.orange { background: var(--accent-orange); box-shadow: 0 0 8px var(--accent-orange); }

@keyframes pulse-dot {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.6; transform: scale(0.85); }
}

/* ===== 通用 Section ===== */
.about-section {
  margin: 36px 0;
  position: relative;
}

.about-section-title {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 1.25em;
  font-weight: 600;
  margin-bottom: 20px;
  color: var(--text-primary);
}

.about-section-title .icon {
  font-size: 1.1em;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
  background: var(--gradient-card);
  border: 1px solid var(--border-glow);
}

.about-section-title::after {
  content: '';
  flex: 1;
  height: 1px;
  background: linear-gradient(to right, var(--border-glow), transparent);
}

/* ===== 技术栈卡片 ===== */
.tech-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 16px;
}

.tech-card {
  background: var(--bg-card);
  border: 1px solid var(--border-glow);
  border-radius: 14px;
  padding: 20px;
  transition: all 0.3s ease;
  position: relative;
  overflow: hidden;
}

.tech-card::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 2px;
  background: var(--gradient-main);
  opacity: 0;
  transition: opacity 0.3s ease;
}

.tech-card:hover {
  background: var(--bg-card-hover);
  border-color: rgba(56, 189, 248, 0.4);
  transform: translateY(-2px);
  box-shadow: 0 8px 30px rgba(56,189,248,0.08);
}

.tech-card:hover::before {
  opacity: 1;
}

.tech-card .card-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}

.tech-card .card-icon {
  font-size: 1.5em;
}

.tech-card .card-label {
  font-size: 0.95em;
  font-weight: 600;
  color: var(--text-primary);
}

.tech-card .card-items {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.tech-tag {
  font-size: 0.78em;
  padding: 4px 10px;
  border-radius: 6px;
  background: rgba(56,189,248,0.08);
  border: 1px solid rgba(56,189,248,0.15);
  color: var(--accent-cyan);
  transition: all 0.2s ease;
}

.tech-tag.purple {
  background: rgba(167,139,250,0.08);
  border-color: rgba(167,139,250,0.15);
  color: var(--accent-purple);
}

.tech-tag.green {
  background: rgba(52,211,153,0.08);
  border-color: rgba(52,211,153,0.15);
  color: var(--accent-green);
}

.tech-tag.orange {
  background: rgba(251,146,60,0.08);
  border-color: rgba(251,146,60,0.15);
  color: var(--accent-orange);
}

.tech-tag.pink {
  background: rgba(244,114,182,0.08);
  border-color: rgba(244,114,182,0.15);
  color: var(--accent-pink);
}

.tech-tag:hover {
  transform: translateY(-1px);
  box-shadow: 0 2px 8px rgba(56,189,248,0.15);
}

/* ===== 核心优势 ===== */
.strength-list {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.strength-item {
  display: flex;
  gap: 14px;
  padding: 16px 18px;
  background: var(--bg-card);
  border: 1px solid var(--border-glow);
  border-radius: 12px;
  transition: all 0.3s ease;
  align-items: flex-start;
}

.strength-item:hover {
  background: var(--bg-card-hover);
  border-color: rgba(56,189,248,0.35);
  transform: translateX(4px);
}

.strength-num {
  font-size: 1.6em;
  font-weight: 800;
  background: var(--gradient-main);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  line-height: 1;
  min-width: 32px;
}

.strength-content h4 {
  margin: 0 0 4px;
  font-size: 0.95em;
  font-weight: 600;
  color: var(--text-primary);
}

.strength-content p {
  margin: 0;
  font-size: 0.85em;
  color: var(--text-secondary);
  line-height: 1.6;
}

/* ===== 代表文章 ===== */
.article-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.article-item {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 18px;
  background: var(--bg-card);
  border: 1px solid var(--border-glow);
  border-radius: 12px;
  transition: all 0.3s ease;
  text-decoration: none;
  color: inherit;
}

.article-item:hover {
  background: var(--bg-card-hover);
  border-color: rgba(167,139,250,0.4);
  transform: translateX(4px);
}

.article-badge {
  font-size: 0.7em;
  padding: 3px 8px;
  border-radius: 5px;
  font-weight: 600;
  white-space: nowrap;
  flex-shrink: 0;
}

.article-badge.design { background: rgba(56,189,248,0.12); color: var(--accent-cyan); border: 1px solid rgba(56,189,248,0.2); }
.article-badge.java { background: rgba(251,146,60,0.12); color: var(--accent-orange); border: 1px solid rgba(251,146,60,0.2); }
.article-badge.spring { background: rgba(52,211,153,0.12); color: var(--accent-green); border: 1px solid rgba(52,211,153,0.2); }
.article-badge.ai { background: rgba(244,114,182,0.12); color: var(--accent-pink); border: 1px solid rgba(244,114,182,0.2); }
.article-badge.arch { background: rgba(167,139,250,0.12); color: var(--accent-purple); border: 1px solid rgba(167,139,250,0.2); }

.article-info {
  flex: 1;
  min-width: 0;
}

.article-info .title {
  font-size: 0.9em;
  font-weight: 500;
  color: var(--text-primary);
  margin-bottom: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.article-info .desc {
  font-size: 0.78em;
  color: var(--text-dim);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.article-arrow {
  color: var(--text-dim);
  font-size: 1.1em;
  transition: all 0.2s ease;
  flex-shrink: 0;
}

.article-item:hover .article-arrow {
  color: var(--accent-cyan);
  transform: translateX(4px);
}

/* ===== 成就 & 计划 ===== */
.achievement-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 14px;
}

.achieve-card {
  background: var(--bg-card);
  border: 1px solid var(--border-glow);
  border-radius: 14px;
  padding: 20px;
  text-align: center;
  transition: all 0.3s ease;
  position: relative;
  overflow: hidden;
}

.achieve-card::after {
  content: '';
  position: absolute;
  bottom: 0; left: 0; right: 0;
  height: 2px;
  background: var(--gradient-main);
  opacity: 0;
  transition: opacity 0.3s ease;
}

.achieve-card:hover {
  background: var(--bg-card-hover);
  transform: translateY(-2px);
  box-shadow: 0 8px 24px rgba(56,189,248,0.08);
}

.achieve-card:hover::after {
  opacity: 1;
}

.achieve-card .achieve-icon {
  font-size: 2em;
  margin-bottom: 10px;
}

.achieve-card .achieve-title {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 4px;
}

.achieve-card .achieve-desc {
  font-size: 0.78em;
  color: var(--text-secondary);
}

.achieve-card.done .achieve-icon { filter: none; }
.achieve-card.progress .achieve-icon { filter: saturate(0.6) brightness(0.8); }

/* ===== 时间线 ===== */
.timeline {
  position: relative;
  padding-left: 28px;
}

.timeline::before {
  content: '';
  position: absolute;
  left: 8px;
  top: 4px;
  bottom: 4px;
  width: 2px;
  background: linear-gradient(to bottom, var(--accent-cyan), var(--accent-purple), var(--accent-pink));
  border-radius: 2px;
}

.timeline-item {
  position: relative;
  padding: 12px 0;
}

.timeline-item::before {
  content: '';
  position: absolute;
  left: -24px;
  top: 18px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--bg-primary);
  border: 2px solid var(--accent-cyan);
  box-shadow: 0 0 8px rgba(56,189,248,0.3);
}

.timeline-item:nth-child(2)::before { border-color: var(--accent-purple); box-shadow: 0 0 8px rgba(167,139,250,0.3); }
.timeline-item:nth-child(3)::before { border-color: var(--accent-pink); box-shadow: 0 0 8px rgba(244,114,182,0.3); }

.timeline-item .time-label {
  font-size: 0.75em;
  color: var(--accent-cyan);
  font-weight: 600;
  margin-bottom: 2px;
}

.timeline-item:nth-child(2) .time-label { color: var(--accent-purple); }
.timeline-item:nth-child(3) .time-label { color: var(--accent-pink); }

.timeline-item .time-content {
  font-size: 0.88em;
  color: var(--text-primary);
  font-weight: 500;
}

.timeline-item .time-desc {
  font-size: 0.8em;
  color: var(--text-secondary);
  margin-top: 2px;
}

/* ===== Footer ===== */
.about-footer {
  text-align: center;
  padding: 30px 0 20px;
  border-top: 1px solid var(--border-glow);
  margin-top: 40px;
}

.about-footer p {
  font-size: 0.82em;
  color: var(--text-dim);
  margin: 4px 0;
}

.about-footer .footer-brand {
  font-weight: 600;
  background: var(--gradient-main);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

/* ===== 亮色主题适配 ===== */
@media (prefers-color-scheme: light) {
  .about-root {
    --bg-primary: #f8fafc;
    --bg-card: rgba(241, 245, 249, 0.9);
    --bg-card-hover: rgba(226, 232, 240, 0.95);
    --border-glow: rgba(56, 189, 248, 0.2);
    --text-primary: #0f172a;
    --text-secondary: #475569;
    --text-dim: #94a3b8;
    --gradient-card: linear-gradient(145deg, rgba(56,189,248,0.06) 0%, rgba(167,139,250,0.04) 100%);
  }
  .about-root::before {
    background:
      radial-gradient(ellipse at 20% 20%, rgba(56,189,248,0.04) 0%, transparent 50%),
      radial-gradient(ellipse at 80% 80%, rgba(167,139,250,0.04) 0%, transparent 50%),
      radial-gradient(ellipse at 50% 50%, rgba(244,114,182,0.02) 0%, transparent 70%);
  }
  .about-hero .avatar-inner {
    background: #f1f5f9;
  }
  .about-hero .motto {
    color: var(--text-secondary);
    background: rgba(167,139,250,0.04);
  }
  .strength-num {
    background: linear-gradient(135deg, #0284c7 0%, #7c3aed 50%, #db2777 100%);
    -webkit-background-clip: text;
    background-clip: text;
  }
  .tech-card {
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
  }
  .tech-card:hover {
    box-shadow: 0 4px 16px rgba(56,189,248,0.1);
  }
  .tech-tag {
    box-shadow: 0 1px 2px rgba(0,0,0,0.04);
  }
  .strength-item, .article-item, .achieve-card {
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
  }
  .strength-item:hover, .article-item:hover, .achieve-card:hover {
    box-shadow: 0 4px 16px rgba(56,189,248,0.1);
  }
  .timeline-item::before {
    background: #f8fafc;
  }
  .about-footer {
    border-top-color: rgba(56,189,248,0.15);
  }
}

/* ===== 响应式 ===== */
@media (max-width: 600px) {
  .about-root { padding: 12px; }
  .about-hero h1 { font-size: 1.7em; }
  .tech-grid { grid-template-columns: 1fr; }
  .achievement-grid { grid-template-columns: 1fr; }
  .about-status-bar { gap: 14px; }
}
</style>

<div class="about-root">

  <!-- ===== Hero ===== -->
  <div class="about-hero">
    <div class="avatar-ring">
      <div class="avatar-inner"><img src="https://blog.lifepoem.fun/favicon.png" alt="Yiwyn" style="width:72px;height:72px;border-radius:50%;object-fit:contain;"></div>
    </div>
    <h1>Yiwyn</h1>
    <p class="tagline">Java 后端工程师 · 系统架构设计师 · 技术探索者</p>
    <div class="motto">"生活不止眼前的苟且，还有诗和远方"</div>
    <div class="about-status-bar">
      <div class="status-item">
        <span class="status-dot green"></span>
        <span>持续学习中</span>
      </div>
      <div class="status-item">
        <span class="status-dot cyan"></span>
        <span>技术输出中</span>
      </div>
      <div class="status-item">
        <span class="status-dot orange"></span>
        <span>架构师认证 ✅</span>
      </div>
    </div>
  </div>

  <!-- ===== 关于我 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">💡</span>
      <span>关于我</span>
    </div>
    <div class="strength-list">
      <div class="strength-item">
        <div class="strength-content">
          <p>一名热爱技术的 Java 后端工程师，专注于<strong style="color:var(--accent-cyan)">系统架构设计</strong>与<strong style="color:var(--accent-purple)">领域驱动设计</strong>的落地实践。善于从复杂业务中抽象出优雅的技术方案，追求代码的简洁与系统的可扩展性。</p>
          <p style="margin-top:8px;">相信<strong style="color:var(--accent-green)">技术的价值在于解决实际问题</strong>，而非炫技。在这里记录学习与思考，分享工程实践中的设计思路与踩坑经验。</p>
        </div>
      </div>
    </div>
  </div>

  <!-- ===== 核心优势 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">⚡</span>
      <span>核心优势</span>
    </div>
    <div class="strength-list">
      <div class="strength-item">
        <span class="strength-num">01</span>
        <div class="strength-content">
          <h4>架构设计思维</h4>
          <p>深入理解 DDD 领域驱动设计，能够将复杂业务拆解为清晰的领域模型；熟悉微服务、工作流引擎等架构模式，具备从 0 到 1 的系统设计能力。</p>
        </div>
      </div>
      <div class="strength-item">
        <span class="strength-num">02</span>
        <div class="strength-content">
          <h4>Java 深度实践</h4>
          <p>精通 Spring 生态（事务机制、AOP、动态加载），深入掌握反射、注解、字节码增强等底层技术；具备 Drools 规则引擎并发问题排查与调优经验。</p>
        </div>
      </div>
      <div class="strength-item">
        <span class="strength-num">03</span>
        <div class="strength-content">
          <h4>设计模式与抽象能力</h4>
          <p>善于运用设计模式解决实际问题，如基于注解+事件驱动的字段变更追踪框架、轻量级工作流引擎设计，体现出色的抽象与解耦能力。</p>
        </div>
      </div>
      <div class="strength-item">
        <span class="strength-num">04</span>
        <div class="strength-content">
          <h4>技术广度与学习力</h4>
          <p>覆盖云原生（K8s）、AI 开发（Spring AI）、性能优化（JMH、Arthas）等多个领域；持有软考<strong>系统架构设计师</strong>高级认证，持续拓展技术边界。</p>
        </div>
      </div>
    </div>
  </div>

  <!-- ===== 技术栈 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">🛠️</span>
      <span>技术栈</span>
    </div>
    <div class="tech-grid">
      <div class="tech-card">
        <div class="card-header">
          <span class="card-icon">☕</span>
          <span class="card-label">Java 核心</span>
        </div>
        <div class="card-items">
          <span class="tech-tag orange">Spring Boot</span>
          <span class="tech-tag orange">Spring 事务</span>
          <span class="tech-tag orange">MyBatis</span>
          <span class="tech-tag orange">反射 & 注解</span>
          <span class="tech-tag orange">ByteBuddy</span>
          <span class="tech-tag orange">Drools</span>
        </div>
      </div>
      <div class="tech-card">
        <div class="card-header">
          <span class="card-icon">🏗️</span>
          <span class="card-label">架构 & 设计</span>
        </div>
        <div class="card-items">
          <span class="tech-tag purple">DDD</span>
          <span class="tech-tag purple">微服务架构</span>
          <span class="tech-tag purple">设计模式</span>
          <span class="tech-tag purple">工作流引擎</span>
          <span class="tech-tag purple">领域建模</span>
        </div>
      </div>
      <div class="tech-card">
        <div class="card-header">
          <span class="card-icon">☁️</span>
          <span class="card-label">云原生 & 运维</span>
        </div>
        <div class="card-items">
          <span class="tech-tag cyan">Kubernetes</span>
          <span class="tech-tag cyan">Docker</span>
          <span class="tech-tag cyan">Cloudflare</span>
          <span class="tech-tag cyan">Hugo</span>
          <span class="tech-tag cyan">Linux</span>
          <span class="tech-tag cyan">Git</span>
        </div>
      </div>
      <div class="tech-card">
        <div class="card-header">
          <span class="card-icon">🤖</span>
          <span class="card-label">AI & 工具</span>
        </div>
        <div class="card-items">
          <span class="tech-tag pink">Spring AI</span>
          <span class="tech-tag pink">Agent 开发</span>
          <span class="tech-tag green">JMH</span>
          <span class="tech-tag green">Arthas</span>
          <span class="tech-tag green">Redis</span>
        </div>
      </div>
    </div>
  </div>

  <!-- ===== 代表文章 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">📝</span>
      <span>代表文章</span>
    </div>
    <div class="article-list">
      <a class="article-item" href="/posts/互联网/设计/领域驱动设计ddd-理论实际/">
        <span class="article-badge design">设计</span>
        <div class="article-info">
          <div class="title">领域驱动设计 DDD - 理论 & 实际</div>
          <div class="desc">从核心概念到代码落地，深入解析 DDD 的聚合、充血模型、领域仓储与 MVC 对比</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
      <a class="article-item" href="/posts/互联网/设计/轻量工作流模块的前世今生/">
        <span class="article-badge design">设计</span>
        <div class="article-info">
          <div class="title">轻量工作流模块的前世今生</div>
          <div class="desc">从业务痛点出发，设计一套轻量级工作流引擎，实现业务流与工作流的解耦</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
      <a class="article-item" href="/posts/互联网/设计/字段变化记录功能-从业务层面到技术层面的设计演进/">
        <span class="article-badge design">设计</span>
        <div class="article-info">
          <div class="title">字段变化记录功能 - 从业务层面到技术层面的设计演进</div>
          <div class="desc">基于注解+事件驱动的通用字段变更追踪框架，体现抽象与解耦的设计思想</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
      <a class="article-item" href="/posts/互联网/spring/spring事务/">
        <span class="article-badge spring">Spring</span>
        <div class="article-info">
          <div class="title">Spring 事务</div>
          <div class="desc">编程式事务、声明式事务与事务同步机制的深度解析</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
      <a class="article-item" href="/posts/互联网/java/drools规则并发问题分析/">
        <span class="article-badge java">Java</span>
        <div class="article-info">
          <div class="title">Drools 规则并发问题分析 & 解决方案</div>
          <div class="desc">深入 Drools 源码，排查规则加载与校验的并发偏差及内存溢出问题</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
      <a class="article-item" href="/posts/互联网/spring/springai光速入门/">
        <span class="article-badge ai">AI</span>
        <div class="article-info">
          <div class="title">Spring AI 光速入门</div>
          <div class="desc">ChatModel、ChatClient、Prompt、Advisors 等 AI 开发核心概念与实战</div>
        </div>
        <span class="article-arrow">→</span>
      </a>
    </div>
  </div>

  <!-- ===== 成就 & 计划 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">🏆</span>
      <span>成就 & 计划</span>
    </div>
    <div class="achievement-grid">
      <div class="achieve-card done">
        <div class="achieve-icon">🎓</div>
        <div class="achieve-title">系统架构设计师</div>
        <div class="achieve-desc">软考高级 · 已认证</div>
      </div>
      <div class="achieve-card done">
        <div class="achieve-icon">🌐</div>
        <div class="achieve-title">独立博客搭建</div>
        <div class="achieve-desc">Hugo + Cloudflare Pages</div>
      </div>
      <div class="achieve-card done">
        <div class="achieve-icon">📖</div>
        <div class="achieve-title">技术体系沉淀</div>
        <div class="achieve-desc">IT 知识库 · 软考备考笔记</div>
      </div>
      <div class="achieve-card progress">
        <div class="achieve-icon">📋</div>
        <div class="achieve-title">高级项目管理</div>
        <div class="achieve-desc">软考高级 · 进行中</div>
      </div>
      <div class="achieve-card progress">
        <div class="achieve-icon">✍️</div>
        <div class="achieve-title">月度高质量文章</div>
        <div class="achieve-desc">持续输出 · 2026 目标</div>
      </div>
      <div class="achieve-card progress">
        <div class="achieve-icon">🤖</div>
        <div class="achieve-title">AI 工程化探索</div>
        <div class="achieve-desc">Spring AI · Agent 开发</div>
      </div>
    </div>
  </div>

  <!-- ===== 技术旅程 ===== -->
  <div class="about-section">
    <div class="about-section-title">
      <span class="icon">🗺️</span>
      <span>技术旅程</span>
    </div>
    <div class="timeline">
      <div class="timeline-item">
        <div class="time-label">2024</div>
        <div class="time-content">搭建个人技术博客</div>
        <div class="time-desc">从博客园到 Hugo + Cloudflare Pages，建立独立技术输出阵地</div>
      </div>
      <div class="timeline-item">
        <div class="time-label">2025</div>
        <div class="time-content">系统架构设计深耕</div>
        <div class="time-desc">通过软考系统架构设计师认证，深入 DDD、工作流引擎等架构设计实践</div>
      </div>
      <div class="timeline-item">
        <div class="time-label">2026</div>
        <div class="time-content">AI + 架构双线探索</div>
        <div class="time-desc">探索 Spring AI 与 Agent 开发，冲击高级项目管理认证，持续高质量输出</div>
      </div>
    </div>
  </div>

  <!-- ===== Footer ===== -->
  <div class="about-footer">
    <p><span class="footer-brand">lifepoem.fun</span></p>
    <p>生活不止眼前的苟且，还有诗和远方 🌊</p>
  </div>

</div>
