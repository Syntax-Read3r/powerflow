#!/usr/bin/env node
/*
 * Independent team-chat → Codex wake connector.
 *
 * The committed script contains no session IDs. `install` reads CODEX_THREAD_ID from the current
 * Codex process, stores it in a private local config (D: by default), and registers a Windows task
 * at wall-clock :00/:15/:30/:45. Each task invocation is a one-shot, zero-model-token precheck. It
 * resumes the pinned Codex thread only when the current team-chat log's newest message is from
 * someone else and addressed to Codex.
 *
 * Commands:
 *   node teamchat/bin/teamchat-codex-wake.js install [--interval 15] [--state-root D:\...]
 *   node teamchat/bin/teamchat-codex-wake.js arm     [--repo <repoRoot>]
 *   node teamchat/bin/teamchat-codex-wake.js disarm  [--repo <repoRoot>]
 *   node teamchat/bin/teamchat-codex-wake.js check   --config D:\...\config.json
 *   node teamchat/bin/teamchat-codex-wake.js run     --config D:\...\config.json
 *   node teamchat/bin/teamchat-codex-wake.js status  --config D:\...\config.json
 *   node teamchat/bin/teamchat-codex-wake.js uninstall --config D:\...\config.json
 *   node teamchat/bin/teamchat-codex-wake.js self-test
 *
 * BOOT-SESSION ARM GUARD (owner directive, 2026-08-01): the team room must NOT survive a PC
 * shutdown. The scheduled task inevitably does (Task Scheduler definitions persist, and
 * StartWhenAvailable fires the missed tick right after boot), so the guard lives HERE: `run` is
 * DORMANT unless `<repoRoot>/team-room/state/armed.json` was written during the CURRENT boot
 * session. The stamp records the boot identity (clock time minus uptime); a reboot changes it, so
 * every stamp dies with the boot it was written in — no clock comparison against wall time, which
 * this machine is known to rewind across restarts. Re-arming is the reinit protocol's job
 * (`arm` from the repo root), per project. Dormant ticks spawn nothing, consume nothing and write
 * nothing.
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const VERSION = 1;
const DEFAULT_AGENT = "Codex";
const DEFAULT_INTERVAL_MINUTES = 15;
const MAX_RUNTIME_MS = 2 * 60 * 60 * 1000;
// `#{1,2}`: block headers are H1 (`#`) from 2026-07-30 per owner directive — easier to trace where
// each conversation starts. H2 is still accepted so existing logs keep parsing.
const HEADER = /^#{1,2}\s+(.+?)\s+—\s*([^\n→]+?)\s*→\s*([^\n]+?)\s*$/gm;

function fail(message) {
	throw new Error(`teamchat-codex-wake: ${message}`);
}

function argsOf(argv) {
	const out = { _: [] };
	for (let i = 0; i < argv.length; i++) {
		const token = argv[i];
		if (!token.startsWith("--")) {
			out._.push(token);
			continue;
		}
		const key = token.slice(2);
		const value = argv[i + 1];
		if (value !== undefined && !value.startsWith("--")) {
			out[key] = value;
			i++;
		} else {
			out[key] = true;
		}
	}
	return out;
}

function asPositiveInt(value, fallback, name) {
	if (value === undefined) return fallback;
	const parsed = Number(value);
	if (!Number.isInteger(parsed) || parsed < 1 || parsed > 1440) fail(`${name} must be 1..1440`);
	return parsed;
}

function sha(value) {
	return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

function atomicJson(file, value) {
	fs.mkdirSync(path.dirname(file), { recursive: true });
	const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
	fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
	fs.renameSync(tmp, file);
}

function readJson(file, what) {
	let parsed;
	try {
		parsed = JSON.parse(fs.readFileSync(file, "utf8"));
	} catch (error) {
		fail(`cannot read ${what} at ${file}: ${error.message}`);
	}
	return parsed;
}

function parseMessages(file) {
	const text = fs.readFileSync(file, "utf8");
	const messages = [];
	HEADER.lastIndex = 0;
	let match;
	while ((match = HEADER.exec(text)) !== null) {
		messages.push({
			date: match[1].trim(),
			sender: match[2].trim(),
			recipient: match[3].trim(),
			index: match.index,
		});
	}
	return messages;
}

function currentLog(repoRoot, indexRelative) {
	const indexFile = path.resolve(repoRoot, indexRelative);
	const text = fs.readFileSync(indexFile, "utf8");
	const section = text.match(/## Current log\s+([\s\S]*?)(?=\n## |$)/);
	if (!section) fail(`${indexRelative} has no '## Current log' section`);
	const firstLink = section[1].match(/\[[^\]]+\]\(([^)]+)\)/);
	if (!firstLink) fail(`${indexRelative} has no current-log link`);
	const decoded = decodeURIComponent(firstLink[1]);
	const resolved = path.resolve(path.dirname(indexFile), decoded);
	if (!fs.existsSync(resolved)) fail(`current log does not exist: ${resolved}`);
	return resolved;
}

function normalizedAliases(config) {
	return config.aliases.map((value) => value.trim().toLowerCase()).filter(Boolean);
}

function isFromAgent(sender, aliases) {
	const normalized = sender.trim().toLowerCase();
	return aliases.some((alias) => normalized === alias);
}

function isAddressedToAgent(recipient, aliases) {
	const normalized = recipient.toLowerCase();
	return aliases.some((alias) => new RegExp(`(^|[^a-z0-9_-])${escapeRegExp(alias)}([^a-z0-9_-]|$)`, "i").test(normalized));
}

function escapeRegExp(value) {
	return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function inspect(config) {
	const log = currentLog(config.repoRoot, config.indexRelative);
	const messages = parseMessages(log);
	const latest = messages.at(-1) || null;
	const aliases = normalizedAliases(config);
	const signature = latest
		? sha(`${path.relative(config.repoRoot, log)}\n${latest.index}\n${latest.sender}\n${latest.recipient}`)
		: sha(`${path.relative(config.repoRoot, log)}\n<empty>`);
	return {
		log,
		latest,
		signature,
		actionable: Boolean(latest && !isFromAgent(latest.sender, aliases) && isAddressedToAgent(latest.recipient, aliases)),
	};
}

function validateConfig(config, configFile) {
	if (config.version !== VERSION) fail(`unsupported config version in ${configFile}`);
	for (const key of ["agent", "repoRoot", "indexRelative", "stateDir", "taskName", "sessionId", "codexJs", "nodeExe"]) {
		if (typeof config[key] !== "string" || config[key].length === 0) fail(`invalid config field '${key}'`);
	}
	if (!Array.isArray(config.aliases) || config.aliases.length === 0) fail("aliases must be a non-empty array");
	if (!/^[0-9a-fA-F-]{36}$/.test(config.sessionId)) fail("pinned Codex session ID has an invalid format");
	return config;
}

function loadConfig(file) {
	return validateConfig(readJson(path.resolve(file), "config"), path.resolve(file));
}

// ---- boot-session arm guard ---------------------------------------------------------------------

/** Estimated boot instant: wall clock minus uptime. Both terms come from the SAME clock at the same
 * moment, so an absolute clock reset shifts them together — the value identifies a boot session
 * without trusting wall time across restarts. Second-resolution jitter is absorbed by ARM_TOLERANCE. */
