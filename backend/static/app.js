// Daily Concierge Frontend Application Logic

const state = {
  activeTab: "tab-today",
  gachaCategory: "ALL",
  gachaCurrentItem: null,
  gachaTimerInterval: null,
  gachaRemainingSec: 1800,
  snsSourceFilter: "all",
  snsUnreadOnly: false,
};

function showToast(message) {
  const toast = document.getElementById("toast");
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add("show");
  setTimeout(() => toast.classList.remove("show"), 2600);
}

async function apiGet(path) {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`GET ${path} failed: ${res.status}`);
  return res.json();
}

async function apiPost(path, body = {}) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`POST ${path} failed: ${errText}`);
  }
  return res.json();
}

// ------------------------------------------------------------------
// Navigation
// ------------------------------------------------------------------
function setupNavigation() {
  const allButtons = document.querySelectorAll("[data-tab]");
  allButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const target = btn.getAttribute("data-tab");
      state.activeTab = target;

      document.querySelectorAll(".tab-pane").forEach((pane) => {
        pane.classList.toggle("active", pane.id === target);
      });
      allButtons.forEach((b) => {
        b.classList.toggle("active", b.getAttribute("data-tab") === target);
      });

      if (target === "tab-sns") loadSnsFeeds();
      if (target === "tab-curation") loadCurationFeeds();
      if (target === "tab-sources") loadSourcesTab();
    });
  });
}

// ------------------------------------------------------------------
// Dashboard Overview Loader
// ------------------------------------------------------------------
async function loadDashboard() {
  try {
    const data = await apiGet("/api/dashboard");
    renderStatus(data.status);
    renderWeather(data.weather);
    renderSuggestions(data.suggestions);
    renderYaruMemo(data.yaru_memo);
    renderGachaStatus(data.gacha);
    renderSchedule(data.schedule);
    renderProfile(data.profile);
    updateUnreadBadge(data.feeds_summary?.total_unread || 0);
  } catch (err) {
    console.error(err);
    showToast("データの読み込み中にエラーが発生しました");
  }
}

function renderStatus(status) {
  const label = document.getElementById("vault-status-label");
  if (label && status) {
    const okText = status.vault_accessible ? "Obsidian Vault 接続OK" : "ローカルキャッシュ動作中";
    label.textContent = `${okText}`;
  }
}

function updateUnreadBadge(count) {
  const badge = document.getElementById("nav-unread-badge");
  if (badge) {
    badge.textContent = String(count);
  }
}

// ------------------------------------------------------------------
// Weather & AI Suggestions
// ------------------------------------------------------------------
function renderWeather(w) {
  if (!w) return;
  document.getElementById("weather-icon").textContent = w.icon || "🌤️";
  document.getElementById("weather-temp").textContent = `${w.temperature}℃`;
  document.getElementById("weather-condition").textContent = `${w.condition} (最高 ${w.temp_max}℃ / 最低 ${w.temp_min}℃・降水確率 ${w.precip_prob}%)`;
  document.getElementById("weather-location").textContent = `📍 ${w.location}`;
  document.getElementById("weather-advice").textContent = w.advice || "";
}

function renderSuggestions(suggData) {
  const container = document.getElementById("proposal-container");
  if (!container || !suggData) return;
  container.innerHTML = "";

  (suggData.proposals || []).forEach((p) => {
    const badgeClass =
      p.badge === "Must" ? "must" : p.badge === "Want" ? "want" : "trial";
    const card = document.createElement("div");
    card.className = "proposal-card";
    card.innerHTML = `
      <div>
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
          <span class="badge ${badgeClass}">${p.slot || p.badge}</span>
          <span style="font-size:11px;color:#93c5fd;">⏱️ ${p.estimated_time || "30分"} / 💰 ${p.estimated_cost || "¥0"}</span>
        </div>
        <div class="proposal-title">${p.title}</div>
        <div class="proposal-detail" style="margin-top:6px;">${p.action_detail}</div>
      </div>
      <div class="proposal-reason">💡 <strong>提案理由:</strong> ${p.reason}</div>
    `;
    container.appendChild(card);
  });
}

