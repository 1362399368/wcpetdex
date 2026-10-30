# 贡献指南

本仓库的所有改动都走「切分支 → 提交 → 发拉取请求 → 合并」。提交信息格式遵循[约定式提交 1.0.0](https://www.conventionalcommits.org/zh-hans/v1.0.0/)，下文在其基础上补充本仓库的分支、范围、语言和长度约定。

## 分支规范

### 基本规则

- `main` 分支只接收拉取请求合并，不直接在 `main` 上提交，也不直接推送到 `main`。
- 任何改动都先从最新的 `main` 切出分支，包括只改一行文档或一个错别字。
- 一个分支只做一件事。顺手发现的其他问题另开分支。
- 合并后删除分支，本地和远端都删。

### 分支命名

格式为 `<类型>/<简短描述>`：

- 类型与提交信息的类型相同，取本次改动的主要类型，见下文「类型」。
- 简短描述用英文小写单词，单词之间用 `-` 连接，不超过 5 个单词。

示例：

```text
feat/checkin-reminder
fix/barrage-retry-queue
docs/contributing-and-readme
refactor/overlay-recovery
```

### 完整流程

1. 同步 `main` 并切分支：

   ```bash
   git switch main
   git pull origin main
   git switch -c fix/barrage-retry-queue
   ```

2. 开发并按下文「提交信息规范」提交。`git add` 写明确路径，不用 `git add -A` 或 `git add .`，避免把无关文件带进来。
3. 开发期间 `main` 有新提交时，用变基同步：

   ```bash
   git fetch origin
   git rebase origin/main
   ```

   已经推送过的分支变基后用 `git push --force-with-lease` 推送。只对自己的分支这样做，别人也在用的分支改用 `git merge origin/main`。

4. 推送分支，在 GitHub 上发拉取请求，目标分支选 `main`：

   ```bash
   git push -u origin fix/barrage-retry-queue
   ```

5. 拉取请求统一用压缩合并（GitHub 上的 Squash and merge 按钮），合并后删除分支。

### 拉取请求要求

- 标题按提交信息的标题行格式写，例如 `fix(Sources): 修复弹幕重试队列挤掉新消息`。压缩合并时，这个标题就是进入 `main` 的提交信息。
- 描述写三件事：改了什么、为什么改、怎么验证的。
- 验证范围如实写。只跑了模拟器预览就写「只跑了模拟器预览」，真机、过夜、具体微信版本没测就写没测。预览用的是模拟的微信服务，通过不代表真实微信可用。
- 至少保证 `./build.sh preview personal` 能编译通过；改了 `Backend`、`BackendCloudflare`、`BackendPages` 目录的，跑对应目录的测试。

## 提交信息规范

### 格式

提交信息分标题行、正文、脚注三部分，部分之间空一行。只有标题行必写。

```text
<类型>(<范围>): <描述>

<正文>

<脚注>
```

每行不超过 72 个字符，标题行整体不超过 50 个字符。范围连同括号计入长度，超了先压缩描述，不要为了凑长度删掉范围。

### 语言

- 类型和范围恒为英文，照下面两张表原样写。
- 描述和正文用简体中文。
- 2026-10-26 之前的历史提交是英文，保持原样，不改写。

### 类型

| 类型 | 用途 |
| --- | --- |
| `feat` | 新增功能或内容。新功能必须用 `feat` |
| `fix` | 修复缺陷。修缺陷必须用 `fix` |
| `docs` | 只改说明类文档，如 `README.md`、`CONTRIBUTING.md`、`CHANGELOG.md` |
| `style` | 只改格式，不影响含义，如缩进、空格、空行 |
| `refactor` | 调整结构但不改功能，如改名、移动、拆分 |
| `perf` | 提升性能或降低内存占用 |
| `test` | 增加或修改测试 |
| `build` | 改构建脚本或依赖，如 `build.sh`、`package.json` |
| `ci` | 改持续集成配置 |
| `chore` | 不属于以上类型的杂项，如工具脚本、`.gitignore` |
| `revert` | 撤销之前的提交，见下文「撤销提交」 |

不使用 `init`、`misc`、`update`、`draft` 等自定义类型，按实际内容归入上表。

### 范围

范围写改动所在的仓库根目录下那一层目录名，原样照抄，不缩写、不翻译、不改大小写。改动落在 `Sources/` 就写 `Sources`，落在 `BackendCloudflare/src/` 就写 `BackendCloudflare`。

| 范围 | 内容 |
| --- | --- |
| `Sources` | 插件源码 |
| `Preview` | 模拟器预览宿主和模拟的微信服务 |
| `Tests` | 测试和验证脚本 |
| `Tools` | 构建辅助脚本 |
| `Resources` | 打进插件包的桌宠资源 |
| `Assets` | 美术源文件 |
| `Config` | 后端配置示例 |
| `Backend` | Python 版双人互动服务 |
| `BackendCloudflare` | Cloudflare Workers 版双人互动服务 |
| `BackendPages` | Cloudflare Pages 网关 |

以下两种情况省略范围，写成 `<类型>: <描述>`：

- 改动跨多个顶层目录。
- 改的是根目录下的散文件，如 `README.md`、`CHANGELOG.md`、`build.sh`、`.gitignore`。

### 描述

- 以动词开头，概括本次改动，如「新增」「修复」「删除」「调整」。
- 结尾不加句号。

### 正文

- 可选。重点写为什么这么改，不逐行复述改了什么。
- 可以分段，支持 Markdown。

### 脚注

- 可选。每行一条，写成 `键: 值`，键名中的空格用 `-` 代替，如 `Refs: #12`、`Reviewed-by: 张三`。
- `BREAKING CHANGE` 是唯一可以带空格的键名。

### 破坏性变更

改动会让原有用法失效时必须标记，例如删除或改动配置项、偏好设置键名、桌宠包格式、后端协议，或者移动、改名目录导致路径失效。

- 在标题行的冒号前加 `!`，描述里写清楚破坏了什么。
- 需要说明影响或迁移方式时，在脚注写 `BREAKING CHANGE: <说明>`，必须大写。

### 撤销提交

不用 `git revert` 自动生成的 `Revert "..."` 标题，改写成 `revert!: <描述>`，并在脚注写 `Refs: <被撤销提交的短哈希>`，多个用逗号分隔。

### 一次提交只做一件事

改动横跨多个不相关主题时，按主题拆成多次提交，每次只 `git add` 该主题的文件。同一文件里混了多个主题时，用 `git add -p` 拆开。

### 示例

```text
feat(Sources): 新增工作日上班打卡提醒
```

```text
fix(Sources): 修复弹幕重试队列挤掉新消息

收件箱满 12 条时，旧消息的元数据重试会把刚收到的消息顶出队列。
改为重试只占用自己原来的位置，不再按到达顺序淘汰。
```

```text
feat(Backend)!: 将双人互动协议升级到 v3

BREAKING CHANGE: 旧版插件无法连接新服务，需要先升级插件再部署后端
```

```text
revert!: 撤销头像缓存改动

Refs: 1d0420d
```

```text
docs: 补充贡献指南和分支规范
```

## 版本号与更新日志

- 版本号写在 `build.sh` 的 `VERSION`、`RELEASE_TAG`、`BUILD_NUMBER` 和 `WP_VERSION_STRING` 四处，发版时一起改。
- 每个版本在 `CHANGELOG.md` 里写一节，说明改动和实际做过的验证，没验证的部分如实写明。