function bootInstantMs() {
	return Date.now() - os.uptime() * 1000;
}

const ARM_TOLERANCE_MS = 3 * 60 * 1000;

function armFile(repoRoot) {
	return path.join(repoRoot, "team-room", "state", "armed.json");
}

/** Armed iff the stamp exists, parses, and was written in the CURRENT boot session. Any failure mode
 * (missing, corrupt, other-boot) is dormancy — the room must fail CLOSED after a shutdown. */
function armState(repoRoot) {
	const file = armFile(repoRoot);
	let stamp;
	try {
		stamp = JSON.parse(fs.readFileSync(file, "utf8"));
	} catch (error) {
		return { armed: false, reason: error.code === "ENOENT" ? "never-armed-this-boot" : "unreadable-arm-stamp", file };
	}
	if (typeof stamp.bootInstantMs !== "number") return { armed: false, reason: "malformed-arm-stamp", file };
	const drift = Math.abs(bootInstantMs() - stamp.bootInstantMs);
	if (drift > ARM_TOLERANCE_MS) {
		return { armed: false, reason: "armed-in-previous-boot", file, armedAt: stamp.armedAt, driftMs: Math.round(drift) };
	}
	return { armed: true, file, armedAt: stamp.armedAt, armedBy: stamp.armedBy };
}

