# SA-MP Android 插件开发工具

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

本仓库提供用于开发 SA-MP Android Lua 插件的公开工具和示例。

本仓库不包含 SA-MP Android 客户端源码。客户端是闭源项目，插件只能通过公开文档中定义的 Lua API 与宿主交互。

## 仓库内容

- `samp-plugin`：使用 Go 编写的跨平台 CLI，用于校验插件项目并生成 `.splug` 安装包。
- `api/schema.json`：当前 Plugin API 1.0 的机器可读契约快照。
- `examples/`：可以独立校验、打包和安装的示例插件。

## 安装

从 [GitHub 最新 Release](https://github.com/SA-MP-Android/Plugin-Tools/releases/latest) 下载与操作系统和处理器架构对应的压缩包：

1. 根据平台选择名称中包含 `windows_amd64`、`linux_arm64` 或 `darwin_arm64` 等标识的压缩包。
2. 解压得到 `samp-plugin` 或 `samp-plugin.exe`。
3. 将可执行文件移动到 `PATH` 中的目录，或者使用完整路径运行。

Release 提供 Windows、Linux 和 macOS 的 amd64 与 arm64 构建。需要校验下载完整性时，请使用 Release 中的 `checksums.txt`。

可以使用 `samp-plugin version` 查看已经安装的 CLI 版本。

## 校验插件

校验源码目录：

```bash
samp-plugin validate examples/fps-counter
```

校验已有插件包：

```bash
samp-plugin validate fps-counter-1.0.0.splug
```

校验范围包括 manifest 字段类型和长度、SemVer、API 兼容范围、权限、上下文、Lua 入口文件、跨平台路径安全、文件数量，以及与客户端一致的包容量限制。

## 打包插件

```bash
samp-plugin pack examples/fps-counter
```

默认在源码目录的上一级生成 `<插件 ID>-<版本>.splug`。也可以指定输出位置：

```bash
samp-plugin pack --output dist/fps-counter.splug examples/fps-counter
```

工具不会覆盖已有文件。生成的包使用排序后的便携路径、固定时间戳和固定文件权限，因此相同输入会产生相同字节和 SHA-256。`manifest.json` 始终位于压缩包根目录。

## 插件目录

最小项目结构如下：

```text
my-plugin/
├── manifest.json
└── main.lua
```

可选目录包括 `modules/`、`assets/` 和 `locales/`。包内路径始终使用 `/`，不得包含绝对路径、反斜杠、空路径段、`.` 或 `..`。

完整的 Lua API、事件参数、权限和运行时限制以 SA-MP Android 官方文档为准。`api/schema.json` 是随客户端版本发布的契约快照；修改契约时必须同步更新测试和示例。

## 开发

开发需要 Go 1.24 或更高版本。CLI 仅使用 Go 标准库。

```bash
go test ./...
go vet ./...
go build -o bin/samp-plugin ./cmd/samp-plugin
```

仓库不会提交生成的二进制文件和 `.splug` 包。推送匹配 `v*` 的 tag 后，Release 工作流会自动测试项目、构建全部支持平台的压缩包、生成 SHA-256 校验清单并发布 GitHub Release。

## 开源协议

本仓库使用 [MIT License](LICENSE)。
