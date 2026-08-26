# 偏好窗口 macOS 26 渲染修复 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 MacGesture 偏好窗口在 macOS 26 (Tahoe) 深/浅两种模式下正常渲染，同时不改变老系统（部署目标 10.13）上的行为。

**Architecture:** 根因已实测确认为 **xib 序列化的遗留面板视图**在 macOS 26 上渲染反相（非窗口容器问题）。计划先跑 3 个便宜 spike（面板审计 / `UIDesignRequiresCompatibility` 一键开关 / 界定「重建」爆炸半径），再据结果落地一个**版本门控**（`majorVersion >= 26`）的程序化修复，写在 `AppPrefsWindowController` 里；老系统一行不动。

**Tech Stack:** Objective-C + AppKit；Xcode 26.6（本地，`/Applications/Xcode.app`）；验证靠 lldb + `screencapture`（真实合成画面，**不用** `cacheDisplayInRect`——它不捕获 `layer.backgroundColor`，会误导）。

**Spec:** [docs/superpowers/specs/2026-08-25-prefs-window-macos26-rendering-design.md](../specs/2026-08-25-prefs-window-macos26-rendering-design.md)

## Global Constraints

- **版本门控**：修复仅在 `[NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 26` 时生效；macOS < 26 走原 xib 路径，一行不动。
- **部署目标保持 10.13**（`MACOSX_DEPLOYMENT_TARGET`），不依赖路线图 P1-2。
- **无损保留**：37 个 IBOutlet、31 个 IBAction、四语言文案（Base/en/cs/zh-Hans）、所有现有行为。
- **不硬编码坐标**：重建时读取已加载视图的现有 `frame`/`autoresizingMask` 定位（绕开 `FB18835363` struts-and-springs 错位回归）。
- **验证口径**：`screencapture -l<windowNumber>`（真实合成画面），深色**和**浅色两种模式都要过；渲染 bug 不做 xUnit 断言。
- **不碰**签名/公证/发布；不改其他面板的功能性 bug。
- **分支**：`claude/p4-prefs-macos26`，合入 `develop` 走 PR。

## 复用工具：本地构建 + 截图自查管线

这些命令在下方任务中反复引用，先在此定义（均已在调研阶段实测可用）：

**构建（Debug）：**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project MacGesture.xcodeproj -scheme MacGesture \
  -configuration Debug -derivedDataPath /tmp/mg-dd > /tmp/mg-build.log 2>&1
grep -c "BUILD SUCCEEDED" /tmp/mg-build.log   # 1 = 成功
```

**启动 + 打开偏好窗口（单实例技巧 + 兜底调用 delegate）：**
```bash
pkill -x MacGesture 2>/dev/null; sleep 1
APP=/tmp/mg-dd/Build/Products/Debug/MacGesture.app
open "$APP"; sleep 2.5; open -n "$APP" 2>/dev/null; sleep 2   # 第二个实例触发老实例打开偏好
PID=$(pgrep -x MacGesture | head -1)
# 若偏好窗口没开（被辅助功能授权 alert 挡住），关 alert 并直接调 delegate：
lldb -p $PID -b \
  -o 'expr -l objc -O -- (void)({ for (id w in (NSArray*)[(id)NSApp windows]) if(((char*)strstr((const char*)object_getClassName(w),(const char*)"Alert"))!=0) [w close]; id d=(id)[(id)NSApp delegate]; if((BOOL)[d respondsToSelector:@selector(openPreferences:)]) [d openPreferences:(id)0]; })' \
  -o detach >/dev/null 2>&1
