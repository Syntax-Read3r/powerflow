#!/usr/bin/env node
/*
 * teamchat-wait.js — block until the OTHER party posts a message addressed to ME in the ACTIVE
 * daily team-chat log, print that message, and exit 0. Poll-based (portable across Windows/Git
 * Bash, macOS and Linux — no inotify/fswatch). Designed to be launched as a background task so the
 * host harness notifies the agent the instant the watcher exits.
 *
 * Turn model — the file IS the source of truth, so it can never desync:
 *   Every block is "## <date> — <Sender> → <Recipient>". The newest block's Recipient is whose turn
 *   it is. This watcher fires (exit 0) only when the newest block is FROM someone else and addressed
 *   TO me. When the newest block is mine, I stay dormant — the other party owes the next message.
 *
 * Day rollover needs no calendar math: it always follows the newest-mtime "wk-N slash day.md" under
 * LOG_ROOT, so when tomorrow's file is first written it becomes the target automatically.
 *
 * Usage:
 *   node teamchat/bin/teamchat-wait.js                 # uses the CONFIG below
 *   node teamchat/bin/teamchat-wait.js --me Codex --interval 900
 *   node teamchat/bin/teamchat-wait.js --status        # print the current turn/target and exit (no waiting)
 *   node teamchat/bin/teamchat-wait.js --skip-current  # RE-ARM MODE (2026-08-01): baseline the newest
 *       block even when it is addressed to me, and fire only on something NEWER. Use this EXACTLY when
 *       re-arming while already processing the newest message — it closes the mid-checkpoint coverage
 *       gap (a follow-up posted while the agent is implementing used to go unnoticed until the next
 *       manual arm; observed 2026-08-01: a 16:08 Codex directive sat unseen past the 16:15 tick).
 *       NEVER use it when the newest addressed-to-me block is UNPROCESSED — that is the 07-30 deadlock.
 */

// ============================ ADJUST ME ============================
// How often (SECONDS) to check the log for a new message addressed to you.
// Fable/Claude: 300 (5 min).  Codex: 900 (15 min).  A `--interval` flag overrides this.
const POLL_INTERVAL_SECONDS = 300;

// Your identity/aliases as they appear as the RECIPIENT in "— Sender → Recipient" headers.
// The team-chat history signs this side as "Claude"; "Fable" is accepted as an alias. A `--me` flag
// (comma-separated) overrides this.
const ME_ALIASES = ["Claude", "Fable"];

// Root directory holding the dated "wk-N slash day.md" logs. A `--root` flag overrides this.
const LOG_ROOT = "teams-chat/main-project";
// ===================================================================

const fs = require("fs");
const path = require("path");

// ---- args (override the CONFIG above) -------------------------------------
const argv = process.argv.slice(2);
const flag = (name) => {
	const i = argv.indexOf(`--${name}`);
	return i !== -1 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : undefined;
};
const has = (name) => argv.includes(`--${name}`);

const intervalMs = (Number(flag("interval")) || POLL_INTERVAL_SECONDS) * 1000;
const meAliases = (flag("me") ? flag("me").split(",") : ME_ALIASES).map((s) => s.trim().toLowerCase()).filter(Boolean);
const root = flag("root") || LOG_ROOT;
const statusOnly = has("status");
const skipCurrent = has("skip-current");

if (meAliases.length === 0) {
	console.error("teamchat-wait: no identity — set ME_ALIASES or pass --me <name>");
	process.exit(2);
}

// ---- helpers --------------------------------------------------------------
// Message headers only: "## <date/time> <SEP> <Sender> <ARROW> <Recipient>".
// SEP and ARROW accept BOTH the canonical Unicode punctuation (em/en dash, →) AND plain ASCII
// (- / --, ->), because a co-agent may type either — the em-dash-only form silently missed an
// ASCII-headed block once. The SEP must be space-delimited so it never matches the hyphens inside
// an ISO date (2026-07-21 has no surrounding spaces); the arrow may be Unicode or "->".
// `#{1,2}`: block headers are H1 (`#`) from 2026-07-30 per owner directive — easier to trace where
// each conversation starts. H2 is still accepted so the three weeks of existing logs keep parsing.
const HEADER = /^#{1,2}\s+.*?\s(?:—|–|-{1,2})\s+([^\n]*?)\s+(?:→|->)\s+([^\n]+?)\s*$/gm;
// Only files that live under a "wk-<week>" directory are daily logs (skips content.md, side-projects…).
const DAILY_LOG = /(^|[\\/])wk-[^\\/]+[\\/][^\\/]+\.md$/;