function writeArmStamp(repoRoot, armedBy) {
	const file = armFile(repoRoot);
	atomicJson(file, {
		version: VERSION,
		armedAt: new Date().toISOString(),
		bootInstantMs: bootInstantMs(),
		armedBy: armedBy || "reinit",
	});
	return armState(repoRoot);
}

function clearArmStamp(repoRoot) {
	fs.rmSync(armFile(repoRoot), { force: true });
}

function stateFile(config) {
	return path.join(config.stateDir, "state.json");
}

function readState(config) {
	const file = stateFile(config);
	if (!fs.existsSync(file)) return { version: VERSION };
	return readJson(file, "state");
}

function writeState(config, state) {
	atomicJson(stateFile(config), { version: VERSION, ...state, updatedAt: new Date().toISOString() });
}

function lockFile(config) {
	return path.join(config.stateDir, "codex-wake.lock");
}

function acquireLock(config) {
	const file = lockFile(config);
	fs.mkdirSync(config.stateDir, { recursive: true });
	try {
		const fd = fs.openSync(file, "wx", 0o600);
		fs.writeFileSync(fd, `${JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() })}\n`, "utf8");
		fs.closeSync(fd);
		return true;
	} catch (error) {
		if (error.code !== "EEXIST") throw error;
		let age = 0;
		try {
			age = Date.now() - fs.statSync(file).mtimeMs;
		} catch {
			return false;
		}
		if (age <= MAX_RUNTIME_MS) return false;
		fs.rmSync(file, { force: true });
		return acquireLock(config);
	}
}

function releaseLock(config) {
	fs.rmSync(lockFile(config), { force: true });
}

function appendRuntimeLog(config, event) {
	fs.mkdirSync(config.stateDir, { recursive: true });
	const clean = { at: new Date().toISOString(), ...event };
	delete clean.sessionId;
	fs.appendFileSync(path.join(config.stateDir, "activity.jsonl"), `${JSON.stringify(clean)}\n`, "utf8");
}

function wakePrompt(config, observation, triggerId) {
	const relativeLog = path.relative(config.repoRoot, observation.log).replaceAll("\\", "/");
	return `[TEAMCHAT_WAKE]\nThis is an automated local team-chat heartbeat, not a direct message from Munya or another agent. Trigger ${triggerId}. You are ${config.agent}. First read and obey AGENTS.md, then teams-chat/content.md and its current linked log. The zero-token precheck observed the newest header '${observation.latest.sender} → ${observation.latest.recipient}' in '${relativeLog}', signature ${observation.signature}. If this session is already actively executing an assigned task, do not interrupt, restart or duplicate it; return ignored-active. Otherwise act only on the newest unresolved update addressed to ${config.agent}, using the repository team-chat protocol and appending the durable response to the correct current dated log. The appended heading MUST use the protocol's exact Unicode separators: '# YYYY-MM-DD HH:MM BST — Codex → Claude' — a SINGLE '#' (owner directive 2026-07-30, so each conversation start is easy to trace), with the exact Unicode em dash and right arrow; plain '-' or '->' is invalid and must not be used. Do not use Agent Room, poll, start unrelated work or treat machine status as a human instruction. Finish by printing exactly one of these markers as the final line:\n[TEAMCHAT_WAKE_ACK] ${triggerId} ${config.agent} acted\n[TEAMCHAT_WAKE_ACK] ${triggerId} ${config.agent} checked-no-update\n[TEAMCHAT_WAKE_ACK] ${triggerId} ${config.agent} ignored-active\n[TEAMCHAT_WAKE_ACK] ${triggerId} ${config.agent} failed`;
}

