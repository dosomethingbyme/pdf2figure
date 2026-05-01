# Figra

Figra 是一个本地优先的 macOS PDF 工具箱，面向论文阅读、图表复用、报告整理和日常 PDF 处理。应用不上传文件，默认生成新文件，不覆盖原 PDF。

![Figra 软件界面](docs/images/figra-ui.png)

## 当前能力

- 图表提取：第一个主功能。使用内置 `pdffigures2.jar` 从单个论文 PDF 提取 Figure/Table，输出 PNG，DPI 支持 `150 / 300 / 600 / 900`，默认 600。
- 图库面板：查看全部图表，支持图片/表格筛选、点击缩略图复制、关闭按钮、打开图片、Finder 定位、移除误识别结果和导出 CSV。
- 页面提取：显示全部页面缩略图，左侧选择同步右侧 PDF 预览，右键缩略图复制该页为图片，支持页码范围、全选、清空、图片导出和 PDF 导出。
- 页面整理：相册式页面缩略图，拖动重排、移除页面后导出新 PDF。
- 合并 PDF：多 PDF 排序合并，每项支持上移、下移和移除。
- BibTeX 工具：选择或拖入 `.bib` 文件，通过“合并 / 合并去重 / 格式化 / 去重格式化”四个任务导出；去重时按引用键或归一化标题识别重复文献，保留先出现的条目，并显示输入、重复项和生成参考文献数量。
- 拆分 PDF：复用页面选择器，支持选中页、每页、每 N 页导出。
- 压缩 PDF：使用 PDFKit 重写结构生成优化副本，完成后显示体积变化；不对扫描图片做有损重采样。
- 清除隐私：清理 PDF document info metadata，明确不扫描页面正文、批注或图片内容。
- PDF 加密：导出加密副本，或输入密码后导出无密码副本。
- 最近任务与输出设置：记录本次运行输出，支持默认输出目录、默认 DPI 和导出后自动定位。

## 工程结构

```text
FigraApp/
  Info.plist
  build_app.sh
  build_dmg.sh
  Sources/
    FigraApp.swift
    FigraModels.swift
    FigraAppModel.swift
    FigraViews.swift
    BibToolViews.swift
    PDFOperations.swift
    FigureExtractionService.swift
  Resources/
    pdffigures2.jar
    jre/
    logo.png
    AppIcon.iconset/
    AppIcon.icns
    AppIcon.ico
    generate_app_icon.swift
docs/
  PRODUCT_REQUIREMENTS.md
logo.png
```

命名约定：

- App 名称、bundle 名称和可执行文件统一为 `Figra`。
- macOS app 工程目录统一为 `FigraApp/`。
- 根目录 `logo.png` 是唯一 logo 源。构建时会从它生成 `Resources/logo.png`、`AppIcon.iconset`、`AppIcon.icns` 和 `AppIcon.ico`。
- 生成的 app logo 和图标会统一做 macOS 风格圆角裁切。

## 构建

```bash
cd FigraApp
./build_app.sh
```

构建 DMG：

```bash
cd FigraApp
./build_dmg.sh
```

产物：

```text
FigraApp/Figra.app
FigraApp/Figra.dmg
```

## 运行时依赖

- `Resources/pdffigures2.jar` 会被打包进 `.app/Contents/Resources/`。
- `Resources/jre/` 会被打包进 `.app/Contents/Resources/`。
- 正式 app 不依赖系统 Java、Python 或 conda。

## 图标生成

如需单独刷新图标：

```bash
cd FigraApp/Resources
swift generate_app_icon.swift
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

`build_app.sh` 会在检测到根目录 `logo.png` 时自动执行上述图标生成流程。