function newestDailyLog() {
	let best = null;
	(function walk(dir) {
		let entries;
		try {
			entries = fs.readdirSync(dir, { withFileTypes: true });
		} catch {
			return;
		}
		for (const e of entries) {
			const p = path.join(dir, e.name);
			if (e.isDirectory()) walk(p);
			else if (e.isFile() && e.name.endsWith(".md") && DAILY_LOG.test(p)) {
				const mtime = fs.statSync(p).mtimeMs;
				if (!best || mtime > best.mtime) best = { file: p, mtime };
			}
		}
	})(root);
	return best && best.file;
}

function lastMessage(file) {
	let text;
	try {
		text = fs.readFileSync(file, "utf8");
	} catch {
		return null;
	}
	let last = null;
	let m;
	HEADER.lastIndex = 0;
	while ((m = HEADER.exec(text)) !== null) {
		last = { sender: m[1].trim(), recipient: m[2].trim(), index: m.index };
	}
	return last ? { ...last, tail: text.slice(last.index) } : null;
}

function addressedToMe(recipient) {
	const r = recipient.toLowerCase();
	return meAliases.some((a) => r.includes(a)) || /\b(both|all|team|everyone)\b/.test(r);
}

function isFromMe(sender) {
	const s = sender.toLowerCase();
	return meAliases.some((a) => s === a || s.includes(a));
}

function signature(file, msg) {
	return msg ? `${file}|${msg.index}|${msg.sender}→${msg.recipient}` : `${file}|<no-message>`;
}

// ---- --status: report current turn and exit -------------------------------
if (statusOnly) {
	const file = newestDailyLog();
	if (!file) {
		console.log(`no daily log found under ${root}`);
		process.exit(0);
	}
	const msg = lastMessage(file);
	if (!msg) {
		console.log(`active log: ${file}\nno message blocks yet`);
		process.exit(0);
	}
	const mine = isFromMe(msg.sender);
	const forMe = addressedToMe(msg.recipient);
	console.log(`active log:   ${file}`);
	console.log(`last message: ${msg.sender} → ${msg.recipient}`);
	console.log(`whose turn:   ${msg.recipient}${forMe ? " (that's me)" : ""}`);
	console.log(`watcher would: ${!mine && forMe ? "FIRE now (a message is waiting for me)" : "WAIT (I owe nothing / it's the other party's turn)"}`);
	process.exit(0);
}

// ---- watch loop -----------------------------------------------------------
// Baseline = what the newest block was at startup, so we only fire on something NEW.
let baseline = signature(newestDailyLog(), newestDailyLog() ? lastMessage(newestDailyLog()) : null);
console.error(
	`teamchat-wait: watching ${root} as [${meAliases.join(", ")}], every ${intervalMs / 1000}s. ` +
		`Baseline turn: ${baseline}`,
);

// ---- STARTUP DEADLOCK GUARD (2026-07-30) ----------------------------------
// A message addressed to me may ALREADY be the newest block when the watcher starts — for example
// when it is armed during a reinitiate while it is still my turn. Baselining that message means
// waiting for a NEWER one, which the other party will never send because they are correctly holding
// for my reply. Both sides then wait for each other and the loop is silently dead.
//
// Observed on 2026-07-30: armed at 07:26 against Codex's 01:17 release, `--status` reported
// "FIRE now (a message is waiting for me)" while the running watcher sat waiting indefinitely.
//
// So: if a message is already waiting at startup, deliver it NOW instead of baselining it. A
// duplicate wake for something already read is merely noisy; a missed wake stalls the whole loop.
//
// --skip-current (2026-08-01) deliberately SUPPRESSES this guard for the one legitimate case the
// guard would misread: re-arming while the newest addressed-to-me block is the very message being
// processed right now. Without it, coverage dies the moment a watcher fires — it exits on delivery,
// and a follow-up posted mid-checkpoint waits for a human to notice. With it, the in-hand message
// becomes the baseline and anything NEWER still fires.
if (!skipCurrent) {
	const startupFile = newestDailyLog();
	const startupMsg = startupFile ? lastMessage(startupFile) : null;
	if (startupMsg && !isFromMe(startupMsg.sender) && addressedToMe(startupMsg.recipient)) {
		console.log(
			`UPDATE (already waiting at startup) — ${startupMsg.sender} → ${startupMsg.recipient} in ${startupFile}\n`,
		);
		console.log(startupMsg.tail);
		process.exit(0);
	}
}

function tick() {
	const file = newestDailyLog();
	const msg = file && lastMessage(file);
	if (file && msg) {
		const sig = signature(file, msg);
		if (sig !== baseline) {
			if (!isFromMe(msg.sender) && addressedToMe(msg.recipient)) {
				console.log(`UPDATE — ${msg.sender} → ${msg.recipient} in ${file}\n`);
				console.log(msg.tail);
				process.exit(0); // the harness notifies the agent here
			}
			// A new block that isn't for me (mine, or addressed to a third party) — advance and keep waiting.
			baseline = sig;
		}
	}
	setTimeout(tick, intervalMs);
}
setTimeout(tick, intervalMs);
