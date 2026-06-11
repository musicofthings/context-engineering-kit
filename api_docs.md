# API Documentation
_Auto-fetched: 2026-06-11T21:17:57Z_
_Source: /Users/theranosis_dx/projects/context-engineering-kit/config/api_sources.json_

---

## ANTHROPIC-CLAUDE-CODE

_Claude Code hooks, skills, slash commands, subagents_

Source: https://docs.anthropic.com/en/docs/claude-code/hooks


```
The table below summarizes when each event fires. The [Hook events](#hook-events) section documents the full input schema and decision control options for each one.

| Event                 | When it fires                                                                                                                                          |
| :-------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SessionStart`        | When a session begins or resumes                                                                                                                       |
| `Setup`               | When you start Claude Code with `--init-only`, or with `--init` or `--maintenance` in `-p` mode. For one-time preparation in CI or scripts             |
| `UserPromptSubmit`    | When you submit a prompt, before Claude processes it                                                                                                   |
| `UserPromptExpansion` | When a user-typed command expands into a prompt, before it reaches Claude. Can block the expansion                                                     |
| `PreToolUse`          | Before a tool call executes. Can block it                                                                                                              |
| `PermissionRequest`   | When a permission dialog appears                                                                                                                       |
| `PermissionDenied`    | When a tool call is denied by the auto mode classifier. Return `{retry: true}` to tell the model it may retry the denied tool call                     |
| `PostToolUse`         | After a tool call succeeds                                                                                                                             |
| `PostToolUseFailure`  | After a tool call fails                                                                                                                                |
| `PostToolBatch`       | After a full batch of parallel tool calls resolves, before the next model call                                                                         |
| `Notification`        | When Claude Code sends a notification                                                                                                                  |
| `MessageDisplay`      | While assistant message text is displayed                                                                                                              |
| `SubagentStart`       | When a subagent is spawned                                                                                                                             |
| `SubagentStop`        | When a subagent finishes                                                                                                                               |
| `TaskCreated`         | When a task is being created via `TaskCreate`                                                                                                          |
| `TaskCompleted`       | When a task is being marked as completed                                                                                                               |
| `Stop`                | When Claude finishes responding                                                                                                                        |
| `StopFailure`         | When the turn ends due to an API error. Output and exit code are ignored                                                                               |
| `TeammateIdle`        | When an [agent team](/en/agent-teams) teammate is about to go idle                                                                                     |
| `InstructionsLoaded`  | When a CLAUDE.md or `.claude/rules/*.md` file is loaded into context. Fires at session start and when files are lazily loaded during a session         |
| `ConfigChange`        | When a configuration file changes during a session                                                                                                     |
| `CwdChanged`          | When the working directory changes, for example when Claude executes a `cd` command. Useful for reactive environment management with tools like direnv |
| `FileChanged`         | When a watched file changes on disk. The `matcher` field specifies which filenames to watch                                                            |
| `WorktreeCreate`      | When a worktree is being created via `--worktree` or `isolation: "worktree"`. Replaces default git behavior                                            |
| `WorktreeRemove`      | When a worktree is being removed, either at session exit or when a subagent finishes                                                                   |
| `PreCompact`          | Before context compaction                                                                                                                              |
| `PostCompact`         | After context compaction completes                                                                                                                     |
| `Elicitation`         | When an MCP server requests user input during a tool call                                                                                              |
| `ElicitationResult`   | After a user responds to an MCP elicitation, before the response is sent back to the server                                                            |
| `SessionEnd`          | When a session terminates                                                                                                                              |

### How a hook resolves

To see how these pieces fit together, consider this `PreToolUse` hook that block
```


---

## ANTHROPIC-API

_Claude API messages, models, pricing_

Source: https://docs.anthropic.com/en/api/getting-started


```
## Rate limits and availability

### Rate limits

The API enforces rate limits and spend limits to prevent misuse and manage capacity. Limits are organized into usage tiers that increase automatically as you use the API. Each tier has:

- **Spend limits**: Maximum monthly cost for API usage
- **Rate limits**: Maximum number of requests per minute (RPM) and tokens per minute (TPM)

You can view your organization's current limits in the [Console](/settings/limits). For higher limits or Priority Tier (enhanced service levels with committed spend), contact sales through the Console.

For detailed information about limits, tiers, and the token bucket algorithm used for rate limiting, see [Rate limits](/docs/en/api/rate-limits).

### Availability

The Claude API is available in [many countries and regions](/docs/en/api/supported-regions) worldwide. Check the supported regions page to confirm availability in your location.

## Next steps

<CardGroup cols={2}>
  <Card title="Messages API reference" icon="book" href="/docs/en/api/messages/create">
    Complete API specification for direct model interactions
  </Card>
  <Card title="Claude Managed Agents reference" icon="brain" href="/docs/en/managed-agents/sessions">
    Agents, Sessions, and Environments endpoints
  </Card>
  <Card title="Client SDKs" icon="code" href="/docs/en/cli-sdks-libraries/overview">
    Python, TypeScript, C#, Go, Java, PHP, and Ruby
  </Card>
  <Card title="Rate limits" icon="gauge" href="/docs/en/api/rate-limits">
    Usage tiers, spend limits, and token bucket algorithm
  </Card>
