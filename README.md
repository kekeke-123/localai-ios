# 本地智能（LocalAI for iOS）

一个完全跑在 iPhone 本地的 AI 小工具：**本地识图 + 本地对话模型 + 可选的联网搜索**。

不依赖任何云端大模型服务，聊天记录和图片都不会上传。

## 结构

| 模块 | 用的是什么 | 是否离线 |
| --- | --- | --- |
| 识图 | 系统 Apple Vision（图像分类 / 文字识别 / 条码识别） | 完全离线，0 MB 额外存储 |
| 对话 | llama.cpp + GGUF 小模型（通义千问 2.5 0.5B / 1.5B） | 模型下载一次后完全离线 |
| 搜索 | 必应 / DuckDuckGo 网页版解析 | 只在打开开关时联网 |

## 功能

- **识图页**：选照片 → 本地识别画面元素、图中文字、条码 → 一键把结果发给对话模型解释。
- **对话页**：流式输出、可随时中断；点地球图标开启「这次提问联网搜索」，搜到的资料会作为提示词喂给模型，并在回答下方列出参考来源。
- **模型页**：三个模型条目（内置视觉模型 + 两个对话模型），显示体积、下载进度，可删除、可设为当前模型，也支持从「文件」App 导入任意 GGUF。
- **设置页**：搜索来源、温度、上下文长度、单次回答上限。

## 构建

GitHub Actions 自动构建未签名 IPA（见 `.github/workflows/build.yml`）：

1. `brew install cmake xcodegen`
2. `bash scripts/build-llama-ios.sh` —— 克隆并编译 llama.cpp（Metal 加速）为 `llama.xcframework`
3. `xcodegen generate`
4. `xcodebuild ... CODE_SIGNING_ALLOWED=NO`
5. 打包 `Payload/LocalAI.app` → `LocalAI.ipa`

本地手动构建也一样，只要在 macOS 上跑上面四步。

## 安装

构建产物是**未签名 IPA**，需要用自己的 Apple ID 签名：

- **Sideloadly**（Windows / macOS，最省事）
- **AltStore / SideStore**（免费账号 7 天续签）
- 有开发者证书的话，Xcode 直接真机跑也行

## 技术说明

- 推理：`llama.cpp`（c++），Objective-C++ 桥接 `LocalAI/LLM/LlamaShim.mm`，Swift 侧 `LlamaRunner` 放后台队列。
- 采样式生成：penalties → top-k → top-p → temp → dist，遇到 EOG 停止。
- 上下文管理与消息裁剪在桥接层完成；模型自带聊天模板（`llama_model_chat_template`），缺失时退回 ChatML。
- 识图用 `VNClassifyImageRequest` / `VNRecognizeTextRequest(zh-Hans, en-US)` / `VNDetectBarcodesRequest`。

## 已知限制

- 视觉模型是系统分类器，不是视觉大模型，只能给粗粒度标签，不能像 GPT-4V 那样细讲画面。
- 0.5B / 1.5B 小模型的常识和推理能力有限，回答短、偶尔跑题，属正常。
- 搜索是解析网页 HTML，搜索引擎改版可能需要跟着修选择器。