```

**截取偏好窗口真实画面到 PNG（供 Read 视觉判读）：**
```bash
PID=$(pgrep -x MacGesture | head -1)
osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$PID"') to true' 2>/dev/null
sleep 1
WN=$(lldb -p $PID -b -o 'expr -l objc -- (long)({ id p=nil; for (id w in (NSArray*)[(id)NSApp windows]) if((BOOL)[w isKindOfClass:(id)[NSWindow class]]&&(BOOL)[w isVisible]&&(id)[w toolbar]!=nil) p=w; (long)[p windowNumber]; })' -o detach 2>&1 | grep -oE '= [0-9]+' | grep -oE '[0-9]+' | head -1)
screencapture -l"$WN" -x -o -t png /tmp/prefs.png    # 然后 Read /tmp/prefs.png
```

**切换某个面板**（工具栏项标识符 = 面板显示名，英文本地化下为 `General`/`Gestures`/`Filters`/`AppleScript`/`About`）：
```bash
lldb -p $PID -b -o 'expr -l objc -O -- (void)({ id p=nil; for (id w in (NSArray*)[(id)NSApp windows]) if((BOOL)[w isKindOfClass:(id)[NSWindow class]]&&(BOOL)[w isVisible]&&(id)[w toolbar]!=nil) p=w; id c=(id)[p delegate]; if((BOOL)[c respondsToSelector:@selector(loadViewForIdentifier:animate:)]) [c loadViewForIdentifier:(id)@"PANELNAME" animate:(BOOL)0]; })' -o detach >/dev/null 2>&1
```

---

## 阶段 0 — Spike（先行，带决策门）

### Task 0: 基线复现 + 管线自检

**Files:**
- 无源码改动（仅本地构建 + 验证）

**Interfaces:**
- Produces: 一张 `/tmp/prefs.png` 基线截图（复现白板 bug）；确认构建 + 截图管线可用。

- [ ] **Step 1: 确认在 macOS 26 上**

Run: `sw_vers -productVersion`
Expected: `26.x`（若非 26，本计划整体不适用，停止并上报）

- [ ] **Step 2: 本地 Debug 构建**（用上方「构建」命令）

Expected: `grep -c "BUILD SUCCEEDED"` 输出 `1`。若失败，尾部 `tail -30 /tmp/mg-build.log` 排查（常见：Xcode 未跑 `xcodebuild -runFirstLaunch`，需人工 `sudo`）。

- [ ] **Step 3: 启动并打开偏好窗口**（用上方「启动」命令）

- [ ] **Step 4: 截图并判读基线**（用上方「截图」命令，然后 Read `/tmp/prefs.png`）

Expected: 深色模式下内容区大面积白、控件/文字不可见 —— 复现 bug。**若此步渲染正常**（未复现），说明该 macOS 版本或环境已不触发，停止并上报（可能 Apple 已在 OS 更新中修复，见 spec R4）。

- [ ] **Step 5: 记录基线**

把 `/tmp/prefs.png` 另存为 `/tmp/mg-baseline-dark.png` 备查；无需提交（本 Task 无源码改动）。

**决策门**：基线复现 → 进 Task 1。

---

### Task 1: 5 个面板逐一审计

**Files:**
- 无源码改动

**Interfaces:**
- Produces: 「受影响面板清单」——后续只重建清单内的面板。

- [ ] **Step 1: 逐面板截图**

对 `General` / `Gestures` / `Filters` / `AppleScript` / `About` 各执行：用上方「切换面板」命令切过去 → 「截图」命令存成 `/tmp/mg-panel-<名字>.png` → Read 判读。

- [ ] **Step 2: 记录清单**

在本任务的提交信息或一条 issue #11 评论里，列出每个面板「正常 / 白板 / 部分白」的判读结果（附截图事实）。已知 `General` 白板。

**决策门**：得到受影响面板清单 → 进 Task 2。

---

### Task 2: Spike 0a — `UIDesignRequiresCompatibility`

**Files:**
- Modify（临时，可能回滚）: `MacGesture/Supporting Files/MacGesture-Info.plist`

**Interfaces:**
- Produces: 「0a 是否采纳」的判定。采纳 → 跳到 Task 5；否则 → 进 Task 3。

- [ ] **Step 1: 加键**

在 `MacGesture-Info.plist` 顶层 dict 加：
```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```

- [ ] **Step 2: 重建 + 打开 + 截图**（复用上方三条命令），Read 判读

- [ ] **Step 3: 判定（含浅色模式）**

若深色模式渲染正常，**必须再切系统到浅色模式**重截一次确认（spike 要求人工切系统外观；无法自动化时在此暂停请维护者切换后继续）。同时逐面板核对布局未被破坏（对照 Task 1 的截图）。

- [ ] **Step 4a（若采纳）: 保留键 + 文档标注**

在 plist 该键上方加注释说明「过渡开关，针对 macOS 27 SDK 构建即失效，需复查」；提交；跳到 **Task 5**。

- [ ] **Step 4b（若丢弃）: 回滚该键**

```bash
git checkout -- "MacGesture/Supporting Files/MacGesture-Info.plist"
```
进 **Task 3**。

**决策门**：采纳 → Task 5；丢弃 → Task 3。

---

### Task 3: Spike 0b — 界定「重建」爆炸半径

**Files:**
- 无源码改动（lldb 运行时试验）

**Interfaces:**
- Produces: 「B 的形态」判定 —— B-外科版（Task 4-surgical）或 B-完整版（Task 4-full）。

- [ ] **Step 1: 取一个盒子外、当前渲染正常的现有控件，重 parent 到新建 NSView**

启动并打开偏好窗口后，用 lldb 找到 General 面板里一个**当前渲染正常**的控件（Task 1 截图中可见的、位于盒子外的按钮/标签），新建一个普通 `NSWindow`+`NSView`，把该控件 `addSubview:` 进去，`makeKeyAndOrderFront:`，取新窗口 `windowNumber` 后 `screencapture`。（参考调研阶段已跑通的 objc_msgSend spike 写法；控件地址用 `recursiveDescription` 定位。）

- [ ] **Step 2: 判读该控件在新容器里是否变白**

Read 新窗口截图。

- [ ] **Step 3: 判定**

- 控件仍正常 → 现有控件可安全搬动 → **Task 4-surgical**。
- 控件变白 → 搬动即中招 → **Task 4-full**。

**决策门**：按 Step 3 分流。

---

## 阶段 1 — 重建（按决策门二选一）

> **重要**：阶段 0 跑完后，先把「受影响面板清单（Task 1）」和「B 形态（Task 3）」回填，然后**重新进入 writing-plans 把下面选中的变体展开成逐面板、逐步骤的具体任务**（每个受影响面板一个子任务，含该面板实际的盒子/控件地址与 frame）。此处给出的是变体骨架与验证闭环，不是最终逐步骤清单——因为具体步骤依赖 Task 1/3 的实测结果，提前写死会是臆造。

### Task 4-surgical: 只替换 NSBox 容器（首选）

**Files:**
- Modify: `MacGesture/Controllers/AppPrefsWindowController.m`（新增私有方法 + 在 `setupToolbar` 开头调用）

**Interfaces:**
- Produces: `-mg_repairMacOS26PrefsRenderingIfNeeded`（版本门控入口）、`-mg_replaceBoxesIn:(NSView *)root`（递归把 `NSBox` 换成普通 `NSView` + 标题标签，移入现有子控件）。

- [ ] **Step 1: 写门控入口 + 递归替换方法**

```objc
// macOS 26 把 NSBox 换成 SwiftUI 承载，老 xib 的盒子会渲染反相。
// 换成普通 NSView 容器 + 标题标签，移入现有子控件（保留 outlet/action）。
- (void)mg_repairMacOS26PrefsRenderingIfNeeded {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 26) return;
    for (NSView *panel in @[_generalPreferenceView, _rulesPreferenceView,
                            _filtersPrefrenceView, _appleScriptPreferenceView,
                            _aboutPreferenceView]) {
        [self mg_replaceBoxesIn:panel];
    }
}

