# 设计：偏好数据归档迁移到 Secure Coding（P3-3）

- 状态：**待评审**（设计阶段，未动代码）
- 日期：2026-08-26
- 路线图：议题 #1 的 **P3-3**「迁移到 secure coding 并做偏好数据迁移」
- 目标定性：把已弃用的 `NSKeyedUnarchiver unarchiveObjectWithData:` / `NSKeyedArchiver archivedDataWithRootObject:`（macOS 10.14 弃用，非安全）迁移到 secure coding API，**且不丢老用户的手势规则 / 颜色 / AppleScript 数据**。

## 1. 问题

项目多处用 `+[NSKeyedUnarchiver unarchiveObjectWithData:]` 和 `+[NSKeyedArchiver archivedDataWithRootObject:]`（10.14 弃用），以及 xib 里的 `NSKeyedUnarchiveFromData` value transformer（同样非安全、macOS 12 起有安全替代）。它们解档时不校验类，属不安全反序列化。P3 要求逐项迁移到 secure coding。

## 2. 现状清点（已核实源码，非推断）

| # | 数据 | 存储 | 归档/解档点 | 对象图里的类 |
|---|---|---|---|---|
| A | **5 个颜色**（line/preview/previewBg/note/noteBg） | `NSUserDefaults`，键 `lineColor` 等 | 代码：`MGOptionsDefine.m`（5 对 get/set）；**并且** xib 里 5 个色井绑定 `values.lineColor` 等经 `NSKeyedUnarchiveFromData` transformer | `NSColor` |
| B | **手势规则**（用户核心数据） | `NSUserDefaults` | `RulesList.m:346/352`（`nsData`/`initWithNsData:`） | `NSArray`/`NSMutableArray` → `NSMutableDictionary` → `NSString`/`NSNumber` |
| C | **AppleScripts** | `NSUserDefaults` 键 `appleScripts` | `AppleScriptsList.m:33/43` | 同 B（数组→字典→NSString） |
| D | 拖拽行索引 | 拖拽 pasteboard（**临时，不持久**） | `AppPrefsWindowController.m:885/905` | `NSIndexSet` |

**决定性结论：全是标准 Foundation 类，零自定义类。** `NSColor` / `NSArray` / `NSDictionary` / `NSString` / `NSNumber` / `NSIndexSet` 本就实现 `NSSecureCoding`。因此**无需给任何类补 `NSSecureCoding` 适配**——这把本项从路线图担心的「高风险」降到「中等」。

**已核实**：A 的色井绑定键（`values.lineColor` 等）与 `MGOptionsDefine` 的 `OPTIONS_*_COLOR_ID`（`lineColor` 等）**是同一批 defaults 键**——UI 绑定与渲染代码共用同一存储，两条路径必须一起迁且保持格式兼容。

## 3. 兼容性分析（旧数据能否被安全 API 读回）

Secure 与非 secure 的 keyed-archive **是同一种归档格式**；secure 只是在解档时按 allowlist 校验类。所以只要：(1) 对象图里的类都实现 `NSSecureCoding`（本项全满足），(2) 解档时把这些类都列进 allowlist，**旧的非安全归档数据就能被 secure API 完整读回，不丢数据**。

**已实证**（在真机运行进程里用 lldb 验证，2026-08-26）：
- `NSColor` 用旧 `archivedDataWithRootObject:` 归档 → 用 `unarchivedObjectOfClass:[NSColor class] fromData:error:` 读回 → **成功，颜色值完整（`0.1 0.2 0.3 1`），无 error**。
- `数组[字典{NSString,NSNumber}]` 同理（标准 plist 类型比 NSColor 更简单，属文档保证行为；真实旧数据回归见 §6 测试计划）。

## 4. 迁移设计

### 4.1 统一 helper（收敛样板，降低 allowlist 漏项风险）

在 `Helpers/utils.{h,m}` 加两个薄封装，全项目共用，避免各处手写 allowlist 出错：

```objc
// 写：secure 归档；失败返回 nil（调用方保留原有兜底）
NSData *MGArchive(id<NSSecureCoding> object);
// 读：secure 解档，allowlist = classes；失败/nil 返回 nil
id MGUnarchive(NSData *data, NSSet<Class> *classes);
```

- `MGArchive` = `+[NSKeyedArchiver archivedDataWithRootObject:requiringSecureCoding:YES error:]`。
- `MGUnarchive` = `+[NSKeyedUnarchiver unarchivedObjectOfClasses:fromData:error:]`，`data==nil` 直接返回 nil，失败记 `NSLog` 但不抛。

### 4.2 各处改法

