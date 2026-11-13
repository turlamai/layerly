# Layerly

> AI 原生 3D 打印工作台——从一个想法，到一件拿得起来的东西。

Layerly 是面向个人 3D 打印的桌面工作台：一件作品的完整生命周期收在同一处——需求 brief、设计版本、模型文件、切片方案、用掉的耗材、打印记录、成品的实物照片——旁边站着一位了解你的打印机、你的耗材和你的打印历史的 AI 顾问。顾问负责解释、对比与起草；所有关键动作（发送打印任务、采购耗材、删除归档）都由你显式确认。

核心流程全部本地运行。打印机走局域网直连，核心功能不依赖云账号。

English readme: [README.md](README.md)。

## 状态

骨架阶段。按家族原型先行流程，设计基线（`design/DESIGN.md` +
`design/prototype/`）先于实现落地。

## 环境要求

- Racket（含 `glaze` 包）与系统原生 WebView
  - macOS：WKWebView（内置）
  - Windows：WebView2
  - Linux：WebKitGTK
- Node.js 22+ 与 pnpm

## 开发

```sh
pnpm install
pnpm build          # 构建前端到 apps/desktop/dist
raco glaze dev      # 运行原生应用
raco test backend/  # 后端单元测试
raco glaze schema check --json
pnpm check          # 前端类型检查
```

参与贡献见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[AGPL-3.0](LICENSE)。Layerly 为独立实现，不包含来自非商业许可项目的代码。
