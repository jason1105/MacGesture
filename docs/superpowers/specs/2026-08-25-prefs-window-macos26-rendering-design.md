# 设计：修复偏好窗口在 macOS 26 上的渲染错乱（P4-1）

- 状态：**已实现**（根因 = 自定义类 `ComboColorWell`；最小修复已在本机深/浅双模式验证）
- 日期：2026-08-25
- 路线图：议题 #1（P4-1）｜阻塞：议题 #11、PR #8 的 GUI 验收
- 目标定性：**最小修复**（保持现有 UI/控件/行为，只让偏好窗口在 macOS 26 上正常渲染）

> **落地结论（2026-08-25）**：二分定位到毒源是 `ComboColorWell`（`NSColorWell` 子类，整段 override `drawRect:` 不调 super），在 macOS 26 上与重新设计的 NSColorWell 不兼容，令**整个 General 面板**合成为白位图。修复 = `ComboColorWell.drawRect:` 在 `majorVersion >= 26` 时交回 `[super drawRect:]`（仅 1 文件 ~8 行，不动 xib/outlet/binding）。**§5 的方案 B（外科/完整版）不再需要**。详见计划文档「阶段 1 执行结果」。§8 待实测点 #4「新建控件正常、xib 控件反色」的机制由此获解释：并非「所有 xib 控件」，而是特定自定义子类 `ComboColorWell` 的自定义绘制路径。

## 1. 问题

在 macOS 26 (Tahoe) 上打开 MacGesture 的偏好窗口，工具栏正常，但**内容区大面积渲染成与系统外观反相的纯色**：深色模式白底、浅色模式黑底。文字用动态系统色（`labelColor` 等）跟随系统外观，于是「白字白底 / 黑字黑底」而不可见，控件也大片消失。

后果：偏好窗口在 macOS 26 上不可用，并**阻塞 PR #8 的人工 GUI 验收**（看不见按钮标题就无法验证「重置前确认框」等）。

## 2. 根因（已实测确认，非推断）

用 lldb 挂真机进程 + `screencapture` 取真实合成画面，逐一确认：

1. 所有视图 `effectiveAppearance` 都是 `DarkAqua`、`windowBackgroundColor` 正确解析为深色——**外观是对的，渲染是错的**。
2. macOS 26 把 `NSBox` 换成 SwiftUI 绘制（视图树出现 `_NSCoreHostingView<AppKitBoxView>`）。
3. **决定性对照**：同一进程、同一 macOS 26 下，**代码全新创建的 `NSWindow` + `NSButton` + `NSTextField` 渲染完全正常**；但把**从 xib 加载的遗留面板视图**放进全新窗口，就全白。→ **病根在 xib 序列化的遗留视图，不在窗口容器。**
4. 运行时改属性（`backgroundColor`、隐藏 SwiftUI 盒子外壳、`NSBoxCustom`+`fillColor`、清 `layer.contents`、切 `appearance`）**全部无效**。
5. 补充观察：在原 xib 位置**不动**时，盒子外控件渲染正常、只有盒子内变白；一旦**重 parent / 重布局**遗留视图（搬进新窗口、或 de-box），则整片变白。→ 猜测存在两层问题：盒子的 SwiftUI 承载，以及「重布局遗留归档视图触发全白」。此机制**未完全查清**，作为待验点（见 §7）。

两个 SDK 构建都复现，**与构建 SDK 无关**（已实测 Xcode 16.4/SDK 15.5 与 Xcode 26.6/SDK 26.5 均白）——因此「换 SDK 重编」不是解。

## 3. 已排除 / 已调研的路径（一手来源见议题 #11 的调研评论）

- **无官方一行解**：Apple macOS 26.0–26.6 全部 Release Notes 的 AppKit 小节均无本症状的 Known/Resolved Issue。
- **重存 xib（`ibtool --upgrade`）——放弃**：无任何「重存修好 Tahoe 渲染」的先例；且 `FB18835363` 证明用 Xcode 26 打开/重存**无 Auto Layout 的老式 struts-and-springs xib**（本项目的 `Preferences.xib` 大概率正是）会引入控件错位回归。低收益 + 有实锤风险。
- **`wantsUpdateLayer=false`——无关**：一手案例证实它只修 NSBox 的打印/PDF 导出，不修屏显反色。
- **换旧 SDK 门控——否**：已实测两个 SDK 都白。
- **社区共识**：所有一手案例的应对都是「局部重建/替换受影响的老 nib 控件」，无一是「设个开关整体解决」；WWDC25 Session 310 的官方指引也是迁移/替换。

## 4. 目标与非目标

**目标**
- 偏好窗口在 macOS 26（深/浅两种模式）正常渲染：背景、控件、文字均可见。
- 保留现有全部行为、控件、四语言文案、37 个 IBOutlet、31 个 IBAction。
- 修复**版本门控**：`operatingSystemVersion.majorVersion >= 26` 才生效，老系统（部署目标 10.13）代码路径一行不动。
- 不依赖路线图 P1-2（抬升最低系统），可独立提前落地。

**非目标**
- 不重新设计 UI 外观（不是 modernization）。
- 不修其他面板的功能性 bug。
- 不做签名/公证/发布相关改动。

## 5. 方案与分阶段计划

整体策略：**便宜的先试，确定形态后再投入重建。** 每一步用 `screencapture` 自查管线判定（已验证可用），最后由人工做功能验收。

### 阶段 0 — 便宜 spike 先行（按成本排序，带决策门）

**Spike 0-审计**：在 macOS 26 上逐一打开全部 5 个面板（General / Gestures / Filters / AppleScript / About），`screencapture` 记录哪些真的渲染错乱。**只重建真坏的面板。**（当前只确认 General 坏。）