function resumeCodex(config, observation) {
	const triggerId = crypto.randomUUID();
	const outputFile = path.join(config.stateDir, `last-message-${triggerId}.txt`);
	const prompt = wakePrompt(config, observation, triggerId);
	const result = spawnSync(
		config.nodeExe,
		[config.codexJs, "exec", "resume", "-o", outputFile, config.sessionId, "-"],
		{
			cwd: config.repoRoot,
			encoding: "utf8",
			input: prompt,
			timeout: MAX_RUNTIME_MS,
			windowsHide: true,
			maxBuffer: 10 * 1024 * 1024,
		},
	);
	let finalMessage = "";
	try {
		finalMessage = fs.readFileSync(outputFile, "utf8");
	} catch {
		// The exit status and missing ACK below are sufficient diagnostics.
	}
	fs.rmSync(outputFile, { force: true });
	const ack = finalMessage.match(new RegExp(`\\[TEAMCHAT_WAKE_ACK\\] ${escapeRegExp(triggerId)} ${escapeRegExp(config.agent)} (acted|checked-no-update|ignored-active|failed)\\s*$`));
	const diagnostic = String(result.stderr || result.stdout || result.error?.message || "no diagnostic output")
		.replaceAll(config.sessionId, "<pinned-session>")
		.slice(-4000);
	return {
		triggerId,
		exitCode: result.status,
		signal: result.signal || null,
		outcome: ack ? ack[1] : "failed",
		timedOut: Boolean(result.error && result.error.code === "ETIMEDOUT"),
		diagnostic,
	};
}

function completedWake(result, durableReply) {
	return result.exitCode === 0 && (durableReply || result.outcome === "checked-no-update");
}

function runOnce(config, dryRun = false) {
	// The boot-session guard comes FIRST: an unarmed room is dormant — it observes nothing, consumes
	// no signature, writes no state and spawns no agent. Reinit re-arms it for this boot only.
	const arm = armState(config.repoRoot);
	if (!arm.armed) return { status: "dormant-unarmed", arm, observation: null };
	const observation = inspect(config);
	const state = readState(config);
	if (!observation.actionable) {
		writeState(config, { ...state, lastSeenSignature: observation.signature, lastCheck: "no-update" });
		return { status: "no-update", observation };
	}
	if (state.lastCompletedSignature === observation.signature) return { status: "already-consumed", observation };
	if (dryRun) return { status: "would-wake", observation };
	if (!acquireLock(config)) return { status: "ignored-active", observation };
	try {
		const afterLock = inspect(config);
		if (!afterLock.actionable || afterLock.signature !== observation.signature) {
			writeState(config, { ...state, lastSeenSignature: afterLock.signature, lastCheck: "changed-before-wake" });
			return { status: "changed-before-wake", observation: afterLock };
		}
		const result = resumeCodex(config, afterLock);
		const afterResume = inspect(config);
		const aliases = normalizedAliases(config);
		const durableReply = Boolean(
			result.outcome === "acted" &&
			afterResume.latest &&
			afterResume.signature !== afterLock.signature &&
			isFromAgent(afterResume.latest.sender, aliases),
		);
		// A successful checked-no-update is the agent's explicit resolution of this exact
		// signature. Requiring the heading to become non-actionable caused informational
		// acknowledgements to wake the same Codex thread every 15 minutes forever.
		const completed = completedWake(result, durableReply);
		if (result.outcome === "acted" && !durableReply) {
			result.outcome = "failed";
			result.diagnostic = "Agent acknowledged acted, but no newer canonical Codex team-chat header was found.";
		}
		writeState(config, {
			...state,
			lastSeenSignature: afterResume.signature,
			lastAttemptSignature: afterLock.signature,
			lastCompletedSignature: completed ? afterLock.signature : state.lastCompletedSignature,
			lastOutcome: result.outcome,
			lastExitCode: result.exitCode,
			lastTriggerId: result.triggerId,
			lastDiagnostic: result.outcome === "failed" ? result.diagnostic : undefined,
		});
		appendRuntimeLog(config, {
			event: "wake",
			signature: afterLock.signature,
			outcome: result.outcome,
			exitCode: result.exitCode,
			signal: result.signal,
			timedOut: result.timedOut,
			diagnostic: result.outcome === "failed" ? result.diagnostic : undefined,
		});
		return { status: result.outcome, observation: afterLock, result };
	} finally {
		releaseLock(config);
	}
}

