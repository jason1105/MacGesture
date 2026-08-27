
# MacGesture

![logo](https://raw.githubusercontent.com/MacGesture/MacGesture/master/logo.png)

Configurable global mouse gestures for macOS.

**[中文说明](README.zh-CN.md)**

> You can read this `README` file in the **About** section of the app's Preferences.

## About this fork

This is a community-maintained fork of [MacGesture/MacGesture](https://github.com/MacGesture/MacGesture)
by [CodeFalling](https://github.com/xcodebuild). The upstream repository has had no
commits since June 2023 and does not run on recent macOS releases without problems.

This fork exists to keep MacGesture working on modern macOS. It is **not** an official
release and is not endorsed by the original authors. Same GPL-3.0 licence, same
gesture engine, same preferences format — just maintained.

### What this fork fixes on macOS 26

| Symptom on macOS 26 | Fixed in |
| --- | --- |
| Preferences window renders nearly unreadable — controls and text washed out | [#11](https://github.com/jason1105/MacGesture/issues/11) |
| No menu bar icon at all, and gestures never work, when the Accessibility permission has not been granted yet | [#24](https://github.com/jason1105/MacGesture/issues/24) |
| Granting the Accessibility permission does nothing until the app is quit and reopened | [#26](https://github.com/jason1105/MacGesture/issues/26) |
| Crash while editing an AppleScript entry and switching preference panes | [#27](https://github.com/jason1105/MacGesture/issues/27) |
| No way back into Preferences once the window is closed — double-clicking the app now reopens it | [#22](https://github.com/jason1105/MacGesture/pull/22) |

Also migrated off APIs that macOS has deprecated or removed: `NSUserNotification` →
`UserNotifications`, `LSSharedFileList` login items → `SMAppService`, and keyed
archiving → secure coding. Minimum supported version is now macOS 13.

Verified on macOS 26.5.2. Continuous integration builds against both macOS 15 /
Xcode 16.4 and macOS 26 / Xcode 26.6.

## Installation

Download the latest build from this fork's
[Releases](https://github.com/jason1105/MacGesture/releases) page.

> **Heads-up: builds are currently ad-hoc signed, not notarised.**
>
> macOS will refuse to open the app on first launch. To get past it, open
> **System Settings → Privacy & Security**, scroll to the bottom, and click
> **Open Anyway** next to the MacGesture entry.
>
> There is a second consequence worth knowing about: because the signature changes
> on every build, macOS treats each update as a different app and **silently voids
> the Accessibility permission**. The toggle in System Settings still looks enabled,
> but the app is not actually trusted. If gestures stop working after an update, run:
>
> ```shell
> tccutil reset Accessibility com.codefalling.MacGesture
> ```
>
> then relaunch MacGesture and grant the permission again. Toggling the existing
> switch off and on does *not* work — the stale entry has to be removed.
>
> Proper Developer ID signing and notarisation are tracked in
> [#28](https://github.com/jason1105/MacGesture/issues/28); this section goes away
> once that lands.

The Homebrew cask `macgesture` still installs the **upstream** 3.2.0 build, not this
fork.

### First launch

MacGesture needs the Accessibility permission to read mouse events. On first launch it
will ask for it and offer to open the relevant System Settings pane directly. Once you
grant it, gestures activate immediately — no restart required.

## Still open in this fork

Things that are not fixed yet, listed here so they are not a surprise:

- Preferences window behaves poorly across multiple displays — colour and font panels
  can open on the wrong screen ([#13](https://github.com/jason1105/MacGesture/issues/13))
- Notifications may not appear on ad-hoc signed builds
  ([#23](https://github.com/jason1105/MacGesture/issues/23))
- Permission prompt strings are English-only
  ([#17](https://github.com/jason1105/MacGesture/issues/17))

Plus the long-standing behaviours inherited from upstream, described under
[Known Issues](#known-issues) below.

## Features

- Global mouse gestures recognition
- Configurable shortcut invocation by gesture
- App filtering based on bundle identifiers

## Gestures Format

| Gesture      | Acronym |
| ------------ | :-----: |
| Move Left    |   `L`   |
| Move Up      |   `U`   |
| Move Right   |   `R`   |
| Move Down    |   `D`   |
| Left Button  |   `Z`   |
| Wheel Up     |   `u`   |
| Wheel Dp     |   `d`   |

Gestures can contain wildcard matching (`?` and `*`).

The first rule matching will take effect.

`Z` is the acronym of pinyin of `左` which means “left” in English. So to distinguish _clicking the left mouse button_ from _dragging your mouse to the left_, we chose letter `Z`.

Wheel directions may vary according to system configuration (Natural scroll direction setting) or some system tweaks (Karabiner's Reverse Vertical Scrolling, for example).

## Known Issues

### Right click does not work in some Java applications

An imperfect fix:
Take WebStorm for example, open Preferences, then KeyMap, set the shortcut of “Show Context Menu” to `Button3 Click`.

### Cannot assign some system-wide shortcuts to rules

Reason:
macOS respond to system-wide shortcuts before MacGesture.

Fix:
Disable the shortcut first (for example in System Preferences → Keyboard → Shortcuts), then assign the shortcut in MacGesture, and re-enable the shortcut.

Caveats:
Some shortcuts still don't work with the fix above. When you are encountering this, here are two possible solutions:

- Change them to others (e.g. `⌃0`, `⌃9`).
- Tick “Invert Fn When Control Is Pressed” option.

## Tips

### Basic gestures

The following table covers probably the most basic scenario of usage:

| Gesture | Filter                   | Action   | Note     |  ⚡️  |
| :-----: | :----------------------- | :------: | :------: | :-: |
| `D`     | `*safari`&#124;`*chrome` |    ⌘T    | New Tab  |  –  |
| `DR`    | `*safari`&#124;`*chrome` |    ⌘W    | Close    |  –  |

By setting these rules, you can empower mouse gestures to open new and close currently focused tabs in Sarari and Chrome Browsers. Simply:

- press the right button, drag mouse down, and release
	- opens a new tab in the current browser window
- press the right button, drag mouse down, then to the right, and release
	- this will result in closing the currently focused tab in the active browser window

How neat! 🙌

### Mouse scroll gesture example

Now, to quickly cycle between the selected tabs even without releasing the right mouse button, you can set the gesture to be triggered on every match using the “⚡️” checkbox at the end of the Rule line.

So by defining the following rules:

| Gesture | Filter                   | Action   | Note     |  ⚡️  |
| :-----: | :----------------------- | :------: | :------: | :-: |
| `U*u`   | `*safari`&#124;`*chrome` |   ⇧⌘\[   | Prev Tab |  ☑️  |
| `U*d`   | `*safari`&#124;`*chrome` |   ⇧⌘\]   | Next Tab |  ☑️  |

you can simply:

- right click, drag mouse upwards, and every `u` (mouse wheel scroll up) triggers a **Prev Tab** action,
- right click, drag mouse upwards, and every `d` (mouse wheel scroll down) triggers a **Next Tab** action.

Switching between multiple tabs in the browser is now a piece of cake! 😎

### Exporting and importing MacGesture preferences

#### Recommended way

Use “Import” and “Export” buttons in the **General** Panel.

#### Geek-ish way

Open the _Terminal_ app, Do this in your old computer:

```shell
defaults read com.codefalling.MacGesture backup.plist
```

And then copy that file to your new computer, then:

```shell
defaults import com.codefalling.MacGesture backup.plist
```

All settings should be successfully brought over. If that's not the case please file an issue.

### Excluding an app in a certain rule

You can prepend `!`, then the app you want to exclude (still wildcard).

For example, the original one:

| Gesture | Filter             | Action   | Note     |  ⚡️  |
| :-----: | :----------------- | :------: | :------: | :-: |
| `U*d`   | `*`                |   ⇧⌘\]   | Next Tab |  ☑️  |

Then, in order to exclude Safari, change this to:

| Gesture | Filter              | Action   | Note     |  ⚡️  |
| :-----: | :------------------ | :------: | :------: | :-: |
| `U*d`   | `*`&#124;`!*safari` |   ⇧⌘\]   | Next Tab |  ☑️  |

Then you will experience the expected behaviour.

## Found a Bug?

Open [an issue on this fork](https://github.com/jason1105/MacGesture/issues) 👍

Bugs that also affect the original app are worth reporting
[upstream](https://github.com/MacGesture/MacGesture/issues) as well, in case it is
ever picked up again.

## Contributors

Original project:

- [CodeFalling](https://github.com/xcodebuild) – original author
- [username0x0a](https://github.com/username0x0a) – maintainer
- [jiegec](https://github.com/jiegec)
- [zhangciwu](https://github.com/zhangciwu)

This fork:

- [jason1105](https://github.com/jason1105) – macOS 26 compatibility work

## License

This project is made under the [GNU General Public License v3](https://en.wikipedia.org/wiki/GNU_General_Public_License).

This fork is distributed under the same licence and remains fully open source.
Copyright and attribution for the original work stay with the authors listed above.

App icon & other icons designed by [username0x0a](https://github.com/username0x0a).
