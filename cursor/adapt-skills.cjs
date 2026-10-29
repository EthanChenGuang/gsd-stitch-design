#!/usr/bin/env node
// Build Cursor SKILL.md files from the Claude originals.
// Mechanical substitutions plus inserted Cursor runtime sections.
// Run from pack root: node cursor/adapt-skills.cjs
"use strict";

const fs = require("fs");
const path = require("path");

const PACK = path.resolve(__dirname, "..");
const DEST = process.argv[2] ? path.resolve(process.argv[2]) : PACK;

const ADAPTER = `---
name: {{NAME}}
description: {{DESCRIPTION}}
argument-hint: {{HINT}}
---

<cursor_skill_adapter>
## A. Skill Invocation
- This skill is invoked when the user mentions \`{{NAME}}\` or describes a task matching this skill.
- Treat all user text after the skill mention as arguments (flags and phase number). If none, treat arguments as empty.

## B. User Prompting
When an interactive user can reply (Cursor desktop / a follow-up in this chat):
- Present options as a numbered list in your response text.
- Mark the recommended option with \`（推荐）\` / \`(recommended)\`.
- Ask the user to reply with their choice. For multi-select, ask for comma-separated numbers.

When **no interactive user is available** (headless Cursor cloud agent, background agent, or you cannot wait for a reply), do **not** pick an answer. Follow \`<cursor_gates>\`: stop, commit and push current state, and report the exact question, the options, and the recommended option. Never silently pick a non-recommended path.

## C. Tool Usage
Use these Cursor tools:
- \`Shell\` for commands
- \`StrReplace\` for editing existing files
- \`Read\`, \`Write\`, \`Glob\`, \`Grep\`, \`Task\`, \`WebSearch\`, \`WebFetch\`, \`TodoWrite\` as needed
- Google Stitch MCP: \`GetDynamicTools\` then \`CallDynamicTool\` with namespace \`Google_Stitch\` (see \`<stitch_mcp>\`). Do **not** call Claude-only tools: \`mcp__Google_Stitch__*\`, \`ToolSearch\`, \`AskUserQuestion\`, \`SendUserFile\`, \`Agent\`, \`Skill\`.

## D. Subagent Spawning
When the workflow needs a subagent, use \`Task(subagent_type="generalPurpose", ...)\`. The \`model\` parameter maps to Cursor's model options (e.g. "fast").
</cursor_skill_adapter>
`;

const GATES = `<cursor_gates>
Interactive sessions use a numbered list (adapter §B). Headless / cloud-agent sessions **stop** instead of auto-answering.

**Headless stop protocol** (no interactive user, including GSD \`--auto\` / \`workflow.ui_stitch_auto=true\` when nobody can reply):

1. Write any in-progress artifacts you already have.
2. Commit them (\`commit_docs\` true) and **push** the current branch so the cloud container's work is not lost.
3. Stop. In the final message, report:
   - the exact question
   - every option, verbatim
   - which option is recommended, and why
   - what to reply to continue (e.g. \`1\` or a short instruction)
4. Never silently pick a non-recommended path. Never silently fall back from \`renderer: stitch\` to the html renderer.

| Location | Headless / no user |
|---|---|
| 0 config | Required fields missing: stop. Name the file and the empty fields. Do not invent product facts. |
| Route / global design | DESIGN.md missing or not \`status: locked\`: stop. Recommend \`gsd-ui-stitch-phase --design-only\` (or \`gsd-ui-design-pick\`). |
| G1–G5 | Stop at each gate with the question, options, recommended option. |
| A | If UI-SPEC is missing, follow \`.cursor/skills/gsd-ui-phase/SKILL.md\` with the same phase args. |
| B' | Stop with: "UI-SPEC 改回全局值"（推荐） / "作为新令牌加入全局设计" → G4. Do not apply G4 yourself. |
| C | Stop with: "清单没问题，开始生成"（推荐） / "需要调整" / "先停在这里". |
| E1 renderer | \`renderer\` is \`stitch\` and Stitch MCP is missing or files cannot be fetched: **stop**. Do not switch to html. Offer "connect Stitch and retry"（推荐） / "改用 html 渲染器" / "先停在这里". \`renderer: html\` does not need Stitch. \`auto\` is not the Cursor default; if you see it, stop and recommend setting \`renderer\` to \`stitch\`. |
| E1 sample | Stop after the sample. Do not batch until the user confirms. |
| F | Stop and list the screens; wait for change requests or "都可以了". |
| Other questions | Stop, commit, push, report question + options + recommended. |
</cursor_gates>
`;

