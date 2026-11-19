# Layerly

**从想法到实物——本地优先的 3D 打印工作台。**

[English](README.md) · **简体中文**

> **开发预览——工程骨架阶段。** 当前是设计与架构实现，不是已经正式发布的消费应用。没有经过验证的安装包、收费版、购买入口或试用到期限制。

## 目标工作流

Layerly 计划将一件作品的整个生命周期放在一起：需求、设计迭代、3D 模型、切片方案、耗材、打印记录和成品照片。自带模型密钥的 AI 顾问负责解释和起草；发送打印、采购耗材、删除记录等重要动作必须由人明确确认。

核心流程以本地为主，打印机通过局域网接入，不强制云账号。**这些是设计目标，并非所有功能已实现或可用的证明。**

## 平台与阶段

目标平台为 macOS、Windows、Linux，技术路线为 [Glaze](https://github.com/turlamai/glaze)、Racket 后端及系统原生 WebView。当前开发以 [design/DESIGN.md](design/DESIGN.md) 和 [design/prototype](design/prototype/) 为设计基线。

当前没有通过打包验收的正式安装包。不要用原型无人值守地控制生产打印机。

## 开发者快速开始

依赖 Racket 与 `glaze` 包、Node.js 22+、pnpm，以及 macOS 的 WKWebView / Windows 的 WebView2 / Linux 的 WebKitGTK。

```sh
pnpm install
pnpm build          # 构建前端
raco glaze dev      # 开发态原生宿主
raco test backend/  # 后端单测
raco glaze schema check --json
pnpm check          # 前端类型检查
```

这些是开发环境指令，不代表发行版通过验收。

## 数据、隐私与恢复

核心数据计划留在本机；关键操作显式确认。文件格式、备份、迁移与崩溃恢复还需在正式发布前验证，重要作品不可只保存于原型中。

## 反馈

在 [Issues](https://github.com/turlamai/layerly/issues) 提交最小复现场景、系统/工具链与非保密示例模型。贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[AGPL-3.0](LICENSE)。不含来自非商业许可项目的代码。[产品组合质量优先决策](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.zh-CN.md)不会更改既有许可。