function findCodexJs() {
	const appData = process.env.APPDATA;
	if (!appData) fail("APPDATA is missing; pass --codex-js explicitly");
	const candidate = path.join(appData, "npm", "node_modules", "@openai", "codex", "bin", "codex.js");
	if (!fs.existsSync(candidate)) fail(`Codex CLI entrypoint not found at ${candidate}`);
	return candidate;
}

function defaultStateRoot(repoRoot) {
	const slug = path.basename(repoRoot).replace(/[^a-zA-Z0-9._-]+/g, "-") || "project";
	const suffix = sha(repoRoot).slice(0, 8);
	const dRoot = process.platform === "win32" && fs.existsSync("D:\\") ? "D:\\CodexData" : path.join(os.homedir(), ".codex");
	return path.join(dRoot, "teamchat-heartbeat", `${slug}-${suffix}`);
}

function powershell(script, env = {}) {
	const result = spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
		encoding: "utf8",
		env: { ...process.env, ...env },
		windowsHide: true,
	});
	if (result.status !== 0) fail((result.stderr || result.stdout || "PowerShell command failed").trim());
	return result.stdout.trim();
}

function installTask(config, scriptFile) {
	if (process.platform !== "win32") fail("automatic installation currently supports Windows only");
	const ps = [
		"$ErrorActionPreference='Stop'",
		"$minutes=[int]$env:TC_INTERVAL",
		"$now=Get-Date",
		"$next=$now.AddMinutes($minutes-($now.Minute % $minutes)).AddSeconds(-$now.Second).AddMilliseconds(-$now.Millisecond)",
		"if($next -le $now){$next=$next.AddMinutes($minutes)}",
		"$trigger=New-ScheduledTaskTrigger -Once -At $next -RepetitionInterval (New-TimeSpan -Minutes $minutes) -RepetitionDuration (New-TimeSpan -Days 3650)",
		"$argument='\"'+$env:TC_SCRIPT+'\" run --config \"'+$env:TC_CONFIG+'\"'",
		"$action=New-ScheduledTaskAction -Execute $env:TC_NODE -Argument $argument -WorkingDirectory $env:TC_REPO",
		"$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)",
		"Register-ScheduledTask -TaskName $env:TC_TASK -Action $action -Trigger $trigger -Settings $settings -Description 'Zero-token team-chat precheck; resumes pinned Codex only for addressed updates.' -Force | Out-Null",
		"$info=Get-ScheduledTaskInfo -TaskName $env:TC_TASK",
		"[pscustomobject]@{NextRunTime=$info.NextRunTime;LastTaskResult=$info.LastTaskResult}|ConvertTo-Json -Compress",
	].join(";");
	return powershell(ps, {
		TC_INTERVAL: String(config.intervalMinutes),
		TC_SCRIPT: scriptFile,
		TC_CONFIG: config.configFile,
		TC_NODE: config.nodeExe,
		TC_REPO: config.repoRoot,
		TC_TASK: config.taskName,
	});
}

function taskStatus(taskName) {
	if (process.platform !== "win32") return { installed: false, reason: "non-Windows" };
	const ps = "$ErrorActionPreference='Stop';$task=Get-ScheduledTask -TaskName $env:TC_TASK;$info=Get-ScheduledTaskInfo -TaskName $env:TC_TASK;[pscustomobject]@{TaskName=$task.TaskName;State=[string]$task.State;NextRunTime=$info.NextRunTime;LastRunTime=$info.LastRunTime;LastTaskResult=$info.LastTaskResult}|ConvertTo-Json -Compress";
	try {
		return { installed: true, ...JSON.parse(powershell(ps, { TC_TASK: taskName })) };
	} catch (error) {
		return { installed: false, reason: error.message };
	}
}