const STITCH_MCP = `<stitch_mcp>
Stitch tools come from the Cursor MCP server \`Google_Stitch\` declared in \`.cursor/mcp.json\` (\`https://stitch.googleapis.com/mcp\`, header \`X-Goog-Api-Key: \${env:STITCH_API_KEY}\`). Never read, print, or commit the key.

**Load (once per run):**

1. \`GetDynamicTools\` with \`namespace: "Google_Stitch"\`. If that namespace is missing, try \`pattern: "stitch|Stitch"\`.
2. You need these 14 tools (names are the MCP tool names, not Claude \`mcp__Google_Stitch__*\` prefixes):

   create_project, get_project, list_projects, generate_screen_from_text, get_screen, list_screens, edit_screens, generate_variants, upload_design_md, create_design_system_from_design_md, list_design_systems, apply_design_system, update_design_system, download_file

3. Call them with \`CallDynamicTool\` (\`namespace: "Google_Stitch"\`, \`toolName: "<name>"\`, \`arguments: { ... }\`). If the server uses a different namespace, use that namespace for every call.
4. \`download_file\` returns screen HTML and screenshots (\`htmlCode.name\` / \`screenshot.name\` from \`get_screen\`). If the server has no \`download_file\`, step X may fall back to \`curl\` on \`downloadUrl\`.

**If none of the 14 tools loaded:**

- \`renderer\` is \`stitch\` (Cursor default): G1–G2 review may continue; stop at Stitch sync (G3 step 3) or at E. Tell the user Stitch MCP is not connected: add the \`Google_Stitch\` server to \`.cursor/mcp.json\`, set env \`STITCH_API_KEY\` (cloud agents: https://cursor.com/dashboard?tab=cloud-agents ; key from https://stitch.withgoogle.com/settings ). Do **not** silently switch to html.
- \`renderer\` is \`html\`: Stitch is not required.
- \`renderer\` is \`auto\`: stop and recommend setting \`"renderer": "stitch"\` in design-config.json (or \`html\` if they do not want Stitch).
</stitch_mcp>
`;

const INIT_STITCH = `cd "$(git rev-parse --show-toplevel)"
# GSD: Cursor shim first (.cursor/gsd-core), then Claude copy, then PATH
if [ -x .cursor/bin/gsd-run ]; then GSD="./.cursor/bin/gsd-run"
elif [ -f .cursor/gsd-core/bin/gsd-tools.cjs ]; then GSD="node .cursor/gsd-core/bin/gsd-tools.cjs"
elif [ -f .claude/gsd-core/bin/gsd-tools.cjs ]; then GSD="node .claude/gsd-core/bin/gsd-tools.cjs"
elif [ -f "$HOME/.cursor/gsd-core/bin/gsd-tools.cjs" ]; then GSD="node $HOME/.cursor/gsd-core/bin/gsd-tools.cjs"
elif [ -f "$HOME/.claude/gsd-core/bin/gsd-tools.cjs" ]; then GSD="node $HOME/.claude/gsd-core/bin/gsd-tools.cjs"
elif command -v gsd_run >/dev/null 2>&1; then GSD="gsd_run"
else echo "未找到 GSD：请先安装 GSD Core for Cursor（项目内 .cursor/gsd-core，或用户目录 ~/.cursor/gsd-core）。命令：npx -y @opengsd/gsd-core@latest --cursor --local"; fi

# 本 skill 目录：先项目 .cursor/skills，再 .claude/skills，再用户目录
SKILL_NAME=gsd-ui-stitch-phase
if [ -d ".cursor/skills/$SKILL_NAME" ]; then SKILL_DIR="$PWD/.cursor/skills/$SKILL_NAME"
elif [ -d ".claude/skills/$SKILL_NAME" ]; then SKILL_DIR="$PWD/.claude/skills/$SKILL_NAME"
elif [ -d "$HOME/.cursor/skills/$SKILL_NAME" ]; then SKILL_DIR="$HOME/.cursor/skills/$SKILL_NAME"
elif [ -d "$HOME/.claude/skills/$SKILL_NAME" ]; then SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
else echo "找不到 skill 目录 $SKILL_NAME"; fi

COMMIT_DOCS=$($GSD query config-get commit_docs --raw 2>/dev/null || echo true)
ls .planning/design/DESIGN.md .planning/design/stitch.json .planning/design/design-config.json 2>/dev/null
`;

