# Figra 软件开发规则

- 后续本软件相关开发都在当前目录 `/Users/yangye/github/pdf2figure` 下进行。
- macOS app 工程在 `FigraApp/`。
- `pdffigures2.jar` 已放在 `FigraApp/Resources/pdffigures2.jar`，后续打包时应复制进 `.app/Contents/Resources/`。
- 正式 app 后端只使用 `pdffigures2` 提取 Figure/Table，不提取 PDF 内嵌对象。
- 输出图片使用 600 DPI PNG。
- `FigraApp/Resources/jre/` 是随 app 打包的精简 Java runtime。
- 不要把论文 PDF、论文图片产物或 draw.io 复刻文件混入软件工程目录，除非它们被明确作为测试样例或资源使用。
- 以后发布 release 不要手动创建或手动上传附件；只推送版本 tag，让 GitHub Actions 自动构建并发布唯一的 `Figra-vX.Y.Z.dmg` 和 `.sha256`。