// ------------------------------------------------------------------
// Obsidian やるメモ.md 双方向チェックリスト＆クイック追記
// ------------------------------------------------------------------
function renderYaruMemo(yaru) {
  const wrap = document.getElementById("yaru-memo-sections");
  if (!wrap || !yaru || !yaru.sections) return;
  wrap.innerHTML = "";

  const sectionMeta = [
    { key: "morning_routine", title: "🌅 朝ルーチン" },
    { key: "today_and_home", title: "📌 今・今日・帰ったら" },
    { key: "tomorrow_and_holiday", title: "🗓️ 明日・休日・10/29〜11/8 休暇計画" },
    { key: "maybe_want", title: "💭 やりたいかもだけどやらなくてもいいやつ" },
    { key: "done_and_archive", title: "✅ 完了・消しといて" },
  ];

  sectionMeta.forEach(({ key, title }) => {
    const items = yaru.sections[key] || [];
    if (!items.length) return;

    const secHeader = document.createElement("div");
    secHeader.className = "memo-section-title";
    secHeader.textContent = `${title} (${items.length})`;
    wrap.appendChild(secHeader);

    items.forEach((item) => {
      if (item.is_header) {
        const subH = document.createElement("div");
        subH.style.cssText = "font-size:12px;font-weight:700;color:#60a5fa;margin:6px 0 2px 4px;";
        subH.textContent = item.text;
        wrap.appendChild(subH);
        return;
      }

      const row = document.createElement("div");
      row.className = `task-item ${item.checked ? "checked" : ""}`;

      if (item.is_checkbox) {
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = !!item.checked;
        cb.addEventListener("change", async () => {
          try {
            await apiPost("/api/obsidian/toggle-task", {
              line_number: item.line_number,
              text_match: item.text,
              checked: cb.checked,
            });
            row.classList.toggle("checked", cb.checked);
            showToast(`Obsidian『やるメモ.md』(${item.line_number}行目)を更新しました`);
          } catch (e) {
            cb.checked = !cb.checked;
            showToast("更新に失敗しました");
          }
        });
        row.appendChild(cb);
      } else {
        const bullet = document.createElement("span");
        bullet.textContent = "•";
        bullet.style.color = "#60a5fa";
        row.appendChild(bullet);
      }

      const txt = document.createElement("span");
      txt.textContent = item.text;
      row.appendChild(txt);
      wrap.appendChild(row);
    });
  });
}

// ------------------------------------------------------------------
// 進化版『趣味ガチャ』 (Obsidian 完全連動 + 30分タイマー)
// ------------------------------------------------------------------
function renderGachaStatus(gacha) {
  if (!gacha) return;
  const c = gacha.counts || {};
  document.getElementById("cnt-all").textContent = c.ALL ?? 0;
  document.getElementById("cnt-game").textContent = c.GAME ?? 0;
  document.getElementById("cnt-story").textContent = c.STORY ?? 0;
  document.getElementById("cnt-single").textContent = c.SINGLE ?? 0;

  const doingBox = document.getElementById("gacha-doing-list");
  if (doingBox) {
    const doing = gacha.current_doing?.doing || [];
    const done = gacha.current_doing?.done || [];
    doingBox.innerHTML = doing.length
      ? doing.map((t) => `<span class="tag-chip">🎯 ${t}</span>`).join(" ")
      : `<span style="color:var(--text-muted);">現在進行中リストは空です（完了済み: ${done.slice(0, 4).join(" / ")}）</span>`;
  }
}

