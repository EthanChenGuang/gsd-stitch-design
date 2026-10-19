# gsd-stitch-design

给 GSD 项目用的「全局设计 + 每阶段界面设计稿」工作流，打包成两个可移植的 skill，一条命令装进任何 GSD 项目。当前版本见 `VERSION`（1.0.0），变更记录见 `CHANGELOG.md`。

## 这是什么

两层设计，一个来源：

- **全局层**（整个项目一份）：`.planning/design/DESIGN.md` 是颜色、字体、间距、圆角、阴影、动效和组件视觉规则的**唯一来源**。使用 Stitch 时，`.planning/design/stitch.json` 记录**唯一的** Stitch 项目和**唯一的**设计系统。
- **阶段层**（每个阶段一份）：`{NN}-UI-SPEC.md` 只引用全局令牌，补充本阶段的新组件、文案和状态；`{NN}-SCREENS.md` 是界面清单；`design/` 目录放设计稿（html + png + `manifest.json`）。
- **配置层**（整个项目一份）：`.planning/design/design-config.json` 保存产品名、语言、设备、技术栈、品牌禁区、渲染方式。两个 skill 本身不含任何项目信息，全部从这里读。

包里有两个 skill：

| skill | 做什么 |
|---|---|
| `gsd-ui-stitch-phase` | 导入、审查、完善、锁定全局 DESIGN.md；按阶段调用 `/gsd-ui-phase` 出 UI-SPEC；列界面清单；用 Stitch 或 html 渲染器生成全部界面；修改、导出、写 manifest、提交。它在本项目里**替代** `/gsd-ui-phase`。 |
| `gsd-ui-design-pick` | 还没有全局设计时，从 VoltAgent/awesome-design-md 里挑一份起点模板：写设计简报、初筛、打分、并排预览、用户选定或混搭，然后交给 `gsd-ui-stitch-phase` 审查、去品牌化、锁定。 |

另外随 skill 带三个脚本：`shoot.cjs`（HTML 转 PNG）、`contrast.cjs`（WCAG 对比度）、`design-catalog.cjs`（模板目录解析）。

## 前提条件

- **GSD 已安装**：项目内有 `.claude/gsd-core`，或用户目录有 `$HOME/.claude/gsd-core`，或 PATH 上有 `gsd_run`。没有也能安装，但 skill 运行时会停下来提示。
- **Google Stitch MCP**（可选）：只有渲染方式用 Stitch 时才需要；用 html 渲染器完全不需要。确认方法：在 Claude Code 里运行 `/mcp`，看列表里有没有 Stitch；工具名形如 `mcp__Google_Stitch__generate_screen_from_text`。如果服务器用了别的名字，skill 会再按 `generate_screen_from_text` 搜一次并改用实际前缀。怎么连接 Stitch，请以 Google Stitch 官方说明为准，本包不提供连接地址。
- **Node**（>= 18）：三个脚本和安装器里的 JSON 编辑都用 node。
- **Playwright**（可选，html 渲染器截图用）：`npm i -D playwright`，然后 `npx playwright install chromium`。没有时 html 文件照样生成，只是没有 PNG。
- **git 和 GitHub 访问**：`/gsd-ui-design-pick` 要克隆 `https://github.com/VoltAgent/awesome-design-md`。

## 安装

在本仓库里（或任何拿到了这个目录的地方）：

```bash
bash tools/gsd-stitch-design/install.sh /path/to/project --dry-run   # 先看会改什么，不写任何文件
bash tools/gsd-stitch-design/install.sh /path/to/project
```

从 GitHub 获取：先克隆到临时目录，**看过 `install.sh` 之后**再运行。不要把远程脚本直接交给 shell 执行。

```bash
git clone --depth 1 https://github.com/EthanChenGuang/learn-italian /tmp/gsd-stitch-src
# 可选：只取这个目录
#   git clone --depth 1 --filter=blob:none --sparse https://github.com/EthanChenGuang/learn-italian /tmp/gsd-stitch-src
#   git -C /tmp/gsd-stitch-src sparse-checkout set tools/gsd-stitch-design
bash /tmp/gsd-stitch-src/tools/gsd-stitch-design/install.sh /path/to/project --dry-run
bash /tmp/gsd-stitch-src/tools/gsd-stitch-design/install.sh /path/to/project
```

如果仓库是私有的，先用 `gh auth login` 登录 GitHub，再克隆。

### 安装器会改什么