function install(options, scriptFile) {
	const repoRoot = path.resolve(options.repo || process.cwd());
	const sessionId = process.env.CODEX_THREAD_ID;
	if (!sessionId || !/^[0-9a-fA-F-]{36}$/.test(sessionId)) fail("CODEX_THREAD_ID is unavailable; install must run from the Codex session being pinned");
	const intervalMinutes = asPositiveInt(options.interval, DEFAULT_INTERVAL_MINUTES, "interval");
	if (60 % intervalMinutes !== 0) fail("interval must divide 60 so ticks remain wall-clock aligned");
	const stateDir = path.resolve(options["state-root"] || defaultStateRoot(repoRoot));
	const configFile = path.join(stateDir, "config.json");
	const config = {
		version: VERSION,
		agent: DEFAULT_AGENT,
		aliases: [DEFAULT_AGENT],
		repoRoot,
		indexRelative: options.index || path.join("teams-chat", "content.md"),
		stateDir,
		taskName: options.task || `TeamChat-Codex-${path.basename(repoRoot).replace(/[^a-zA-Z0-9_-]+/g, "-")}`,
		intervalMinutes,
		sessionId,
		codexJs: path.resolve(options["codex-js"] || findCodexJs()),
		nodeExe: process.execPath,
		installedAt: new Date().toISOString(),
		configFile,
	};
	validateConfig(config, configFile);
	const initial = inspect(config);
	atomicJson(configFile, config);
	writeState(config, { lastSeenSignature: initial.signature, lastCheck: "installed-baseline" });
	const installed = installTask(config, scriptFile);
	return { config, initial, installed };
}

function uninstall(config) {
	if (process.platform !== "win32") return;
	powershell("Unregister-ScheduledTask -TaskName $env:TC_TASK -Confirm:$false -ErrorAction SilentlyContinue", { TC_TASK: config.taskName });
}

function selfTest() {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "teamchat-wake-"));
	try {
		const chat = path.join(root, "teams-chat");
		const dailyDir = path.join(chat, "main-project", "2026", "July", "wk-4");
		fs.mkdirSync(dailyDir, { recursive: true });
		const daily = path.join(dailyDir, "21 July.md");
		fs.writeFileSync(path.join(chat, "content.md"), "## Current log\n\n- [21 July](main-project/2026/July/wk-4/21%20July.md)\n", "utf8");
		fs.writeFileSync(daily, "## 2026-07-21 — Codex → Claude\n\nWait.\n", "utf8");
		const config = { repoRoot: root, indexRelative: "teams-chat/content.md", aliases: ["Codex"] };
		if (inspect(config).actionable) fail("self-test: own message must not wake Codex");
		fs.appendFileSync(daily, "\n## 2026-07-21 — Claude → Codex\n\nUpdate.\n", "utf8");
		if (!inspect(config).actionable) fail("self-test: Claude → Codex must wake Codex");
		fs.appendFileSync(daily, "\n## 2026-07-21 — Claude → Fable\n\nNot for Codex.\n", "utf8");
		if (inspect(config).actionable) fail("self-test: message to Fable must not wake Codex");
		if (!completedWake({ outcome: "checked-no-update", exitCode: 0 }, false)) {
			fail("self-test: checked-no-update must consume the exact observed signature");
		}
		if (completedWake({ outcome: "ignored-active", exitCode: 0 }, false)) {
			fail("self-test: ignored-active must remain eligible for a later wake");
		}
		if (!completedWake({ outcome: "acted", exitCode: 0 }, true)) {
			fail("self-test: acted with a durable reply must consume the signature");
		}
		if (completedWake({ outcome: "acted", exitCode: 0 }, false)) {
			fail("self-test: acted without a durable reply must not consume the signature");
		}
		// Boot-session arm guard: never armed → dormant; armed NOW → live; stamped in another boot →
		// dormant again. The room must not survive a reboot on its own.
		fs.mkdirSync(path.join(root, "team-room"), { recursive: true });
		if (armState(root).armed) fail("self-test: an unarmed repo must be dormant");
		writeArmStamp(root, "self-test");
		if (!armState(root).armed) fail("self-test: arming in the current boot must be live");
		const staleBoot = { version: VERSION, armedAt: new Date().toISOString(), bootInstantMs: bootInstantMs() - 6 * 60 * 60 * 1000, armedBy: "self-test" };
		fs.writeFileSync(armFile(root), `${JSON.stringify(staleBoot)}\n`, "utf8");
		if (armState(root).armed) fail("self-test: a stamp from a previous boot session must be dormant");
		if (armState(root).reason !== "armed-in-previous-boot") fail("self-test: the previous-boot reason must be named");
		fs.writeFileSync(armFile(root), "not json\n", "utf8");
		if (armState(root).armed) fail("self-test: a corrupt stamp must fail CLOSED to dormant");
		clearArmStamp(root);
		if (armState(root).reason !== "never-armed-this-boot") fail("self-test: disarm must return the room to never-armed");
		console.log("SELF-TEST PASSED");
	} finally {
		fs.rmSync(root, { recursive: true, force: true });
	}
}