- (void)mg_replaceBoxesIn:(NSView *)root {
    for (NSView *sub in [root.subviews copy]) {
        if ([sub isKindOfClass:[NSBox class]]) {
            NSBox *box = (NSBox *)sub;
            NSView *content = box.contentView;           // 现有内容（含控件）
            NSString *title = box.title;
            NSBoxType type = box.boxType;

            NSView *plain = [[NSView alloc] initWithFrame:box.frame];
            plain.autoresizingMask = box.autoresizingMask;

            NSRect cf = content.frame;                   // 现有 frame，不硬编码
            [content removeFromSuperview];
            content.frame = cf;
            [plain addSubview:content];

            if (title.length > 0 && type != NSBoxSeparator) {
                NSTextField *label = [NSTextField labelWithString:title];
                label.font = [NSFont boldSystemFontOfSize:11];
                label.textColor = [NSColor secondaryLabelColor];
                [label sizeToFit];
                NSRect lf = label.frame;
                lf.origin = NSMakePoint(NSMinX(cf), NSMaxY(plain.bounds) - NSHeight(lf));
                label.frame = lf;
                label.autoresizingMask = NSViewMinYMargin;
                [plain addSubview:label];
            }
            [box.superview replaceSubview:box with:plain];
            [self mg_replaceBoxesIn:plain];              // 处理嵌套盒子
        } else {
            [self mg_replaceBoxesIn:sub];
        }
    }
}
```
并在 `- (void)setupToolbar {` 第一行插入 `[self mg_repairMacOS26PrefsRenderingIfNeeded];`。

- [ ] **Step 2: 构建**（上方「构建」命令）→ Expected `BUILD SUCCEEDED`。

- [ ] **Step 3: 验证渲染（深色）**

启动 + 打开偏好 + 逐个受影响面板截图（Task 1 清单里的那些）→ Read 判读。Expected: 每个面板背景与窗口一致（深灰）、控件与文字全部可见。

- [ ] **Step 4: 验证渲染（浅色）**

请维护者切系统到浅色模式，重复 Step 3。Expected: 浅色下同样正常，无黑底反相。

- [ ] **Step 5: 验证布局未错位**

对照 Task 1 的每面板截图，确认控件位置/大小与替换前一致（重点看嵌套盒子与标题位置）。若错位，回到 Step 1 调整（标题标签定位、content frame）。

- [ ] **Step 6: 功能自检（人工，维护者）**

每个受影响面板：控件可点、状态正确；四语言切换后文案正常；关键 IBAction（重置确认框、导入 alert 等）行为不变。

- [ ] **Step 7: 提交**

```bash
git add "MacGesture/Controllers/AppPrefsWindowController.m"
git commit -m "fix(prefs): macOS 26 用普通 NSView 替换 NSBox 修复渲染反相（P4-1）"
```

**若 Step 3–5 任一失败且无法调好** → 说明外科版不够，升级到 Task 4-full（回到 writing-plans 展开）。

### Task 4-full: 程序化重建受影响面板（兜底）

**Files:**
- Modify: `MacGesture/Controllers/AppPrefsWindowController.m`（每个受影响面板一个 builder）

**Interfaces:**
- Produces: `-mg_repairMacOS26PrefsRenderingIfNeeded`（同上门控）+ 每面板 `-mg_buildXxxPanel`（全新创建视图与控件，重新接 outlet/action）。

- [ ] **展开占位**：本变体规模大（最多 5 面板、37 outlet、31 action），**必须在 Task 1（确定哪些面板坏）+ Task 3（确认必须全新重建）出结果后，回到 writing-plans**，为**每个受影响面板**生成独立子任务，每个子任务含：该面板控件清单、frame（读现有值）、outlet/action 重接代码、TDD 无法覆盖故用 screencapture + 人工验证闭环（同 Task 4-surgical Step 3–7）。在此之前不臆造具体步骤。

---

## Task 5: （仅当 0a 采纳）收尾 `UIDesignRequiresCompatibility`

**Files:**
- 已在 Task 2 Step 4a 提交 plist 改动

- [ ] **Step 1: 开 issue 追踪过渡开关**

开一条 issue：「`UIDesignRequiresCompatibility` 是过渡方案，针对 macOS 27 SDK 构建即失效，需在升级 SDK 前用真正的重建方案（本计划 Task 4）替换」。关联 #11、本计划。

- [ ] **Step 2: 逐面板 + 双外观验证**

同 Task 4-surgical 的 Step 3/4/6（渲染 + 功能）。

- [ ] **Step 3: 跳到 Task 6。**

---

## Task 6: 合入与验收

**Files:**
- 无新增源码改动（收尾）

- [ ] **Step 1: 推分支**

```bash
git push -u origin claude/p4-prefs-macos26
```

- [ ] **Step 2: 开 PR（草稿转正式前先过 CI）**

PR base `develop`；正文写明：根因、采纳的变体（0a / 外科 / 完整）、受影响面板清单、验证证据（截图）、版本门控说明、以及「渲染修复无法 CI 验证（runner SIP=disabled 且无 GUI），需真机人工验收」。

- [ ] **Step 3: CI 编译通过**

等 `.github/workflows/build.yml` 两档（macos-15 / macos-26）绿。CI 只保证**能编译**，不验证渲染。

- [ ] **Step 4: 真机 GUI 验收（维护者）**

在 macOS 26 上装 CI 产物或本地构建，逐面板确认渲染 + 功能（深/浅两模式）。

- [ ] **Step 5: 合并 + 收尾**

验收通过后合入 `develop`；更新/关闭 issue #11；在 PR #8 下说明「偏好窗口已修，GUI 验收解除阻塞」。

---

## Self-Review（对照 spec）

- **Spec 覆盖**：§5 阶段 0 三 spike → Task 0/1/2/3；阶段 1 B 两变体 → Task 4-surgical/4-full；0a 采纳分支 → Task 5；§6 验证（screencapture + 人工 + 双外观）→ 各 Task 的验证步骤；§9 交付 → Task 6。无遗漏 spec 章节。
- **占位符**：Task 4-full 的「展开占位」是**有意的决策门后延展**（spec 明确 B 形态由 spike 决定），非偷懒 TODO——已注明触发条件与再入 writing-plans 的动作，且给出了 Interface 契约。其余步骤均含实际命令/代码。
- **类型一致**：门控方法名全程统一为 `-mg_repairMacOS26PrefsRenderingIfNeeded`；外科版方法 `-mg_replaceBoxesIn:`；面板 outlet 名与 `AppPrefsWindowController.h` 一致（`_generalPreferenceView` 等，含拼写 `_filtersPrefrenceView`）。

---

## 阶段 0 执行结果（2026-08-25 实测，本机 macOS 26.5.2）

| Task | 结果 |
|---|---|
| Task 0 基线 | ✅ 复现：General 面板深色模式全白 |
| Task 1 审计 | ✅ **只有 General 坏**；Gestures / Filters / AppleScript / About 四个面板全部正常渲染。当时相关性=「唯一含 NSBox 的面板坏」 |
| Task 2 `UIDesignRequiresCompatibility` | ❌ 无效（仍白 + 把 app 整体拖进浅色兼容外观），已回滚 |
| Task 3 爆炸半径 | ✅ 决定性：**现有 xib 控件个体被诅咒**——搬到「全新 NSView(红块) 能正常渲染的同处」仍白；全新代码创建的视图/控件正常 |
| 候选 X（改 xib 拆盒子） | ❌ **失败，且证伪了「盒子」假设**：把 General 的 3 个 NSBox 从 xib 中拆除（27 个控件移到面板下、frame 已按偏移修正、XML 合法、编译通过），General **仍全白**。boxType 改 custom 也无效。 |

### 修正后的根因判断

- **不是 NSBox**：控件即使从一开始就不在任何盒子里加载（xib 已无盒子），General 仍白。
- **其余 4 个面板正常也不是因为「没盒子」**——真正的判别因素**仍未查清**。General 相对其它面板的独有物：3 个 `ComboColorWell`（自定义 NSView 子类）、`NSSlider`、带数据的 `NSPopUpButton`、以及 `windowDidLoad` 里对 General 控件的大量运行时操作（combo 填充、slider frame 调整等）。哪一个是毒源**未定位**。
- **唯一已证实可行的路径**：**B-完整版**——用代码全新创建 General 的控件（全新视图已被红块实验证实渲染正常），而非复用/搬动 xib 控件。这是目前唯一「有正面证据支持」的修法，尽管根因未解释。

### 已排除清单（都实测无效）

盒子替换 / 拆除盒子 / boxType=custom / 隐藏 SwiftUI 外壳 / 清 layer.contents / 切 appearance / 补 layer 背景色 / `UIDesignRequiresCompatibility`。

### 给接手方

- **下一步 = B-完整版**（Task 4-full），需回到 writing-plans 为 General 的 ~27 个控件逐一展开「全新创建 + 重接 outlet/action/绑定」。规模较大、易错（尤其 ColorWell/Slider/带数据下拉/绑定）。
- **值得先花时间定位真正的毒源**（为什么 General 的现有控件白、其它面板不白）——若能找到单点原因，可能有比 B-完整版小得多的修法。建议方向：逐个从 General 移除/替换嫌疑控件类型（先 ColorWell，再 Slider/PopUp），二分定位。
- 验证管线（本地构建 + lldb 开偏好 + `screencapture -l<windowNumber>`）已在本计划顶部「复用工具」记录，可直接复用。

---

## 阶段 1 执行结果（2026-08-25 二分定位 + 最小修复，本机 macOS 26.5.2 + Xcode 26.6）

**根因已定位（决定性，非推断）：自定义类 `ComboColorWell`（`NSColorWell` 子类）。**

二分方法：在 `AppPrefsWindowController` 的 `windowDidLoad`（**首次显示前**）用临时 env 门控 `removeFromSuperview` 各嫌疑控件，逐组截图判读（临时探针已回滚，不进提交）：

| 实验 | 结果 |
|---|---|
| 基线（真实 ComboColorWell） | ⬜️ 整个 General 内容区全白 |
| 显示**后** `setHidden:YES` 全部 8 个嫌疑控件 + 强制重绘 | ⬜️ 仍白 → **白色 baked 在首次显示，不是 live drawRect 产物** |
| 显示**前** `removeFromSuperview` 全部 8 个 | ✅ 完美渲染 → 毒源在这 8 个里 |
| 显示前只移除 **5 个 color well**（保留 slider + 两个 popup） | ✅ 完美 → **color well 是唯一毒源；slider/popup 无辜** |
| 把 ComboColorWell 换成**原生 `NSColorWell`** | ✅ 完美 → **是自定义子类，不是 NSColorWell 本身** |
| 对自定义 well 加 `wantsLayer` / 设 `colorWellStyle` | ⬜️ 仍白 → 子类无法靠属性微调救活 |

**机制**：`ComboColorWell` 整段 override `drawRect:` 且不调 `super`；在 macOS 26 上这条遗留自定义绘制路径与重新设计的 `NSColorWell` 不兼容，导致**整个 General 面板**被合成为一张不透明白位图（面板级，非盒子级——这也**推翻了之前的按盒子推断**：5 个 well 在「Gesture」盒子里，却连它上方「General」盒子一起变白）。

**修正之前的排除结论**：阶段 0 说「拆盒子后仍白 ⇒ 非盒子问题」是对的；但当时把 5 个盒子外/盒子内控件一起搬动，掩盖了真正的单点毒源。本轮用「首次显示前逐类移除」的干净二分才隔离出 ComboColorWell。

### 采纳的修法：Design B — `ComboColorWell.drawRect:` 在 macOS 26 交回 `super`

```objc
- (void)drawRect:(NSRect)cellFrame {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 26) {
        [super drawRect:cellFrame];   // 交给原生 NSColorWell 绘制
        return;
    }
    ... 原自定义绘制（macOS < 26 一行不动）...
}
```

- **仅 1 文件 ~8 行**：`MacGesture/Helpers/ComboColorWell.m`。不动 xib / 37 个 outlet / binding / action。
- **版本门控** `majorVersion >= 26`，与全局约束一致；macOS < 26 保留自定义外观。
- **`B-完整版（Task 4-full）不再需要`**——单点根因 ⇒ 最小修复即可。
- 验证：深色 ✅ / 浅色（运行时强制 Aqua）✅ 均完整渲染，5 个 color well 变原生 Tahoe 样式、仍可用/enabled。其余 4 面板不含 ComboColorWell，且本改动为类内 drawRect，逻辑上不受影响（结合阶段 0 审计）。

### 已知功能待人工确认（不阻塞渲染修复）

- 旧 `drawRect` 末尾调 `applyActive` 设 `colorPanel.showsAlpha = allowsClearColor`（5 个 well 都 `allowsClearColor=YES`）。macOS 26 走 `super` 后不再调用，原生取色面板的**透明度滑块可能不再自动出现**。经与维护者确认：**接受原生外观，透明度行为留待人工功能验收**（如需，后续加一个版本门控的 `-activate:` override 补 `showsAlpha`）。
- 面板切换在「lldb 停住进程注入调用」下驱动不可靠（方法返回但界面不切，属 AppKit 显示需 runloop 的探测局限），非产品缺陷、与本修复无关。
