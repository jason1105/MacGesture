
# MacGesture

![logo](https://raw.githubusercontent.com/MacGesture/MacGesture/master/logo.png)

macOS 上可自定义的全局鼠标手势工具。

**[English](README.md)**

## 关于这个分支

这是 [MacGesture/MacGesture](https://github.com/MacGesture/MacGesture)（作者
[CodeFalling](https://github.com/xcodebuild)）的社区维护分支。上游仓库自 2023 年 6 月
起再无提交，在较新的 macOS 上已无法正常使用。

这个分支的目的只有一个：让 MacGesture 在新版 macOS 上继续可用。它**不是**官方版本，
也未获得原作者背书。许可证同为 GPL-3.0，手势引擎与配置格式均未改动，只是有人在维护。

### 这个分支在 macOS 26 上修了什么

| macOS 26 上的表现 | 修复于 |
| --- | --- |
| 偏好窗口几乎看不清——控件与文字发白 | [#11](https://github.com/jason1105/MacGesture/issues/11) |
| 尚未授予辅助功能权限时，菜单栏完全没有图标，手势也始终不工作 | [#24](https://github.com/jason1105/MacGesture/issues/24) |
| 授予辅助功能权限后毫无反应，必须退出重开才生效 | [#26](https://github.com/jason1105/MacGesture/issues/26) |
| 编辑 AppleScript 条目时切换偏好面板会崩溃 | [#27](https://github.com/jason1105/MacGesture/issues/27) |
| 偏好窗口关掉之后再也没有入口打开——现在双击 app 图标即可重新打开 | [#22](https://github.com/jason1105/MacGesture/pull/22) |

另外还迁移了 macOS 已废弃或移除的 API：`NSUserNotification` → `UserNotifications`、
`LSSharedFileList` 登录项 → `SMAppService`、keyed archiving → secure coding。
最低支持版本已提升至 macOS 13。

已在 macOS 26.5.2 上验证。CI 同时针对 macOS 15 / Xcode 16.4 与
macOS 26 / Xcode 26.6 构建。

## 安装

从本分支的 [Releases](https://github.com/jason1105/MacGesture/releases) 页面下载。

> **提醒：目前的构建是 ad-hoc 签名，未经过公证。**
>
> 首次打开时 macOS 会拒绝运行。绕过方法：打开**系统设置 → 隐私与安全性**，
> 滑到底部，在 MacGesture 那一条旁边点**仍要打开**。
>
> 还有一个后果值得先知道：由于每次构建签名都会变化，macOS 会把每个更新当作
> 另一个 app，从而**静默作废辅助功能授权**。此时系统设置里的开关看起来仍是开着的，
> 但 app 实际上并未被信任。如果更新后手势失效，执行：
>
> ```shell
> tccutil reset Accessibility com.codefalling.MacGesture
> ```
>
> 然后重新启动 MacGesture 并再次授权。**把现有开关关掉再打开是没用的**——
> 必须把那条陈旧记录整条删掉。
>
> 正式的 Developer ID 签名与公证记录在
> [#28](https://github.com/jason1105/MacGesture/issues/28)，做完后本节即可删除。

Homebrew 的 `macgesture` cask 目前安装的仍是**上游**的 3.2.0 版本，不是本分支。

### 首次启动

MacGesture 需要辅助功能权限才能读取鼠标事件。首次启动时它会请求该权限，
并提供一个直达对应系统设置面板的按钮。**授权后手势立即生效，无需重启。**

## 尚未解决的问题

以下问题目前仍然存在，先说清楚免得你意外：

- 多显示器下偏好窗口表现不佳，取色器和字体面板可能出现在错误的屏幕上
  （[#13](https://github.com/jason1105/MacGesture/issues/13)）
- ad-hoc 签名的构建上通知可能不弹出
  （[#23](https://github.com/jason1105/MacGesture/issues/23)）
- 权限弹窗文案仅有英文
  （[#17](https://github.com/jason1105/MacGesture/issues/17)）

此外还有一些自上游继承下来的固有行为，见下方「固有问题」一节。

## 功能

- 全局鼠标手势识别
- 手势触发自定义快捷键
- 基于 bundle identifier 的应用过滤

## 手势写法

| 手势 | 记号 |
| ------------ | :-----: |
| 向左移动 | `L` |
| 向上移动 | `U` |
| 向右移动 | `R` |
| 向下移动 | `D` |
| 左键点击 | `Z` |
| 滚轮向上 | `u` |
| 滚轮向下 | `d` |

手势支持通配符匹配（`?` 与 `*`），**第一条匹配上的规则生效**。

`Z` 取自「左」的拼音首字母。之所以不用 `L`，是为了把**点击左键**和
**向左拖动鼠标**区分开。

滚轮方向会受系统设置影响（「自然」滚动方向），也可能被某些系统增强工具改变
（例如 Karabiner 的 Reverse Vertical Scrolling）。

## 固有问题

### 部分 Java 应用中右键无效

一个不完美的解决办法：以 WebStorm 为例，打开 Preferences → KeyMap，
把「Show Context Menu」的快捷键设为 `Button3 Click`。

### 某些系统级快捷键无法绑定到规则

原因：macOS 会先于 MacGesture 响应系统级快捷键。

解决办法：先在系统设置里停用该快捷键，在 MacGesture 中完成绑定，再重新启用。

注意：有些快捷键即便这样也仍然无效。遇到时可以：

- 换成别的组合（例如 `⌃0`、`⌃9`）
- 勾选「Invert Fn When Control Is Pressed」选项

## 使用技巧

### 基础手势

下面这张表覆盖了最常见的用法：

| 手势 | 过滤条件 | 动作 | 说明 | ⚡️ |
| :-----: | :----------------------- | :------: | :------: | :-: |
| `D` | `*safari`&#124;`*chrome` | ⌘T | 新建标签页 | – |
| `DR` | `*safari`&#124;`*chrome` | ⌘W | 关闭标签页 | – |

设置好之后：

- 按住右键、向下拖动、松开 → 在当前浏览器窗口新建标签页
- 按住右键、先向下再向右拖动、松开 → 关闭当前标签页

### 滚轮手势

勾选规则行末尾的「⚡️」，可以让手势在**每次匹配时**都触发，
这样不松开右键也能连续切换标签页：

| 手势 | 过滤条件 | 动作 | 说明 | ⚡️ |
| :-----: | :----------------------- | :------: | :------: | :-: |
| `U*u` | `*safari`&#124;`*chrome` | ⇧⌘\[ | 上一个标签页 | ☑️ |
| `U*d` | `*safari`&#124;`*chrome` | ⇧⌘\] | 下一个标签页 | ☑️ |

于是：按住右键向上拖动后，每滚一格滚轮就切换一次标签页。

### 导出与导入配置

**推荐做法**：使用 **General** 面板里的「Import」「Export」按钮。

**极客做法**：在旧电脑上执行

```shell
defaults read com.codefalling.MacGesture backup.plist
```

把生成的文件拷到新电脑，然后执行

```shell
defaults import com.codefalling.MacGesture backup.plist
```

配置应当能完整迁移。若有问题请提 issue。

### 在规则中排除某个应用

在应用名前加 `!` 即可排除（同样支持通配符）。例如原规则：

| 手势 | 过滤条件 | 动作 | 说明 | ⚡️ |
| :-----: | :----------------- | :------: | :------: | :-: |
| `U*d` | `*` | ⇧⌘\] | 下一个标签页 | ☑️ |

要排除 Safari，改成：

| 手势 | 过滤条件 | 动作 | 说明 | ⚡️ |
| :-----: | :------------------ | :------: | :------: | :-: |
| `U*d` | `*`&#124;`!*safari` | ⇧⌘\] | 下一个标签页 | ☑️ |

## 发现 Bug？

欢迎在[本分支](https://github.com/jason1105/MacGesture/issues)提 issue 👍

如果该问题在原版上同样存在，也不妨同时报给
[上游](https://github.com/MacGesture/MacGesture/issues)，
万一日后有人接手。

## 贡献者

原项目：

- [CodeFalling](https://github.com/xcodebuild) —— 原作者
- [username0x0a](https://github.com/username0x0a) —— 维护者
- [jiegec](https://github.com/jiegec)
- [zhangciwu](https://github.com/zhangciwu)

本分支：

- [jason1105](https://github.com/jason1105) —— macOS 26 适配

## 许可证

本项目基于 [GNU General Public License v3](https://en.wikipedia.org/wiki/GNU_General_Public_License) 发布。

本分支沿用相同许可证，保持完全开源。原作品的版权与署名归上述作者所有。

应用图标及其他图标由 [username0x0a](https://github.com/username0x0a) 设计。