function safeSummary(observation) {
	if (!observation) return { log: null, latest: "none", actionable: false, signature: null };
	return {
		log: observation.log,
		latest: observation.latest ? `${observation.latest.sender} → ${observation.latest.recipient}` : "none",
		actionable: observation.actionable,
		signature: observation.signature.slice(0, 12),
	};
}

/** Resolve the repo root for arm/disarm: --repo, else cwd. Refuses a directory that carries no
 * team-room tooling — stamping an unrelated folder would arm nothing and mislead the operator. */
function armRepoRoot(options) {
	const repoRoot = path.resolve(options.repo || process.cwd());
	if (!fs.existsSync(path.join(repoRoot, "team-room"))) {
		fail(`no team-room/ directory under ${repoRoot} — run from the project root or pass --repo`);
	}
	return repoRoot;
}

function main() {
	const options = argsOf(process.argv.slice(2));
	const command = options._[0];
	const scriptFile = path.resolve(__filename);
	if (command === "self-test") return selfTest();
	if (command === "install") {
		const result = install(options, scriptFile);
		console.log(JSON.stringify({
			installed: true,
			taskName: result.config.taskName,
			intervalMinutes: result.config.intervalMinutes,
			configFile: result.config.configFile,
			initial: safeSummary(result.initial),
			task: JSON.parse(result.installed),
		}, null, 2));
		return;
	}
	if (command === "arm") {
		const repoRoot = armRepoRoot(options);
		const armed = writeArmStamp(repoRoot, options.by || "reinit");
		console.log(JSON.stringify({ command: "arm", repoRoot, ...armed }, null, 2));
		return;
	}
	if (command === "disarm") {
		const repoRoot = armRepoRoot(options);
		clearArmStamp(repoRoot);
		console.log(JSON.stringify({ command: "disarm", repoRoot, ...armState(repoRoot) }, null, 2));
		return;
	}
	if (!options.config) fail(`${command || "command"} requires --config <private-config.json>`);
	const config = loadConfig(options.config);
	if (command === "check") {
		const result = runOnce(config, true);
		console.log(JSON.stringify({ status: result.status, arm: armState(config.repoRoot), ...safeSummary(result.observation) }, null, 2));
		return;
	}
	if (command === "run") {
		const result = runOnce(config, false);
		console.log(JSON.stringify({ status: result.status, ...safeSummary(result.observation) }));
		return;
	}
	if (command === "status") {
		const check = runOnce(config, true);
		console.log(JSON.stringify({ task: taskStatus(config.taskName), arm: armState(config.repoRoot), check: { status: check.status, ...safeSummary(check.observation) } }, null, 2));
		return;
	}
	if (command === "uninstall") {
		uninstall(config);
		console.log(JSON.stringify({ uninstalled: true, taskName: config.taskName, statePreservedAt: config.stateDir }, null, 2));
		return;
	}
	fail("command must be install, check, run, status, uninstall, or self-test");
}

try {
	main();
} catch (error) {
	console.error(error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
}