**Spike 0a — `UIDesignRequiresCompatibility`**（~5 分钟）
- 在 `MacGesture-Info.plist` 加 `UIDesignRequiresCompatibility = YES`，编译、运行、`screencapture` 自查。
- 判定：
  - 渲染正常**且**布局未坏 → 采纳为**临时解**，附带文档标注「过渡开关，针对 SDK 27 构建即失效，需在升级 SDK 前复查」，并开 issue 追踪。计划到此可提前结束。
  - 无效 / 破坏布局 → 丢弃该键，进 0b。
- 依据：官方文档列 macOS 为受支持平台、有一手案例证明它对纯 AppKit app 改变渲染路径；但**无证据证明它修颜色反相**——所以是「值得一试的候选」，不是「已证实的解」。

**Spike 0b — 界定方案 B 的爆炸半径**（~15 分钟）
- 取一个「盒子外、当前渲染正常」的**现有 xib 控件**，重新 parent 到一个新建 `NSView`，`screencapture` 看它是否变白。
- 判定：
  - 仍正常 → 现有控件可被安全搬动 → 方案 **B-外科版**（只换 NSBox 容器、保留控件）。
  - 变白 → 现有控件搬动即中招 → 方案 **B-完整版**（全新重建控件）。
- 依据：§2 第 3、5 点显示「整个面板搬进新窗口 / de-box」会全白，但那用的是**整个面板**，未隔离到单个控件；此 spike 才能定 B 的形态。

### 阶段 1 — 方案 B（重建受影响视图），形态由 0b 决定

**共同架构**
- 新增一个版本门控的修复入口 `-mg_repairMacOS26PrefsRenderingIfNeeded`，在 `AppPrefsWindowController` 的 `setupToolbar`（`addView:` 之前）调用；`if (majorVersion < 26) return;`。
- 老系统走原 xib 路径，**xib 保持为唯一布局真源**，不动。
- 重建时**读取已加载视图的现有 `frame`/`autoresizingMask` 来定位与复制**，不硬编码坐标（绕开 `FB18835363` 类错位风险）。

**B-外科版**（首选，若 0b 允许）
- 对每个受影响面板递归查找 `NSBox`，替换为同 `frame`/`autoresizingMask` 的普通 `NSView`；把盒子的 `contentView`（或其子控件）移入；用普通 `NSTextField` 标签复现盒子标题。
- outlet/action 全部原样保留（控件对象未变）。
- 单元边界：`-mg_replaceBoxesIn:(NSView *)root`（纯视图变换，可独立理解）。

**B-完整版**（兜底，若 0b 要求）
- 对受影响面板，用代码全新创建 `NSView` + 控件，逐一重新接上对应 outlet/action、复现绑定与文案。
- 单元边界：每个面板一个 builder 方法（`-mg_buildGeneralPanel` 等），各自独立。
- 明确承认这是较大工作量，是最后手段。

## 6. 验证策略

- **渲染验证（每步）**：`screencapture -l<windowNumber>` 取真实合成画面 → 自查（不用 `cacheDisplayInRect`，它不捕获 `layer.backgroundColor`，会误导）。深色**和**浅色两种模式都要过。
- **功能验证（人工）**：由维护者真机点一遍——每个面板的控件可点、状态正确、四语言切换正常、重置/导入等关键 IBAction 行为不变。
- **回归验证（老系统）**：因门控在 macOS 26+，理论上老系统不受影响；条件允许时在 <26 的机器或 CI 上确认 xib 路径未变。
- **说明**：渲染 bug 无法 TDD，验证是实证式（截图 + 人工），spec 不假装能自动化断言像素正确。

## 7. 风险与缓解

| # | 风险 | 缓解 |
|---|---|---|
| R1 | 移动现有控件也变白 → 逼上 B-完整版（大工程） | 0b 先验，把不确定变确定后再定形态 |
| R2 | 程序化定位与 xib struts-and-springs 位置对不齐 | 读现有 frame 定位，不硬编码 |
| R3 | 两条路径（<26 走 xib、≥26 走 transform）漂移 | transform 保持最小、注释清楚；xib 仍是单一真源 |
| R4 | 未来 macOS 更新可能修掉该渲染 bug，使 workaround 冗余/冲突 | 版本门控，届时复查；开 issue 追踪 |
| R5 | 0a 的 `UIDesignRequiresCompatibility` 生效则是过渡开关（SDK 27 失效） | 文档标注 + issue 追踪，SDK 27 前复查 |
| R6 | 机制未完全查清（§2 第 5 点「重布局即全白」） | 阶段 0 的 spike 以「行为可复现」为准来定形态，不依赖机制解释 |

## 8. 待实测才能定论的点（勿把推断当结论）

1. `UIDesignRequiresCompatibility=YES` 对本症状是否有效（0a）。
2. 现有控件重 parent 后是否仍正常，即 B 的形态（0b）。
3. 除 General 外，其余 4 个面板是否也坏、坏到什么程度（0-审计）。
4. 「新建控件正常、xib 控件反色」的确切机制——目前**未解释清楚**，不作为设计依据，只按可复现行为推进。

## 9. 交付物

- 阶段 0：三份 spike 结论（截图 + 判定），据此选定 0a 采纳 / B-外科 / B-完整。
- 阶段 1：代码改动（`AppPrefsWindowController` + 可能的 Info.plist），走 PR 合入 `develop`，CI 编译通过，人工 GUI 验收通过。
- 关闭/更新议题 #11；PR #8 的 GUI 验收解除阻塞。