| 位置（相对目标项目） | 动作 |
|---|---|
| `.claude/skills/gsd-ui-stitch-phase/`、`.claude/skills/gsd-ui-design-pick/` | 复制 SKILL.md 和 scripts。已有且内容不同的文件视为冲突，不加 `--force` 就拒绝（退出码 3，什么都不写）。 |
| `.planning/design/design-config.json` | 只在不存在时从模板复制，**任何情况下都不覆盖**（`--force` 也不会）。 |
| `.claude/CLAUDE.md`（没有就用根目录 `CLAUDE.md`，都没有就新建 `.claude/CLAUDE.md`） | 插入或更新一段 `<!-- gsd-stitch-design:start -->` 到 `<!-- gsd-stitch-design:end -->` 之间的「UI Design Workflow」说明，标记之外的内容不动。 |
| `.planning/config.json` | 把 `workflow.ui_phase` 设为 `true`，其他键保持不变；文件不存在或不是合法 JSON 时只给出警告。 |
| `.claude/skills/.gsd-stitch-design-version` | 写入包的版本号。 |

### 参数与退出码

| 参数 | 作用 |
|---|---|
| `--dry-run` | 只打印要做的事（每行以 `[dry-run] ` 开头），不改任何文件 |
| `--force` | 允许覆盖与包内不同的已安装 skill 文件（本地修改会丢失） |
| `--uninstall` | 卸载，见下文 |
| `-h`、`--help` | 显示用法 |

输出行前缀：`+` 新建，`~` 更新，`=` 无变化，`-` 删除，`WARN:` 警告，`CONFLICT:` 冲突文件。退出码：0 成功，1 出错（目标不是目录、没有 node、标记不成对等），2 用法错误，3 因冲突拒绝。

## 配置

安装后编辑 `.planning/design/design-config.json`。至少填 `product_name`、`product_pitch`、`audience`、`ui_language`；不填的话，skill 第一次运行时会用提问的方式帮你填。模板里每个字段都有 `_comment` 说明，`templates/design-config.example.json` 是一个填好的完整示例。

| 字段 | 类型 | 默认 | 必填 | 用在哪里 |
|---|---|---|---|---|
| `product_name` | 字符串 | 空 | 是 | DESIGN.md 标题、Stitch prompt、报告、设计简报 |
| `product_pitch` | 字符串 | 空 | 是 | Stitch prompt、设计简报 |
| `audience` | 字符串 | 空 | 是 | G1 审查、设计简报 |
| `ui_language` | 字符串 | 空 | 是 | G1 排版审查、Stitch prompt、界面文案 |
| `content_language` | 字符串或 null | null | 否 | 界面里展示的内容文本所用语言；null 表示与界面语言相同，此时跳过「内容语言」审查行 |
| `communication_language` | 字符串 | 简体中文 | 否 | skill 与你交流时使用的语言 |
| `device` | MOBILE / DESKTOP / TABLET | MOBILE | 否 | G1 设备适配、Stitch `deviceType`、预览页导航形态 |
| `viewport` | `{width, height}` | 390 x 844 | 否 | Stitch prompt 约束行、html 渲染器的截图尺寸 |
| `stack` | `{css, components}` | 都为空 | 否 | G1「可实现性」、design-pick 的实现成本打分 |
| `brand_exclusions` | 字符串数组 | `[]` | 否 | 绝不模仿、也不写进设计和 prompt 的品牌；G1「原创性与授权」、design-pick 初筛 |
| `font_rules` | 字符串数组 | `[]` | 否 | G1「UI 语言排版」一行里逐条核对 |
| `review_extra_checks` | `[{dimension, check}]` | `[]` | 否 | 追加到 G1 审查表末尾的行 |
| `preview_samples` | 对象（heading、primary_action、secondary_action、body_text、list_items、conversation、domain_components、nav_items） | 全部为空 | 否 | design-pick 并排预览页的示例内容；全空时由 skill 根据简报自行编造 |
| `renderer` | auto / stitch / html | auto | 否 | 设计稿渲染方式，可被 `--renderer` 覆盖 |
| `stitch_project_title` | 字符串 | 空 | 否 | Stitch 项目标题；空表示使用 `product_name` |

## 在 GSD 生命周期里的位置

