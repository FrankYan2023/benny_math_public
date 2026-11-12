#!/bin/bash
# 把仓库共用的数据复制进 App 的资源目录（shared/ 是唯一的源）：知识点清单、AI 提示词
set -euo pipefail
cd "$(dirname "$0")/.."
cp ../shared/knowledge.json assets/knowledge.json
cp ../shared/ai_prompts.json assets/ai_prompts.json
cp ../shared/demo.json assets/demo.json
cp ../shared/game.json assets/game.json
echo "已同步 assets/knowledge.json、ai_prompts.json、demo.json、game.json"
# 地图布局跟着知识点清单走：重新生成像素画（结果是确定的，没变化就不会有 git 改动）
python3 tool/art/build.py