function setupGachaControls() {
  document.querySelectorAll(".gacha-cat-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.gachaCategory = btn.getAttribute("data-cat");
      document.querySelectorAll(".gacha-cat-btn").forEach((b) => {
        const active = b.getAttribute("data-cat") === state.gachaCategory;
        b.className = `dark-btn ${active ? "btn-level-4" : "btn-level-2"} gacha-cat-btn`;
      });
    });
  });

  const drawBtn = document.getElementById("btn-draw-gacha");
  if (drawBtn) {
    drawBtn.addEventListener("click", async () => {
      stopGachaTimer();
      const res = await apiPost("/api/obsidian/gacha/draw", {
        category: state.gachaCategory,
      });
      renderGachaStatus({ counts: res.counts, current_doing: { doing: [], done: [] } });
      const area = document.getElementById("gacha-result-area");
      const trialBox = document.getElementById("gacha-trial-box");
      const initBtns = document.getElementById("gacha-buttons-initial");

      if (res.empty || !res.item) {
        area.style.display = "block";
        document.getElementById("gacha-item-title").textContent = "このカテゴリの積みリストは空です";
        initBtns.style.display = "none";
        trialBox.style.display = "none";
        return;
      }

      state.gachaCurrentItem = res.item;
      area.style.display = "block";
      trialBox.style.display = "none";
      initBtns.style.display = "flex";
      document.getElementById("gacha-source-badge").textContent = `カテゴリ: [${res.item.source}]`;
      document.getElementById("gacha-item-title").textContent = res.item.title;
    });
  }

  // 試す (30分タイマー開始)
  document.getElementById("btn-gacha-try")?.addEventListener("click", () => {
    document.getElementById("gacha-buttons-initial").style.display = "none";
    document.getElementById("gacha-trial-box").style.display = "block";
    startGachaTimer(30 * 60);
    showToast("⏱️ 30分試食タイマーを開始しました！");
  });

  // いまはやらない (再抽選)
  document.getElementById("btn-gacha-skip")?.addEventListener("click", () => {
    document.getElementById("btn-draw-gacha").click();
  });

  // もう興味ない -> 元ファイルから削除し 趣味ガチャ_log.md へ記録
  document.getElementById("btn-gacha-drop")?.addEventListener("click", async () => {
    if (!state.gachaCurrentItem) return;
    const item = state.gachaCurrentItem;
    await apiPost("/api/obsidian/gacha/action", {
      action: "drop",
      title: item.title,
      source: item.source,
      raw_line: item.raw,
    });
    document.getElementById("gacha-result-area").style.display = "none";
    showToast(`『${item.title}』を元リストから削除し、趣味ガチャ_log.md に記録しました`);
    const poolData = await apiGet("/api/obsidian/gacha/pool");
    renderGachaStatus(poolData);
  });

  // よかった -> 元ファイルから削除し いまやってる・見てるもの.md へ移動
  document.getElementById("btn-gacha-good")?.addEventListener("click", async () => {
    if (!state.gachaCurrentItem) return;
    stopGachaTimer();
    const item = state.gachaCurrentItem;
    await apiPost("/api/obsidian/gacha/action", {
      action: "good",
      title: item.title,
      source: item.source,
      raw_line: item.raw,
    });
    document.getElementById("gacha-result-area").style.display = "none";
    showToast(`🎉『${item.title}』を『いまやってる・見てるもの.md』へ追加しました！`);
    const poolData = await apiGet("/api/obsidian/gacha/pool");
    renderGachaStatus(poolData);
  });

  // あんまりだった
  document.getElementById("btn-gacha-meh")?.addEventListener("click", () => {
    stopGachaTimer();
    document.getElementById("gacha-result-area").style.display = "none";
    showToast("試食おつかれさまでした！（リストはそのまま保持）");
  });
}

function startGachaTimer(seconds) {
  stopGachaTimer();
  state.gachaRemainingSec = seconds;
  updateTimerLabel();
  state.gachaTimerInterval = setInterval(() => {
    state.gachaRemainingSec--;
    if (state.gachaRemainingSec <= 0) {
      stopGachaTimer();
      showToast("⏰ 30分経過しました！『よかった』か『あんまりだった』を選びましょう！");
      return;
    }
    updateTimerLabel();
  }, 1000);
}

function stopGachaTimer() {
  if (state.gachaTimerInterval) {
    clearInterval(state.gachaTimerInterval);
    state.gachaTimerInterval = null;
  }
}

function updateTimerLabel() {
  const el = document.getElementById("gacha-timer");
  if (!el) return;
  const m = String(Math.floor(state.gachaRemainingSec / 60)).padStart(2, "0");
  const s = String(state.gachaRemainingSec % 60).padStart(2, "0");
  el.textContent = `${m}:${s}`;
}