```
new-project
   |
discuss-phase  ---- 写 {NN}-CONTEXT.md
   |
ui-stitch-phase  (/gsd-ui-stitch-phase {N}，替代 /gsd-ui-phase)
   |   读：design-config.json、DESIGN.md、PROJECT.md、CONTEXT.md、REQUIREMENTS.md
   |   写：DESIGN.md（全局，仅首次或 G4）、{NN}-UI-SPEC.md、{NN}-SCREENS.md、
   |        design/manifest.json、design/*.html / *.png、(html) design/tokens.css
   |   确认点：G2 逐条讨论 -> G3 锁定 -> B' 令牌不一致时二选一 -> C 界面清单
   |            -> E1 样板 -> F 修改 -> G4 全局变更需批准
plan-phase     ---- 规划者在任务里引用设计稿
   |
execute-phase  ---- 执行者对照截图实现；令牌取自 DESIGN.md，文案和状态取自 UI-SPEC
   |
code-review
   |
verify
```

要点：全局设计（G 步）只在项目里做一次；之后每个前端阶段只跑 A 到 H。

## 全局设计启动的两条路径

1. **挑选模板**：运行 `/gsd-ui-design-pick`。它先写设计简报（`DESIGN-BRIEF.md`），拉取 awesome-design-md，初筛、打分，生成并排预览页，你选定一份或混搭，保存为 `.planning/design/candidates/{id}-DESIGN.md`，再自动交给 `/gsd-ui-stitch-phase --design-only --design <候选>` 去审查、去品牌化、锁定。参数：`--refresh`、`--top <n>`、`--direction "<风格描述>"`、`--no-handoff`。
2. **自带文件**：已有一份 DESIGN.md 时，运行 `/gsd-ui-stitch-phase --design-only --design <file>`（也可以在对话里附上文件）。skill 会按清单审查、写 `DESIGN-REVIEW.md`、逐条与你讨论，然后锁定。

两条路径都没用时（全局 DESIGN.md 不存在，又选择「从 UI-SPEC 生成」），第一个阶段的 UI-SPEC 通过后会走 G5：把它提升为全局设计，再讨论、锁定。

## 每阶段步骤与参数

| 步骤 | 做什么 |
|---|---|
| 0 | 解析 GSD 与 skill 目录，读 design-config.json（缺失或必填项为空就提问并补全），加载 Stitch 工具，路由 |
| G1–G3 | 导入审查、讨论完善、锁定并同步到 Stitch（renderer 为 html 时不同步） |
| G4 | 锁定后要改令牌：写 `DESIGN-CHANGE-v{n}.md`、评估影响、用户批准后改 DESIGN.md |
| G5 | 没有全局设计时，由第一个 UI-SPEC 提升 |
| A–B | 调用 `/gsd-ui-phase` 出 UI-SPEC |
| B' | 令牌一致性检查：UI-SPEC 里的颜色等必须来自全局设计 |
| C | 界面清单 `{NN}-SCREENS.md`，用户确认 |
| E | 生成界面：样板（用户确认）再批量；`auto` 时在 E1 探测 Stitch 文件能否下载 |
| F | 修改；涉及令牌的修改必须走 G4 |
| X | 导出 html + png，写 manifest，在 UI-SPEC 末尾加 `## Screen Designs` 一节 |
| H | 提交 `docs({NN}): screen designs for phase {N} ({renderer})`，更新 STATE，提示 `/gsd-plan-phase {N}` |

`/gsd-ui-stitch-phase` 的参数：

| 参数 | 作用 |
|---|---|
| `[phase]` | 阶段号；省略时取下一个未规划的阶段 |
| `--design <path>` | 导入你的 DESIGN.md，进入 G1 |
| `--design-only` | 只处理全局设计，不跑阶段 |
| `--from-screens` | UI-SPEC 已通过审核，从 C 开始 |
| `--export-only` | 界面已定稿，只做 X 到 H |
| `--renderer auto\|stitch\|html` | 本次运行的渲染方式，覆盖配置 |

## 和 GSD 原生行为的冲突点

- `/gsd-autonomous` 通过 GSD 自己的 `plan:pre` 钩子调用 `gsd-ui-phase`，**不会**应用「用 ui-stitch-phase 替代」的规则。前端阶段要先手动运行 `/gsd-ui-stitch-phase {N}`，再进入自动模式。
- 直接输入 `/gsd-ui-phase` 时，Claude 会先问你：要完整的 `/gsd-ui-stitch-phase` 流程，还是只要 UI-SPEC。
- 令牌（颜色、字体、间距、圆角、阴影、动效）锁定后不能在阶段里悄悄改，只能走 G4，并留下 `.planning/design/DESIGN-CHANGE-v{n}.md`。
- `workflow.ui_phase` 必须保持 `true`，否则 `/gsd-ui-phase` 会提前退出，`/gsd-ui-stitch-phase` 也就跑不起来。安装器会帮你设置。
- 设计稿如何回到后续流程：每阶段的 `design/manifest.json` 记录界面与文件；UI-SPEC 末尾的 `## Screen Designs` 列出设计稿；安装进 CLAUDE.md 的那一段要求规划者在任务里引用相关界面、执行者对照截图实现。

