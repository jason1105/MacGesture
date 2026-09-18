#!/bin/sh
#
# 生成 app 内「关于」面板显示的 README.html。
#
# 来源是 docs/AppHelp.md，而不是仓库根目录的 README.md —— 后者是面向仓库访客的
# 落地页，包含安装步骤、Gatekeeper 放行说明、分支来历等内容，对「已经把 app 装好
# 并打开了偏好设置」的用户是纯噪音。两者各自维护。
#
# 正文会被套进 docs/AppHelp.template.html（内含「关于」面板依赖的那份 CSS）。
# 早先本脚本写的是 `markdown < README.md > README.html`，直接覆盖整个文件——
# 真跑一次会把那段手工维护的样式全部冲掉，等于把「关于」面板变成无样式裸文本。
#
# 用法：sh gen.sh

set -eu

SRC="docs/AppHelp.md"
TEMPLATE="docs/AppHelp.template.html"
OUT="MacGesture/Resources/Base.lproj/README.html"

for f in "$SRC" "$TEMPLATE"; do
    [ -f "$f" ] || { echo "gen.sh: 缺少 $f" >&2; exit 1; }
done

# Markdown 转换器：优先用原先约定的 markdown(1)，没有则退回 pandoc。
# 两者都没有时明确失败——不能悄无声息地产出一个不完整的 README.html。
if command -v markdown >/dev/null 2>&1; then
    CONVERT="markdown"
elif command -v pandoc >/dev/null 2>&1; then
    CONVERT="pandoc --from=gfm --to=html"
else
    echo "gen.sh: 未找到 markdown(1) 或 pandoc，无法生成 HTML。" >&2
    echo "        安装其一即可，例如：brew install pandoc" >&2
    exit 1
fi

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

$CONVERT < "$SRC" > "$BODY"
[ -s "$BODY" ] || { echo "gen.sh: 转换结果为空，已中止" >&2; exit 1; }

# 用 awk 而非 sed 做替换：正文里含 & 和 / 等会被 sed 替换语义吃掉的字符。
awk -v bodyfile="$BODY" '
    /^<!-- CONTENT -->$/ {
        while ((getline line < bodyfile) > 0) print line
        next
    }
    { print }
' "$TEMPLATE" > "$OUT"

cp logo.png ./MacGesture/Resources

echo "gen.sh: 已用 $CONVERT 生成 ${OUT} , 共 $(wc -l < "$OUT") 行"