</CardGroup>
```


---

## CLOUDFLARE-WORKERS

_Cloudflare Workers API for edge deployment_

Source: https://developers.cloudflare.com/workers/


```
# Cloudflare Workers

A serverless platform for building, deploying, and scaling apps across[Cloudflare's global network ↗](https://www.cloudflare.com/network/) with a single command — no infrastructure to manage, no complex configuration

With Cloudflare Workers, you can expect to:

* Deliver fast performance with high reliability anywhere in the world
* Build full-stack apps with your framework of choice, including [React](https://developers.cloudflare.com/workers/framework-guides/web-apps/react/), [Vue](https://developers.cloudflare.com/workers/framework-guides/web-apps/vue/), [Svelte](https://developers.cloudflare.com/workers/framework-guides/web-apps/sveltekit/), [Next](https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/), [Astro](https://developers.cloudflare.com/workers/framework-guides/web-apps/astro/), [React Router](https://developers.cloudflare.com/workers/framework-guides/web-apps/react-router/), [and more](https://developers.cloudflare.com/workers/framework-guides/)
* Use your preferred language, including [JavaScript](https://developers.cloudflare.com/workers/languages/javascript/), [TypeScript](https://developers.cloudflare.com/workers/languages/typescript/), [Python](https://developers.cloudflare.com/workers/languages/python/), [Rust](https://developers.cloudflare.com/workers/languages/rust/), [and more](https://developers.cloudflare.com/workers/runtime-apis/webassembly/)
* Gain deep visibility and insight with built-in [observability](https://developers.cloudflare.com/workers/observability/logs/)
* Get started for free and grow with flexible [pricing](https://developers.cloudflare.com/workers/platform/pricing/), affordable at any scale

Get started with your first project:

[ Deploy a template ](https://dash.cloudflare.com/?to=/:account/workers-and-pages/templates) [ Deploy with Wrangler CLI ](https://developers.cloudflare.com/workers/get-started/guide/) 

---

## Build with Workers

#### Front-end applications

Deploy [static assets](https://developers.cloudflare.com/workers/static-assets/) to Cloudflare's [CDN & cache](https://developers.cloudflare.com/cache/) for fast rendering

#### Back-end applications

Build APIs and connect to data stores with [Smart Placement](https://developers.cloudflare.com/workers/configuration/placement/) to optimize latency

#### Serverless AI inference

Run LLMs, generate images, and more with [Workers AI](https://developers.cloudflare.com/workers-ai/)

#### Background jobs

Schedule [cron jobs](https://developers.cloudflare.com/workers/configuration/cron-triggers/), run durable [Workflows](https://developers.cloudflare.com/workflows/), and integrate with [Queues](https://developers.cloudflare.com/queues/)

#### Observability & monitoring

Monitor performance, debug issues, and analyze traffic with [real-time logs](https://developers.cloudflare.com/workers/observability/logs/) and [analytics](https://developers.cloudflare.com/workers/observability/metrics-and-analytics/)

---

## Integrate with Workers

Connect to external services like databases, APIs, and storage via [Bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/), enabling functionality with just a few lines of code:

**Storage**

**[Durable Objects](https://developers.cloudflare.com/durable-objects/)** 

Scalable stateful storage for real-time coordination.

**[D1](https://developers.cloudflare.com/d1/)** 

Serverless SQL database built for fast, global queries.

**[KV](https://developers.cloudflare.com/kv/)** 

Low-latency key-value storage for fast, edge-cached reads.

**[Queues](https://developers.cloudflare.com/queues/)** 

Guaranteed delivery with no charges for egress bandwidth.

**[Hyperdrive](https://developers.cloudflare.com/hyperdrive/)** 

Connect to your external database with accelerated queries, cached at the edge.

**Compute**

**[Workers AI](https://developers.cloudflare.com/workers-ai/)** 

Machine learning models powered by serverless GPUs.

**[Workflows](https://developers.cloudflare.com/workflows/)** 

Durable, long-running operations with automatic retries.

**[Vectorize](https://developers.cloudflare.com/vectorize/)** 

Vector database for AI-powered semantic search.

**[R2](https://developers.cloudflare.com/r2/)** 

Zero-egress object storage for cost-efficient data access.

**[Browser Run](https://developers.cloudflare.com/browser-run/)** 

Programmatic serverless browser instances.

**Media**

**[Cache / CDN](https://developers.cloudflare.com/cache/)** 

Global caching for high-performance, low-latency delivery.

**[Images](https://developers.cloudflare.com/images/)** 

Streamlined image infrastructure from a single API.

---

Want to connect with the Workers community? [Join our Discord ↗](https://discord.cloudflare.com)

```json
{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[{"@type":"ListItem","position":1,"item":{"@id":"/directory/","name":"Directory"}},{"@type":"ListItem","position":2,"item":{"@id":"/workers/","name":"Workers"}}]}
```

```


---