const INIT_PICK = `cd "$(git rev-parse --show-toplevel)"
# 本 skill 目录：先项目 .cursor/skills，再 .claude/skills，再用户目录
SKILL_NAME=gsd-ui-design-pick
if [ -d ".cursor/skills/$SKILL_NAME" ]; then SKILL_DIR="$PWD/.cursor/skills/$SKILL_NAME"
elif [ -d ".claude/skills/$SKILL_NAME" ]; then SKILL_DIR="$PWD/.claude/skills/$SKILL_NAME"
elif [ -d "$HOME/.cursor/skills/$SKILL_NAME" ]; then SKILL_DIR="$HOME/.cursor/skills/$SKILL_NAME"
elif [ -d "$HOME/.claude/skills/$SKILL_NAME" ]; then SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
else echo "找不到 skill 目录 $SKILL_NAME"; fi
ls .planning/design/DESIGN.md 2>/dev/null && grep -m1 '^status:' .planning/design/DESIGN.md
ls .planning/design/design-config.json 2>/dev/null
`;

function parseFrontMatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!m) throw new Error("no front matter");
  const fm = {};
  for (const line of m[1].split("\n")) {
    const kv = line.match(/^([a-zA-Z0-9_-]+):\s*(.*)$/);
    if (kv) fm[kv[1]] = kv[2].replace(/^"|"$/g, "");
  }
  return { fm, rest: text.slice(m[0].length) };
}

function commonSubs(s) {
  s = s.replace(/用 AskUserQuestion /g, "按 <cursor_gates> ");
  s = s.replace(/用 AskUserQuestion/g, "按 <cursor_gates>");
  s = s.replace(/AskUserQuestion/g, "<cursor_gates>");
  s = s.replace(/用 SendUserFile（display: render）发给用户；SendUserFile 不可用时，打印文件路径，请用户自己打开。/g,
    "把文件路径发给用户（Cursor 里打开即可）。不要使用 SendUserFile。");
  s = s.replace(/用 SendUserFile 发给用户看，再请用户选择。SendUserFile 不可用时，直接告诉用户文件路径，请他自己打开。/g,
    "把文件路径发给用户（Cursor 里打开即可），再请用户选择。不要使用 SendUserFile。");
  s = s.replace(/用 SendUserFile 把 PNG 发给用户（不可用时给出文件路径）/g,
    "把 PNG 路径发给用户");
  s = s.replace(/可以把几张关键截图用 SendUserFile 直接发给用户。/g,
    "在回复里列出关键截图路径（用户可在 Cursor 中打开）。");
  s = s.replace(/不做 SendUserFile 确认/g, "不发送预览文件");
  s = s.replace(/用 Skill 工具调用 `gsd-ui-stitch-phase`/g,
    "接着执行 `.cursor/skills/gsd-ui-stitch-phase/SKILL.md`（如同用户提到了 `gsd-ui-stitch-phase`）");
  s = s.replace(/用 Skill 调用 `gsd-ui-design-pick`/g,
    "接着执行 `.cursor/skills/gsd-ui-design-pick/SKILL.md`（如同用户提到了 `gsd-ui-design-pick`）");
  s = s.replace(/用 Skill 工具调用 `gsd-ui-phase`/g,
    "接着执行 `.cursor/skills/gsd-ui-phase/SKILL.md`（如同用户提到了 `gsd-ui-phase`）");
  s = s.replace(/遵守项目的 CLAUDE\.md/g, "遵守项目的 Cursor rules 与 GSD 规则（`.cursor/rules/`，以及 CLAUDE.md 若存在）");
  s = s.replace(/两个 skill 总是一起安装，文件在 `\.claude\/skills\/gsd-ui-stitch-phase\/SKILL\.md` 或 `\$HOME\/\.claude\/skills\/gsd-ui-stitch-phase\/SKILL\.md`/g,
    "两个 skill 总是一起安装，文件在 `.cursor/skills/gsd-ui-stitch-phase/SKILL.md`（或 `.claude/skills/` / `$HOME` 对应路径）");
  return s;
}

