/**
 * context-engineering-kit — opencode plugin
 *
 * A translator, not a second implementation. Every opencode event is
 * serialised into the Claude-shaped snake_case JSON the shared core under
 * .claude/hooks/ already reads, then handed to .opencode/hooks/run.sh — the
 * same dispatch pattern the Codex and Grok adapters use. No policy lives here.
 *
 * Why this file is TypeScript when every other adapter is shell: opencode's
 * extension surface is a JS/TS module, not a JSON hook file. Keeping a second
 * logic core in TypeScript was the alternative and is how this kit ended up
 * with duplicated .claude/skills once already.
 *
 * Install:
 *   local — this file at <project>/.opencode/plugins/cek.ts
 *   npm   — "plugin": ["opencode-context-engineering-kit"] in opencode.json
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

type ShellResult = { exitCode: number; stdout: Buffer; stderr: Buffer };

// Structural, not exhaustive. The precise types ship in @opencode-ai/plugin;
// declaring them by hand here would be a second place to get them wrong, and
// this file is a translator with no policy worth type-proving.
type Shell = (strings: TemplateStringsArray, ...expr: unknown[]) => any;

interface PluginContext {
  project?: unknown;
  client?: unknown;
  $: Shell;
  directory: string;
  worktree?: string;
}

/**
 * Locate the kit root — the directory holding scripts/ and .claude/hooks/.
 *
 * Two install shapes to satisfy. Locally the plugin sits at
 * <root>/.opencode/plugins/cek.ts, so the root is two levels up. Installed from
 * npm it sits under ~/.cache/opencode/node_modules/, where walking up finds the
 * package root instead, and the project directory is the right answer.
 */
function resolveKitRoot(directory: string): string | null {
  const candidates: string[] = [];

  // `import.meta.url` rather than Bun's `import.meta.dir`: the former is
  // standard and works under Bun as well, the latter is undefined everywhere
  // else. opencode runs plugins under Bun today, but a plugin whose self-
  // location silently returns null off Bun is a plugin that silently stops
  // preserving context the moment that changes.
  let here: string | null = null;
  try {
    if (typeof import.meta?.url === "string") {
      here = dirname(fileURLToPath(import.meta.url));
    }
  } catch {
    here = null;
  }
  if (!here && typeof (import.meta as any)?.dir === "string") {
    here = (import.meta as any).dir;
  }
  if (here) {
    candidates.push(resolve(here, "..", ".."));
    candidates.push(resolve(here, ".."));
  }
  if (process.env.CEK_ROOT) candidates.push(process.env.CEK_ROOT);
  if (process.env.CLAUDE_PLUGIN_ROOT) candidates.push(process.env.CLAUDE_PLUGIN_ROOT);
  candidates.push(directory);

  for (const c of candidates) {
    if (c && existsSync(join(c, ".opencode", "hooks", "run.sh"))) return c;
  }
  return null;
}

