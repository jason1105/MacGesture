# P2 发布链路 实施方案

- 状态：**待你完成密钥步骤 + 评审**（本文档不含私钥，也不会替你生成/上传密钥）
- 路线图：议题 #1 的 **P2**（P2-1/2/3）
- 目标：从**本 fork 独立**用 Sparkle 发布 `3.3.0`，自动更新可用；**本轮不做 Developer ID 签名/公证**（ad-hoc，接受 Gatekeeper 首次放行摩擦，CI 预留签名接口）。

## 安全边界（谁做什么）

| 步骤 | 谁做 | 原因 |
|---|---|---|
| 生成 Sparkle EdDSA 密钥对 | **只能你** | 私钥不可经我手 |
| 把**私钥**存进 GitHub Secret `SPARKLE_ED_PRIVATE_KEY` | **只能你** | Secret 写入是你账户的安全操作 |
| 把**公钥**字符串贴给我 | 你 → 我 | 公钥非敏感，可提交进 Info.plist |
| 改 `SUPublicEDKey`/`SUFeedURL`、bump 版本、写发布 CI、AppCast 骨架 | 我 | 纯代码/配置，无密钥 |
| 打 tag 触发发布、验收 beta | 你（或授权我打 tag） | 发布是不可逆外发动作，默认你来 |

---

## 第一步（你做）：生成密钥 + 存 Secret

Sparkle 2.9.6 的工具已随 SPM 拉到本地（也可从 Sparkle release 下载）：

```bash
# 路径（DerivedData 里，构建过就有；换成你机器上实际的 DerivedData 亦可）
GK="/tmp/mg-dd-develop/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"

# 1) 首次生成：私钥存进你的「登录」钥匙串，终端打印【公钥】(base64)
"$GK"
#   → 记下它打印的 public key，例如： SUPublicEDKey 应设为这一串

# 2) 导出私钥（供 CI 签名用），存成文件
"$GK" -x /tmp/sparkle_private_key.pem
#   → /tmp/sparkle_private_key.pem 的【内容】就是要放进 Secret 的值
```

3) 在 GitHub 仓库 `Settings → Secrets and variables → Actions → New repository secret`：
   - Name：`SPARKLE_ED_PRIVATE_KEY`
   - Secret：粘贴 `/tmp/sparkle_private_key.pem` 的全部内容
4) **立刻删本地导出**：`rm -f /tmp/sparkle_private_key.pem`（私钥留在钥匙串即可，导出文件用完即删）。
5) 把**公钥字符串**贴给我（非敏感）。

> ⚠️ 不要把私钥贴进聊天、commit、或任何回写。只贴公钥。

---

## 第二步（我做）：配置改动

拿到你的公钥后：

- `MacGesture-Info.plist`：
  - `SUPublicEDKey` → 你的新公钥（替换上游的 `luFpvg…`）
  - `SUFeedURL` → 本 fork 的 AppCast（**决策见下**）
- `Config.xcconfig`：`APP_VERSION 3.2.0 → 3.3.0`，`APP_BUILD` 递增
- （可选）`SUEnableAutomaticChecks` 等 Sparkle 行为键按需补

## 第三步（我做）：发布 CI（`.github/workflows/release.yml`，或扩展 build.yml）

- 触发：push tag，形如 `3.3.0`（**无 `v` 前缀**，与既有下载 URL 一致）。
- 步骤（**全程 `if: ${{ secrets.SPARKLE_ED_PRIVATE_KEY != '' }}` 包裹，Secret 未配置时整段跳过、CI 不红**）：
  1. Release 配置构建（复用 build.yml 的 Xcode 26.6 档）
  2. 打包：`ditto -c -k --sequesterRsrc --keepParent MacGesture.app MacGesture-<ver>.zip`
  3. 签名：`sign_update MacGesture-<ver>.zip`（用 Secret 私钥）→ 得 `sparkle:edSignature` 与长度
  4. 建 GitHub Release（tag=版本），上传 zip
  5. 生成/更新 `AppCast.xml` 条目（version、url、edSignature、length、minimumSystemVersion=13.0、releaseNotesLink 指向 gh-pages CHANGELOG），提交到 feed 位置
- **签名/公证步骤预留**：用 `if: secrets.DEVELOPER_ID_* != ''` 包裹，将来配了证书自动生效（本轮为空、跳过）。

## 待你拍板的决策

1. **AppCast 托管位置 / `SUFeedURL`**：
   - A（推荐，仿上游）：`https://raw.githubusercontent.com/jason1105/MacGesture/master/AppCast.xml` —— 发布 CI 把 AppCast 提交到 `master`；
   - B：放 `gh-pages`（已托管 CHANGELOG），feed 指 gh-pages 的 raw/pages URL。
2. **打 tag 谁来**：你手动打 `3.3.0` 触发发布；还是先发 `3.3.0-beta.1` 走通流程（推荐先 beta）。
3. **版本号**：确认 `3.3.0`（build 号从 198 递增到多少，或用 CI 的 run number）。

## 验收（P2-3，真机，含推迟项）

发 `3.3.0-beta.1`/`beta.2`，真机验（#1 P2 清单 + 本会话推迟的 ②③）：
- 首次下载安装 Gatekeeper 放行路径可接受；
- 辅助功能授权后手势正常；
- **beta.1 → beta.2 自动更新后，辅助功能权限是否保留**（#1 风险1，ad-hoc 关键验证点）；
- App Translocation 提示正确；
- **P3-1 通知实际弹出**、**P3-2 登录项实际注册**（本会话 ②③ 推迟项）。

> CI 无法验证签名/Gatekeeper/TCC（#1 风险5：runner SIP=disabled 且无 GUI）——这些只能真机人工。

## 未在本轮范围
Developer ID 签名与公证（待评估购买会员，CI 已预留接口）；Homebrew cask。