function adaptStitch(src) {
  const { fm, rest } = parseFrontMatter(src);
  fm.description = fm.description.replace(
    "并在唯一的 Stitch 项目、唯一的设计系统下生成该阶段全部界面（Stitch 文件取不回时改用 html 渲染器），把设计稿（HTML + 截图 + 对照表）写回 phase 目录。",
    "并在唯一的 Stitch 项目、唯一的设计系统下生成该阶段全部界面（Cursor 默认 renderer=stitch；Stitch 未连接时停止，不悄悄改用 html），把设计稿（HTML + 截图 + 对照表）写回 phase 目录。"
  );
  let body = rest;

  body = body.replace(
    /^- `--auto`：自动模式，所有提问都取推荐项，见 `<auto_mode>`。GSD 的 plan-phase 流水线以 `\{N\} --auto \[--ws <name>\]` 调用本 skill，`\/gsd-autonomous` 只传裸的 `\{N\}`。$/m,
    "- `--auto`：GSD 流水线传入的自动标志。Cursor 下仍遵守 `<cursor_gates>`：有交互用户就编号提问；没有交互用户就停下来提交并汇报，不要悄悄选推荐项。GSD 的 plan-phase 流水线以 `{N} --auto [--ws <name>]` 调用本 skill，`gsd-autonomous` 只传裸的 `{N}`。"
  );
  body = body.replace(
    /^\*\*自动模式的判定\*\*：带了 `--auto`，或者 `\$GSD query config-get workflow\.ui_stitch_auto --raw` 输出 `true`。命令出错或输出其他内容都按 false 处理。`\/gsd-autonomous` 只传裸的阶段号，所以它下面只有在 `workflow\.ui_stitch_auto` 为 true 时才是自动模式，否则本 skill 保持交互。$/m,
    "**自动 / 无交互用户的判定**：带了 `--auto`，或者 `$GSD query config-get workflow.ui_stitch_auto --raw` 输出 `true`，或者当前是 Cursor 云端 / 后台 agent、无法等待用户回复。命中任一情况都走 `<cursor_gates>` 的 headless 协议（停止、提交、推送、汇报问题），不要自动选取推荐项。"
  );
  body = body.replace(/^<auto_mode>[\s\S]*?^<\/auto_mode>\n/m, GATES + "\n");
  body = body.replace(
    /```bash\ncd "\$\(git rev-parse --show-toplevel\)"\n# GSD 工具[\s\S]*?ls \.planning\/design\/DESIGN\.md \.planning\/design\/stitch\.json \.planning\/design\/design-config\.json 2>\/dev\/null\n```/,
    "```bash\n" + INIT_STITCH + "```"
  );

  body = body.replace(
    /用 ToolSearch 一次性加载 Stitch 工具：\n`select:mcp__Google_Stitch__[^\n]+`\n\n一个都没加载到时，再用一次关键词 ToolSearch（关键词 `generate_screen_from_text`），看有没有 Stitch 服务器以别的前缀注册；找到就改用那个前缀（把上面所有工具名里的 `mcp__Google_Stitch__` 换成它，包括 `download_file`）。`download_file` 是取回界面 HTML 和截图的工具；服务器没有它时，X 步骤才退回 `curl`。\n\n仍然没有 Stitch 工具时：\n\n- `renderer` 为 `stitch`：G1–G2 的审查和讨论照常进行，到同步 Stitch（G3 第 3 步）或 E 步时停止，并告诉用户 Stitch MCP 没有连接（也可以用 `--renderer html` 改用 html 渲染器）。\n- `renderer` 为 `auto`：继续；到 E1 时提供 html 渲染器。\n- `renderer` 为 `html`：不需要 Stitch。\n/,
    "按 `<stitch_mcp>` 加载 Google Stitch MCP 工具（Cursor：`GetDynamicTools` / `CallDynamicTool`，命名空间 `Google_Stitch`）。\n"
  );

  body = body.replace(
    /- 渲染方式 `renderer` 的取值顺序：`--renderer` 参数 → design-config.json → `auto`。/,
    "- 渲染方式 `renderer` 的取值顺序：`--renderer` 参数 → design-config.json → Cursor 安装默认 `stitch`（不是 `auto`）。缺少 Stitch 连接时停止，不要改用 html。"
  );

  body = body.replace(/见 `<auto_mode>`/g, "见 `<cursor_gates>`");
  body = body.replace(/（见 `<auto_mode>`）/g, "（见 `<cursor_gates>`）");
  body = body.replace("自动模式给出警告并正常结束（见 `<cursor_gates>`）", "无交互用户时按 `<cursor_gates>` 停止并汇报");
  body = body.replace(
    /\| `renderer` \| auto \/ stitch \/ html \| auto \| 0 初始化、G3、E、X \|/,
    "| `renderer` | auto / stitch / html | stitch（Cursor 安装默认） | 0 初始化、G3、E、X |"
  );

  body = commonSubs(body);

  const header = ADAPTER
    .replace(/\{\{NAME\}\}/g, fm.name)
    .replace("{{DESCRIPTION}}", fm.description)
    .replace("{{HINT}}", fm["argument-hint"] || "");

  return header + "\n" + STITCH_MCP + "\n" + body;
}

