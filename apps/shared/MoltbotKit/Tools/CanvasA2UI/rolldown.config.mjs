import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "rolldown";

// 当前文件所在目录
const here = path.dirname(fileURLToPath(import.meta.url));
// 仓库根目录
const repoRoot = path.resolve(here, "../../../../..");
// 从当前目录解析路径的辅助函数
const fromHere = (p) => path.resolve(here, p);
// 输出文件路径
const outputFile = path.resolve(
  here,
  "../../../../..",
  "src",
  "canvas-host",
  "a2ui",
  "a2ui.bundle.js",
);

// A2UI Lit 渲染器的分发目录
const a2uiLitDist = path.resolve(repoRoot, "vendor/a2ui/renderers/lit/dist/src");
// A2UI 主题上下文文件路径
const a2uiThemeContext = path.resolve(a2uiLitDist, "0.8/ui/context/theme.js");

export default defineConfig({
  // 打包入口文件
  input: fromHere("bootstrap.js"),
  // 实验性配置
  experimental: {
    attachDebugInfo: "none", // 不附加调试信息
  },
  // 禁用树摇优化
  treeshake: false,
  // 模块解析配置
  resolve: {
    // 模块别名
    alias: {
      "@a2ui/lit": path.resolve(a2uiLitDist, "index.js"),
      "@a2ui/lit/ui": path.resolve(a2uiLitDist, "0.8/ui/ui.js"),
      "@moltbot/a2ui-theme-context": a2uiThemeContext,
      "@lit/context": path.resolve(repoRoot, "node_modules/@lit/context/index.js"),
      "@lit/context/": path.resolve(repoRoot, "node_modules/@lit/context/"),
      "@lit-labs/signals": path.resolve(repoRoot, "node_modules/@lit-labs/signals/index.js"),
      "@lit-labs/signals/": path.resolve(repoRoot, "node_modules/@lit-labs/signals/"),
      lit: path.resolve(repoRoot, "node_modules/lit/index.js"),
      "lit/": path.resolve(repoRoot, "node_modules/lit/"),
    },
  },
  // 输出配置
  output: {
    file: outputFile, // 输出文件路径
    format: "esm", // 输出格式为 ESM
    codeSplitting: false, // 禁用代码分割
    sourcemap: false, // 禁用源映射
  },
});