## 渲染方式：stitch 还是 html

| | stitch | html |
|---|---|---|
| 界面在哪里 | Stitch 网页上的唯一项目（界面带 `[P{NN}]` 前缀） | 阶段目录下的独立 `.html` 文件 + `design/tokens.css` |
| 保真度 | Stitch 生成，受其风格影响，需要用设计系统约束 | Claude 按 DESIGN.md 令牌手写，文案逐字取自 SCREENS.md，颜色只通过 `var(--...)` |
| 需要什么 | Stitch MCP；下载文件可能需要 Google 登录态 | 只需要 Playwright 才能截图（HTML 本身不需要） |
| 导出 | `get_screen` 取回 html 和截图，取不回就走网页导出 zip | 本来就是文件，核对 html 和 png 即可 |
| 修改 | `edit_screens`、`generate_variants`、`apply_design_system` | 直接改 html，用 `shoot.cjs` 重新截图 |
| `auto` 时何时选 | E1 里真的去取 Stitch 返回的文件，能取到就选 stitch | 取不到（例如 401）或没有 Stitch 工具时，建议选 html |

设置：在 design-config.json 里写 `"renderer": "auto"`、`"stitch"` 或 `"html"`，或在命令里带 `--renderer`。选定后会写进每阶段 manifest 的 `renderer` 字段；确定了就把配置里的值改成它，下次不用再探测。

## Parla 实践经验

下面只列源项目里有证据的做法，每条标明证据文件：

- Stitch 的下载链接在没有 Google 登录态时返回 401，文件取不回来（`.planning/design/stitch.json`）。所以 `auto` 模式在 E1 就去真的下载一次，不行就建议改用 html。
- Stitch 返回的缩略图是 1x 的桌面画布截图，看起来分辨率很低；编辑过的界面还会从项目列表里消失（同在 `.planning/design/stitch.json` 的备注里）。
- 第 1 阶段最终没有用 Stitch：设计稿是 Claude 写的 HTML，用 Playwright 按 390x844 @2x 渲染（`.planning/phases/01-accounts-text-tutor/design/manifest.json` 的 `renderer` 字段）。html 渲染器就是把这个做法固化下来。
- DESIGN.md 升到了 v2，而 Stitch 里的设计系统还停在 v1（`.planning/design/stitch.json` 的 `note_v2`）。所以才有「全局前置检查」里的版本落后提示。
- 从 v1 到 v2 的全局变更是先写成提案文件再批准的（`.planning/design/DESIGN-CHANGE-v2.md`），G4 因此固定产出 `DESIGN-CHANGE-v{n}.md`。
- awesome-design-md 里的模板都是仿某个真实品牌的分析，选定后要去品牌化再锁定（`.planning/design/DESIGN-PICK.md`，候选文件在 `.planning/design/candidates/`）。

## 卸载

```bash
bash tools/gsd-stitch-design/install.sh /path/to/project --uninstall --dry-run   # 先预览
bash tools/gsd-stitch-design/install.sh /path/to/project --uninstall
```

会删除：两个 skill 目录、`CLAUDE.md` 里标记之间的那一段（连同它前面的一个空行，所以安装再卸载后文件内容和原来逐字节一致；删完变成空文件就一并删除）、版本文件。

不会动：`.planning/design/`（包括 design-config.json 和你的 DESIGN.md）、`.planning/config.json` 里的 `workflow.ui_phase`。

## 升级

1. 取得新版本的包（再次克隆，或更新你已有的副本），读 `CHANGELOG.md`。
2. 先预览：`bash tools/gsd-stitch-design/install.sh /path/to/project --dry-run`。
3. 重新运行安装。如果你改过已安装的 skill 文件，会看到 `CONFLICT:` 并以退出码 3 拒绝；确认可以丢弃本地修改时加 `--force`。
4. 已安装的版本号在 `.claude/skills/.gsd-stitch-design-version`。
5. `design-config.json` 永远不会被覆盖：新版本加了字段时，把 `templates/design-config.json` 与你的文件对一下，手工补上。
6. 想确认包本身没问题，运行自检：`bash tools/gsd-stitch-design/test/install.test.sh`，最后一行应为 `ALL TESTS PASSED`。