function adaptPick(src) {
  const { fm, rest } = parseFrontMatter(src);
  let body = rest;

  body = body.replace(
    /```bash\ncd "\$\(git rev-parse --show-toplevel\)"\n# 本 skill 目录：先项目内，再用户目录\nSKILL_NAME=gsd-ui-design-pick\nif \[ -d "\.claude\/skills\/\$SKILL_NAME" \]; then SKILL_DIR="\$PWD\/\.claude\/skills\/\$SKILL_NAME"\nelif \[ -d "\$HOME\/\.claude\/skills\/\$SKILL_NAME" \]; then SKILL_DIR="\$HOME\/\.claude\/skills\/\$SKILL_NAME"\nelse echo "找不到 skill 目录 \$SKILL_NAME"; fi\nls \.planning\/design\/DESIGN\.md 2>\/dev\/null && grep -m1 '\^status:' \.planning\/design\/DESIGN\.md\nls \.planning\/design\/design-config\.json 2>\/dev\/null\n```/,
    "```bash\n" + INIT_PICK + "```"
  );

  body = commonSubs(body);

  const header = ADAPTER
    .replace(/\{\{NAME\}\}/g, fm.name)
    .replace("{{DESCRIPTION}}", fm.description)
    .replace("{{HINT}}", fm["argument-hint"] || "");

  return header + "\n" + GATES + "\n" + body;
}

function write(rel, text) {
  const abs = path.join(DEST, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, text);
  console.log("wrote", rel, "(" + text.split("\n").length + " lines)");
}

const stitchSrc = fs.readFileSync(path.join(PACK, "skills/gsd-ui-stitch-phase/SKILL.md"), "utf8");
const pickSrc = fs.readFileSync(path.join(PACK, "skills/gsd-ui-design-pick/SKILL.md"), "utf8");
write("cursor/skills/gsd-ui-stitch-phase/SKILL.md", adaptStitch(stitchSrc));
write("cursor/skills/gsd-ui-design-pick/SKILL.md", adaptPick(pickSrc));
