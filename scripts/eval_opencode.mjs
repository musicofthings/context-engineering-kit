/**
 * eval_opencode.mjs — exercises .opencode/plugins/cek.ts without Bun.
 *
 * opencode runs plugins under Bun, and Bun is not a reasonable thing to require
 * of everyone running this repo's evals. So this harness implements the exact
 * Bun-shell subset the plugin uses — tagged template, `< ${Response}` stdin
 * redirection, .env / .cwd / .nothrow / .quiet — and spawns a REAL bash.
 *
 * That means it covers the whole path: opencode event -> TS mapping -> run.sh
 * -> .claude/hooks/*.sh -> state on disk. What it does NOT cover is Bun itself.
 * Two Bun-only APIs (`import.meta.dir`, `Bun.file`) were caught by this harness
 * precisely because it is not Bun; both are now standard APIs that work in
 * both. Treat a green run as "the mapping is right", not "verified on Bun".
 *
 * Run:  node --experimental-strip-types scripts/eval_opencode.mjs
 */
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const KIT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const calls = [];

function makeShell() {
  return (strings, ...exprs) => {
    const argv = [];
    let stdin = null;
    let pending = "";
    for (let i = 0; i < strings.length; i++) {
      pending += strings[i];
      if (i < exprs.length) {
        const e = exprs[i];
        if (pending.trimEnd().endsWith("<")) {
          stdin = e; // the Response body
          pending = "";
          continue;
        }
        for (const t of pending.split(/\s+/).filter(Boolean)) argv.push(t);
        pending = "";
        argv.push(typeof e === "string" ? e : String(e));
      }
    }
    for (const t of pending.split(/\s+/).filter(Boolean)) argv.push(t);

    let env = process.env;
    let cwd = process.cwd();
    const api = {
      env(e) { env = e; return api; },
      cwd(d) { cwd = d; return api; },
      nothrow() { return api; },
      async quiet() {
        const body = stdin ? await stdin.text() : "";
        const [cmd, ...args] = argv;
        const r = spawnSync(cmd, args, { input: body, env, cwd });
        calls.push({ argv, payload: body ? JSON.parse(body) : null, exitCode: r.status ?? 0 });
        return {
          exitCode: r.status ?? 0,
          stdout: r.stdout ?? Buffer.alloc(0),
          stderr: r.stderr ?? Buffer.alloc(0),
        };
      },
    };
    return api;
  };
}

function sandbox() {
  const d = mkdtempSync(join(tmpdir(), "cek-oc-"));
  spawnSync("git", ["-C", d, "init", "-q"]);
  spawnSync("git", ["-C", d, "config", "user.email", "e@t"]);
  spawnSync("git", ["-C", d, "config", "user.name", "e"]);
  writeFileSync(join(d, "CLAUDE.md"), "# s\n");
  spawnSync("git", ["-C", d, "add", "-A"]);
  spawnSync("git", ["-C", d, "commit", "-qm", "i"]);
  return d;
}

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m, d) => { console.log(`  FAIL  ${m} — ${d}`); fail++; };

const { ContextEngineeringKit } = await import(join(KIT, ".opencode/plugins/cek.ts"));

const SB = sandbox();
const plugin = await ContextEngineeringKit({ $: makeShell(), directory: SB, worktree: SB });

// 1. kit root resolution
if (Object.keys(plugin).length > 0) ok("plugin resolved the kit root and registered hooks");
else bad("plugin registered no hooks", "kit root not found");

const last = () => calls[calls.length - 1];

// 2. session.created -> session-start chain
calls.length = 0;
await plugin.event({ event: { type: "session.created", properties: { sessionID: "oc-1" } } });
last()?.argv.includes("session-start")
  ? ok("session.created -> session-start")
  : bad("session.created", JSON.stringify(last()?.argv));
existsSync(join(SB, ".claude/session/state.json"))
  ? ok("state.json created through the real core")
  : bad("state.json", "missing");

// 3. session id is captured and forwarded
calls.length = 0;
await plugin.event({ event: { type: "session.idle", properties: { sessionID: "oc-1" } } });
last()?.payload?.session_id === "oc-1"
  ? ok("session id captured and sent as snake_case session_id")
  : bad("session_id", JSON.stringify(last()?.payload));
last()?.argv.includes("stop") ? ok("session.idle -> stop chain") : bad("session.idle", JSON.stringify(last()?.argv));

// 4. tool.execute.before blocks by THROWING on exit 2
calls.length = 0;
let threw = null;
try {
  await plugin["tool.execute.before"]({ tool: "bash" }, { args: { command: "rm -rf /" } });
} catch (e) { threw = e; }
threw ? ok("dangerous command throws (opencode's block contract)") : bad("dangerous command", "did not throw");
threw && /BLOCKED/.test(threw.message)
  ? ok("thrown message carries the guard's reason")
  : bad("throw reason", threw ? threw.message : "n/a");

// 5. safe command does not throw
threw = null;
try {
  await plugin["tool.execute.before"]({ tool: "bash" }, { args: { command: "ls -la" } });
} catch (e) { threw = e; }
threw ? bad("safe command", `threw: ${threw.message}`) : ok("safe command does not throw");

// 6. tool name translation bash -> Bash (the guard matches on Claude names)
calls.length = 0;
await plugin["tool.execute.before"]({ tool: "bash" }, { args: { command: "echo hi" } });
last()?.payload?.tool_name === "Bash"
  ? ok("opencode 'bash' translated to Claude 'Bash'")
  : bad("tool_name translation", JSON.stringify(last()?.payload?.tool_name));

// 7. file.edited -> track-changes
calls.length = 0;
await plugin.event({ event: { type: "file.edited", properties: { file: join(SB, "src/x.ts") } } });
const changed = JSON.parse(readFileSync(join(SB, ".claude/session/state.json"), "utf8")).changed_files || [];
changed.includes("src/x.ts") ? ok("file.edited recorded in changed_files") : bad("file.edited", JSON.stringify(changed));

// 8. compaction injects the handover into output.context
calls.length = 0;
const out = { context: [] };
await plugin["experimental.session.compacting"]({}, out);
existsSync(join(SB, "session_handover.md"))
  ? ok("compaction wrote session_handover.md first")
  : bad("pre-compact", "no handover written");
out.context.length === 1 && /Session handover/.test(out.context[0])
  ? ok("handover pushed into the compaction prompt")
  : bad("compaction inject", JSON.stringify(out.context).slice(0, 120));
out.prompt === undefined
  ? ok("output.prompt left alone (does not hijack compaction)")
  : bad("output.prompt", "was overwritten");

// 9. session.error -> stop-failure with the real field names
calls.length = 0;
await plugin.event({
  event: { type: "session.error", properties: { sessionID: "oc-1", error: { name: "rate_limit", message: "429" } } },
});
last()?.payload?.error === "rate_limit" && last()?.payload?.error_details === "429"
  ? ok("session.error -> StopFailure error/error_details")
  : bad("session.error", JSON.stringify(last()?.payload));

// 10. unknown events are ignored rather than dispatched
calls.length = 0;
await plugin.event({ event: { type: "message.part.updated", properties: {} } });
calls.length === 0 ? ok("unhandled event dispatches nothing") : bad("unhandled event", JSON.stringify(last()?.argv));

rmSync(SB, { recursive: true, force: true });
console.log(`\nResults: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