export const ContextEngineeringKit = async (ctx: PluginContext) => {
  const { $, directory } = ctx;
  const worktree = ctx.worktree || directory;
  const kitRoot = resolveKitRoot(directory);

  if (!kitRoot) {
    // Say so once, loudly, rather than failing silently on every event. A
    // context-preservation kit that quietly does nothing is worse than absent:
    // the user believes their state is being saved.
    console.error(
      "[cek] could not locate the kit root (no .opencode/hooks/run.sh found). " +
        "Set CEK_ROOT to the kit directory. Context preservation is INACTIVE.",
    );
    return {};
  }

  const runner = join(kitRoot, ".opencode", "hooks", "run.sh");

  /**
   * Run an adapter action with `payload` on stdin.
   *
   * Returns the exit code rather than throwing, because exit 2 is a decision in
   * this kit's contract (deny), not a failure. `.nothrow()` is what keeps Bun
   * from turning that decision into an exception before we can read it.
   */
  async function dispatch(
    action: string,
    payload: Record<string, unknown>,
    hookScript?: string,
  ): Promise<ShellResult> {
    const body = new Response(JSON.stringify(payload));
    // Two template forms rather than splicing a pre-joined string through
    // `{ raw }`: Bun escapes interpolated values as single literal arguments,
    // and `raw` opts out of exactly that protection. A hook name is not worth
    // handing to the shell unescaped.
    const cmd = hookScript
      ? $`bash ${runner} ${action} ${hookScript} < ${body}`
      : $`bash ${runner} ${action} < ${body}`;
    return await cmd
      .env({
        ...process.env,
        CEK_RUNTIME: "opencode",
        CEK_ROOT: kitRoot,
        CLAUDE_PROJECT_DIR: worktree,
        CLAUDE_PLUGIN_ROOT: kitRoot,
      })
      .cwd(worktree)
      .nothrow()
      .quiet();
  }

  /** Claude-shaped fields every core hook expects to find. */
  function base(extra: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      session_id: String(currentSessionId ?? ""),
      cwd: worktree,
      transcript_path: "",
      ...extra,
    };
  }

  // opencode's event payloads are not documented field-by-field the way its
  // hook signatures are, so the session id is captured opportunistically from
  // whichever event carries one rather than assumed to be at a fixed path.
  let currentSessionId: string | undefined;

  function rememberSession(event: any): void {
    const id =
      event?.properties?.sessionID ??
      event?.properties?.sessionId ??
      event?.properties?.session?.id ??
      event?.properties?.info?.id ??
      event?.sessionID ??
      event?.sessionId;
    if (typeof id === "string" && id) currentSessionId = id;
  }

  return {
    /**
     * Session, file and permission events all arrive through this one
     * subscriber; only the named hooks below get their own keys.
     */
    event: async ({ event }: { event: any }) => {
      rememberSession(event);
      const type = event?.type;

      switch (type) {
        case "session.created":
          await dispatch("session-start", base({ hook_event_name: "SessionStart", source: "startup" }));
          break;

        case "session.idle":
          // The end of a turn. opencode has no UserPromptSubmit equivalent, so
          // this is also where the usage sentinel runs — see run.sh.
          await dispatch("stop", base({ hook_event_name: "Stop", stop_reason: "end_turn" }));
          break;

        case "session.compacted":
          await dispatch("hook", base({ hook_event_name: "PostCompact" }), "post-compact.sh");
          break;

        case "session.deleted":
          await dispatch("hook", base({ hook_event_name: "SessionEnd", reason: "other" }), "session-end.sh");
          break;

        case "session.error":
          await dispatch(
            "hook",
            base({
              hook_event_name: "StopFailure",
              error: String(event?.properties?.error?.name ?? "unknown"),
              error_details: String(event?.properties?.error?.message ?? ""),
            }),
            "stop-failure.sh",
          );
          break;

        case "file.edited":
          await dispatch(
            "hook",
            base({
              hook_event_name: "PostToolUse",
              tool_name: "Edit",
              tool_input: { file_path: String(event?.properties?.file ?? event?.properties?.path ?? "") },
            }),
            "track-changes.sh",
          );
          break;

        default:
          break;
      }
    },

    /**
     * Pre-tool gate. opencode blocks by throwing, so the core's `exit 2 ==
     * deny` contract is translated here and nowhere else.
     */
    "tool.execute.before": async (input: any, output: any) => {
      const args = output?.args ?? {};
      const result = await dispatch(
        "hook",
        base({
          hook_event_name: "PreToolUse",
          tool_name: input?.tool === "bash" ? "Bash" : String(input?.tool ?? ""),
          tool_input: {
            ...args,
            // The guard reads tool_input.command; opencode's bash tool calls it
            // `command` already, but be explicit rather than lucky.
            command: String(args.command ?? ""),
          },
        }),
        "guard-dangerous.sh",
      );
      if (result.exitCode === 2) {
        const reason = result.stderr.toString().trim() || "Blocked by context-engineering-kit";
        throw new Error(reason);
      }
    },

    "tool.execute.after": async (input: any, output: any) => {
      await dispatch(
        "hook",
        base({
          hook_event_name: "PostToolUse",
          tool_name: String(input?.tool ?? ""),
          tool_input: { file_path: String(output?.args?.filePath ?? output?.args?.file_path ?? "") },
        }),
        "track-changes.sh",
      );
    },

    /**
     * The reason this runtime is worth supporting.
     *
     * No other runtime lets a plugin write into the compaction prompt itself.
     * On Claude Code the kit writes session_handover.md before compaction and
     * hopes the summariser keeps what matters; here the handover is appended to
     * the compaction context directly, so the continuation is built from it.
     *
     * `output.prompt` is deliberately NOT set: assigning it replaces opencode's
     * entire compaction prompt and `output.context` is then ignored. Replacing
     * a runtime's summarisation strategy wholesale is not this kit's business.
     */
    "experimental.session.compacting": async (_input: any, output: any) => {
      await dispatch("hook", base({ hook_event_name: "PreCompact", trigger: "auto" }), "pre-compact.sh");

      const handover = join(worktree, "session_handover.md");
      if (existsSync(handover) && Array.isArray(output?.context)) {
        try {
          // readFileSync from node:fs, not Bun.file: standard APIs work under
          // Bun as well, Bun-only ones work nowhere else. The first draft used
          // Bun.file here and the silent catch below turned that into "the
          // handover is simply never injected" — the failure mode that looks
          // exactly like success.
          const text = readFileSync(handover, "utf8");
          output.context.push(
            [
              "## Session handover (context-engineering-kit)",
              "",
              "State written at compaction time. Carry the active task, the next",
              "action and the architecture decisions into the continuation.",
              "",
              text,
            ].join("\n"),
          );
        } catch (err) {
          // A handover we cannot read is not worth failing compaction over,
          // but it IS worth saying so: silently skipping the injection leaves
          // the user believing their state made it into the continuation.
          console.error(`[cek] could not inject session_handover.md into the compaction prompt: ${err}`);
        }
      }
    },
  };
};

export default ContextEngineeringKit;