- **A 颜色（代码侧）**：`MGOptionsDefine` 的 set 用 `MGArchive(color)`；get 用 `MGUnarchive(data, [NSSet setWithObject:NSColor.class])`。get 已有 `?: [self defaultColor]` 兜底 → 解档失败退默认色，不崩。
- **A 颜色（xib 绑定侧）**：新增 `NSSecureUnarchiveFromDataTransformer` 子类 `MGColorValueTransformer`，`+allowedTopLevelClasses` 返回 `@[NSColor.class]`（**默认安全 transformer 不含 NSColor，必须自定义**）；在**极早期**（`main.m` 里 `NSApplicationMain` 之前，或 `+[AppDelegate initialize]`，**须在 nib 加载/绑定解析之前**）用 `+[NSValueTransformer setValueTransformer:forName:]` 注册；把 5 个色井绑定的 `NSValueTransformerName` 由 `NSKeyedUnarchiveFromData` 改为 `MGColorValueTransformer`。该 transformer 的 reverse（写）也用 secure 归档，双向安全，且与代码侧格式互通。
- **B 规则**：`RulesList` 的 `nsData` 用 `MGArchive`；`initWithNsData:` 用 `MGUnarchive(data, RULES_CLASSES)`，其中 `RULES_CLASSES = {NSArray, NSMutableArray, NSDictionary, NSMutableDictionary, NSString, NSNumber}`。解档 nil 时退空数组（保留现有语义）。
- **C AppleScripts**：同 B（同一批类）。`AppleScriptsList` 已有 `if (list==nil) 空数组` 兜底。
- **D 拖拽索引**：`MGArchive(rowIndexes)` / `MGUnarchive(rowData, [NSSet setWithObject:NSIndexSet.class])`。临时数据、低风险。

### 4.3 不需要的东西

- **不需要数据迁移标志/一次性转换**：归档格式不变（还是 keyed archive），旧数据原地就能被 secure API 读；写出的新数据老代码也能读（§6 反向兼容测试）。因此**无需**「读旧→转新→标记已迁移」这类迁移逻辑，风险面更小。
- **不需要版本门控**：全部 secure API 在 macOS 13+ 可用（本项目最低已 13.0，见 #15）。

## 5. 数据丢失风险分析（本项最需盯的）

| 风险 | 说明 | 缓解 |
|---|---|---|
| **R1（高）allowlist 漏类** | 若某解档 allowlist 少列了对象图里出现的类，`unarchivedObjectOfClasses:` 返回 nil → 该项数据「消失」（规则清空/颜色回默认） | allowlist 集中在 helper 调用点、按 §2 清点穷尽列全；§6 用**真实旧数据**回归，逐条比对数量与字段 |
| R2（中）xib transformer 注册时机 | 若 `MGColorValueTransformer` 注册晚于绑定解析，色井绑定拿不到 transformer → 报错/颜色失效 | 在 nib 加载前注册（`main` 或 `+initialize`）；§6 验证色井正常显示/可改 |
| R3（低）nil/损坏数据 | 解档失败返回 nil | helper 统一兜底；各 get 已有默认值回退，不崩 |
| R4（低）反向兼容 | 新写的 secure 数据若老版本读不了，回滚时丢数据 | §6 测反向（secure 归档 → 非 secure 解档）；keyed 格式相同，预期可读 |

**本项不是「高风险」的真正原因**：没有自定义类需要改 `initWithCoder:`/`encodeWithCoder:`（改这些才是数据迁移的经典雷区）；格式不变、无需一次性转换。风险收敛为「allowlist 是否列全」这一个可测点。

## 6. 测试计划（用真实旧数据，防丢失）

1. **真实旧数据取样**：在装有 3.2.0 的机器上配几条规则（含 shortcut 与 AppleScript 两种 action）、改 5 个颜色、加 2 个 AppleScript，`defaults export com.codefalling.MacGesture /tmp/old-prefs.plist` 存档作为夹具。
2. **回归（核心）**：用夹具 `defaults import` 到测试域 → 跑迁移后构建 → 逐条核对：规则**条数**、每条的 direction/filter/note/action/keycode/flag/appleScriptId/enabled/triggerOnEveryMatch **逐字段相等**；5 个颜色 RGBA 相等；AppleScript 条数与 title/script/id 相等。**任一不等即视为数据丢失，阻断合入。**
3. **单元级 round-trip**（可加轻量 test）：数组[字典] 与 NSColor 的 旧归档→secure 解档、secure 归档→secure 解档、secure 归档→旧解档（反向）三向断言相等。
4. **边界**：空/缺失键（首次运行，defaults 无值）→ 退默认、不崩；故意塞损坏 NSData → 退默认、不崩。
5. **色井 UI（真机）**：5 个色井正常显示当前色、点开可改、改完渲染跟随（P4 渲染已修）。
6. **真机验收**：随 P2 beta 或本地正式安装做（与 #1 P2 清单一致）。

## 7. 落地方式（建议）

- **一个 PR**（P3-3）：helper + A/B/C/D 四处 + xib transformer + 注册；附 §6 的单元 round-trip test（若加）。改动集中、可一次评审。
- 或按数据类型拆 2 个 PR（颜色一组、规则/脚本一组）——若想更小粒度评审。**倾向单 PR**，因为 helper 是共享前置、拆开反而重复。
- CI 双档编译兜底；`claude[bot]` 评审；§6.2 真实旧数据回归是**合入前必过**的人工/脚本验证。

## 8. 待你拍板的点

1. **落地粒度**：单 PR（推荐）还是按数据类型拆 2 个？
2. **是否加单元测试**：`MacGestureTests` 现仅一个 2013 年的 `XCTFail` 占位、且 CI 未开 test（#1 记载）。§6.3 的 round-trip 断言值得加，但要顺带把 test target 跑起来（另立小事）。**建议**：本 PR 先加一个独立的、能过的 round-trip test 文件，但**不**在本轮开 CI 的 test action（避免踩那个占位失败）——你也可以选择先不加、只靠 §6.2 的真实数据回归。
3. **真实旧数据夹具**：你手上有没有现成的 3.2.0 带规则/颜色的 `defaults export`？有的话给我，回归更真；没有我构造一份近似夹具。

> 本文档只做设计，未改任何代码。评审通过后再进入实现。