// ------------------------------------------------------------------
// Schedule & Profile
// ------------------------------------------------------------------
function renderSchedule(sched) {
  const box = document.getElementById("schedule-timeline");
  if (!box || !sched) return;
  box.innerHTML = "";

  (sched.upcoming_milestones || []).forEach((ev) => {
    const div = document.createElement("div");
    div.className = `timeline-item ${ev.is_milestone ? "milestone" : ""}`;
    div.innerHTML = `
      <div class="timeline-date">${ev.date}<br/><span style="font-size:10.5px;color:var(--text-muted);">${ev.time}</span></div>
      <div>
        <div style="font-weight:700;color:#fff;">${ev.title}</div>
        <div style="font-size:11.5px;color:var(--text-muted);">📍 ${ev.location || "-"} / 💰 ${ev.cost_note || "-"}</div>
      </div>
    `;
    box.appendChild(div);
  });
}

function renderProfile(prof) {
  const box = document.getElementById("profile-summary-box");
  if (!box || !prof) return;

  const b = prof.budget_and_finance || {};
  const projects = prof.active_projects || [];
  const tags = prof.interest_tags || [];

  box.innerHTML = `
    <div style="background:rgba(0,102,255,0.1);border:1px solid rgba(0,102,255,0.3);padding:10px;border-radius:8px;margin-bottom:10px;">
      <div style="font-weight:700;color:#93c5fd;margin-bottom:4px;">💰 予算＆Quest 3 購入計画</div>
      <div>・現在資産: <strong>${b.current_assets}</strong> ＋ 来月バイト代: <strong>${b.expected_income}</strong></div>
      <div>・最優先目標: <strong>${b.must_buy_goal}</strong></div>
      <div style="font-size:11.5px;color:var(--text-muted);margin-top:3px;">${b.spending_policy}</div>
    </div>

    <div style="font-weight:700;color:#cbd5e1;margin-bottom:6px;">🚀 進行中プロジェクト</div>
    ${projects
      .map(
        (p) => `
      <div style="padding:7px 9px;background:rgba(255,255,255,0.03);border-radius:6px;margin-bottom:6px;">
        <div style="font-weight:700;font-size:12.5px;color:#fff;">${p.title} <span style="color:#34d399;font-size:11px;">(${p.deadline})</span></div>
        <div style="font-size:11.5px;color:var(--text-muted);">${p.description}</div>
      </div>
    `
      )
      .join("")}

    <div class="tag-list">
      ${tags.map((t) => `<span class="tag-chip"># ${t}</span>`).join("")}
    </div>
  `;
}

// ------------------------------------------------------------------
// TAB 2: SNS 差分フィード
// ------------------------------------------------------------------
async function loadSnsFeeds() {
  const q = new URLSearchParams({
    category: "sns_diff",
    source_type: state.snsSourceFilter,
    unread_only: String(state.snsUnreadOnly),
  });
  const data = await apiGet(`/api/feeds?${q.toString()}`);
  updateUnreadBadge(data.total_unread || 0);
  renderFeedList("sns-feed-list", data.items || []);
}

function renderFeedList(containerId, items) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.innerHTML = "";

  if (!items.length) {
    container.innerHTML = `<div style="padding:24px;text-align:center;color:var(--text-muted);">未読の差分アイテムはありません（Inbox Zero達成！🎉）</div>`;
    return;
  }

  items.forEach((item) => {
    const card = document.createElement("div");
    card.className = `feed-card ${item.is_read ? "read" : "unread"}`;
    card.innerHTML = `
      <div class="feed-meta">
        <span><strong>[${item.source_type.toUpperCase()}]</strong> ${item.source_name}</span>
        <span>🕒 ${item.published_at} / 重要度 ${item.importance_score}%</span>
      </div>
      <div class="feed-title">
        <a href="${item.url}" target="_blank" rel="noopener noreferrer">${item.title}</a>
      </div>
      <div class="feed-summary">${item.summary || ""}</div>
      ${
        item.why_it_matters
          ? `<div class="feed-why">💡 <strong>今の私への関連・活かし方:</strong> ${item.why_it_matters}</div>`
          : ""
      }
      <div class="feed-actions">
        <button class="dark-btn ${item.is_bookmarked ? "btn-good" : "btn-level-2"} btn-clip" data-id="${item.id}">
          ${item.is_bookmarked ? "✓ Obsidianクリップ済" : "📎 Obsidian『やるメモ』にクリップ"}
        </button>
        ${
          !item.is_read
            ? `<button class="dark-btn btn-level-1 btn-read" data-id="${item.id}">既読にする</button>`
            : `<span style="font-size:12px;color:var(--text-muted);align-self:center;">✓ 既読</span>`
        }
      </div>
    `;

    card.querySelector(".btn-read")?.addEventListener("click", async () => {
      await apiPost("/api/feeds/mark-read", { item_ids: [item.id] });
      card.classList.remove("unread");
      card.classList.add("read");
      showToast("既読にしました");
      loadDashboard();
    });

    card.querySelector(".btn-clip")?.addEventListener("click", async (e) => {
      const btn = e.currentTarget;
      const res = await apiPost("/api/feeds/bookmark", {
        item_id: item.id,
        clip_to_vault: true,
      });
      if (res.is_bookmarked) {
        btn.className = "dark-btn btn-good btn-clip";
        btn.textContent = "✓ Obsidianクリップ済";
        showToast("Obsidian『やるメモ.md』(やりたいかもリスト) にクリップ追記しました！");
      } else {
        btn.className = "dark-btn btn-level-2 btn-clip";
        btn.textContent = "📎 Obsidian『やるメモ』にクリップ";
      }
    });

    container.appendChild(card);
  });
}

// ------------------------------------------------------------------
// TAB 3: AIニュース・お得情報・良記事キュレーション
// ------------------------------------------------------------------
async function loadCurationFeeds() {
  const [aiData, dealsData, readingData] = await Promise.all([
    apiGet("/api/feeds?category=ai_news"),
    apiGet("/api/feeds?category=deals"),
    apiGet("/api/feeds?category=reading"),
  ]);
  renderFeedList("curation-ai-list", aiData.items || []);
  renderFeedList("curation-deals-list", dealsData.items || []);
  renderFeedList("curation-reading-list", readingData.items || []);
}

// ------------------------------------------------------------------
// TAB 4: URL＋自然言語指示での監視ソース追加 ＆ 設定
// ------------------------------------------------------------------
async function loadSourcesTab() {
  const [srcRes, statusRes] = await Promise.all([
    apiGet("/api/sources"),
    apiGet("/api/status"),
  ]);

  const listEl = document.getElementById("watch-sources-list");
  if (listEl) {
    listEl.innerHTML = "";
    (srcRes.sources || []).forEach((s) => {
      const div = document.createElement("div");
      div.className = "feed-card";
      div.innerHTML = `
        <div class="feed-meta">
          <span><strong>[${s.source_type.toUpperCase()}]</strong> カテゴリ: ${s.category}</span>
          <span>最終巡回: ${s.last_checked_at || "未巡回"}</span>
        </div>
        <div class="feed-title">${s.name}</div>
        <div style="font-size:12px;color:#93c5fd;word-break:break-all;margin-bottom:4px;">🔗 ${s.url}</div>
        <div style="font-size:12.5px;color:#cbd5e1;">📝 指示: 「${s.instruction}」</div>
      `;
      listEl.appendChild(div);
    });
  }

  const statEl = document.getElementById("system-status-detail");
  if (statEl && statusRes) {
    statEl.innerHTML = `
      <div>・<strong>Obsidian Vault パス:</strong> <code>${statusRes.vault_path}</code></div>
      <div>・<strong>Vault アクセス状態:</strong> ${statusRes.vault_accessible ? "✅ 正常（双方向同期有効）" : "⚠️ フォールバック中"}</div>
      <div>・<strong>ローカルDBパス:</strong> <code>${statusRes.db_path}</code></div>
      <div>・<strong>天気取得エリア:</strong> ${statusRes.weather_location} (Open-Meteo API)</div>
      <div>・<strong>Gemini API キー:</strong> ${statusRes.has_gemini_key ? "✅ 設定済み" : "未設定（Vaultスマートルールエンジン動作中）"}</div>
    `;
  }
}

// ------------------------------------------------------------------
// Event Listeners Initialization
// ------------------------------------------------------------------
document.addEventListener("DOMContentLoaded", () => {
  setupNavigation();
  setupGachaControls();
  loadDashboard();

  // Quick Memo Form
  document.getElementById("form-quick-memo")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const input = document.getElementById("input-quick-memo");
    const secSelect = document.getElementById("select-memo-section");
    const text = input.value.trim();
    if (!text) return;

    const res = await apiPost("/api/obsidian/quick-memo", {
      text,
      target_section: secSelect.value,
      as_checkbox: true,
    });
    input.value = "";
    showToast(`『やるメモ.md』の [${res.section}] セクションに追記しました！`);
    const yaru = await apiGet("/api/obsidian/yaru-memo");
    renderYaruMemo(yaru);
  });

  document.getElementById("btn-reload-memo")?.addEventListener("click", async () => {
    const yaru = await apiGet("/api/obsidian/yaru-memo");
    renderYaruMemo(yaru);
    showToast("『やるメモ.md』を再読み込みしました");
  });

  document.getElementById("btn-refresh-suggestions")?.addEventListener("click", async () => {
    const sugg = await apiGet("/api/concierge/suggestions");
    renderSuggestions(sugg);
    showToast("AI行動提案を更新しました");
  });

  // SNS Filters
  document.querySelectorAll(".sns-filter-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.snsSourceFilter = btn.getAttribute("data-source");
      document.querySelectorAll(".sns-filter-btn").forEach((b) => {
        const active = b.getAttribute("data-source") === state.snsSourceFilter;
        b.className = `dark-btn ${active ? "btn-level-4" : "btn-level-2"} sns-filter-btn`;
      });
      loadSnsFeeds();
    });
  });

  document.getElementById("toggle-unread-only")?.addEventListener("change", (e) => {
    state.snsUnreadOnly = e.target.checked;
    loadSnsFeeds();
  });

  document.getElementById("btn-mark-all-sns-read")?.addEventListener("click", async () => {
    await apiPost("/api/feeds/mark-read", {
      category: "sns_diff",
      mark_all: true,
    });
    showToast("SNS差分フィードを一括既読にしました！");
    loadSnsFeeds();
    loadDashboard();
  });

  document.getElementById("btn-crawl-now")?.addEventListener("click", async () => {
    showToast("ウォッチソースを巡回中...");
    const res = await apiPost("/api/feeds/refresh", {});
    showToast(`巡回完了！ (${res.checked_sources}ソース確認 / 新着 ${res.new_items_added}件)`);
    loadSnsFeeds();
  });

  // Add Watch Source Preview & Submit
  async function handleSourceAnalyze(saveFlag) {
    const url = document.getElementById("input-source-url").value.trim();
    const instruction = document.getElementById("input-source-instruction").value.trim();
    const name = document.getElementById("input-source-name").value.trim() || null;
    const category = document.getElementById("select-source-category").value;
    if (!url || !instruction) {
      showToast("URLと取得指示を入力してください");
      return;
    }

    const res = await apiPost("/api/sources/analyze", {
      url,
      instruction,
      name,
      category,
      save: saveFlag,
    });

    const box = document.getElementById("source-analysis-result");
    box.style.display = "block";
    document.getElementById("source-rule-json").textContent = JSON.stringify(
      res.extraction_rule,
      null,
      2
    );
    document.getElementById("source-preview-items").innerHTML = (res.preview_items || [])
      .map(
        (p) =>
          `<div style="padding:6px 0;border-bottom:1px solid var(--border-subtle);">
            <strong>${p.title}</strong><br/>
            <span style="color:var(--text-muted);">${p.summary || ""}</span>
          </div>`
      )
      .join("");

    if (saveFlag) {
      showToast(`監視ソース『${res.name}』を登録し、初回差分を取得しました！`);
      loadSourcesTab();
      loadDashboard();
    } else {
      showToast("抽出ルールの自動解析が完了しました");
    }
  }

  document.getElementById("btn-preview-source")?.addEventListener("click", () => {
    handleSourceAnalyze(false);
  });

  document.getElementById("form-add-source")?.addEventListener("submit", (e) => {
    e.preventDefault();
    handleSourceAnalyze(true);
  });
});
