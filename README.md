# HP LaserJet 1020 on macOS (foo2zjs)

让 USB 连接的 **HP LaserJet 1020** 在现代 macOS（Apple Silicon）上正常打印：系统打印对话框里直接选，每次打印前自动检查并补传固件。

> English summary at the bottom.

## 症状

在 Mac 上添加 1020，打印任务显示"已完成"，队列回到闲置，没有任何报错——但纸就是不出来。同一台打印机在 Windows / Linux 上一切正常。用通用 PCL 驱动、`lp -o raw` 直接发 PCL 也一样不出纸。

## 原因

用 `/usr/libexec/cups/backend/usb` 读打印机的 IEEE 1284 设备 ID 就能看出来：

```
MFG:Hewlett-Packard;MDL:HP LaserJet 1020;CMD:ACL;CLS:PRINTER;...
```

1. **`CMD:ACL`，没有 PCL。** 1020 是主机渲染（GDI）打印机，只接受 HP 私有的 ZjStream 数据，收到 PCL 会静默丢弃。
2. **没有 `FWVER`。** 1020 的固件放在易失内存里，每次断电后都要由电脑重新上传。Windows / Linux 的驱动会自动做这件事，macOS 上没有程序做。

上传固件后，设备 ID 里会出现 `FWVER:20050309`，指示灯也会亮。

## 工作原理

```
应用 ──PDF──▶ cupsd ──▶ pdftozjs-1020 ──▶ usb 后端 ──▶ 打印机
                          │
                          ├─ sc-deviceid：经 CUPS side channel 读设备 ID
                          │    有 FWVER → 跳过；没有 → 先发固件，等 8 秒
                          ├─ gs：PDF → 600 dpi 单色位图
                          └─ foo2zjs：位图 → ZjStream（-z1 -P -L0，与 foo2zjs 官方 1020 配置一致）
```

几个在 macOS 上踩过的坑：

- **CUPS 沙盒**：过滤器在沙盒里运行，不能执行 `/usr/local/bin/gs` 之类的程序（日志里是 `Operation not permitted`）。所以 gs 和它的资源文件会被复制到 `/Library/Printers/foo2zjs/`。
- **没有 libjbig**：用 foo2zjs 源码自带的 `jbig.c` 编译。
- **没有 PS→PDF 过滤器**：PPD 同时声明了 PDF 和 PostScript 两种输入，都由 gs 处理。
- **固件只在需要时上传**：先问 usb 后端要设备 ID，看到 `FWVER` 就不再重复上传，连续打印不用每单多等几秒。

## 依赖

- Xcode Command Line Tools（`xcode-select --install`）
- 一个**自包含**的 Ghostscript：只依赖 `/usr/lib` 和 `/System` 下的系统库，因为它要被复制进 `/Library/Printers` 才能在沙盒里运行。
  - ✅ 已验证：[MacTeX](https://tug.org/mactex/) 自带的 Ghostscript（`/usr/local/bin/gs-noX11`，10.07.0）；也可以只装 MacTeX 单独提供的 Ghostscript 安装包（见 [tug.org/mactex/morepackages.html](https://tug.org/mactex/morepackages.html)）。
  - ❌ Homebrew 的 `ghostscript` 依赖 `/opt/homebrew` 里的库，`build.sh` 会检测到并拒绝。
- 网络：`build.sh` 会从 GitHub 拉 foo2zjs 源码，并下载固件。

## 安装

```bash
git clone https://github.com/daidaidaiok/hp-laserjet-1020-macos-foo2zjs.git
cd hp-laserjet-1020-macos-foo2zjs
./build.sh                  # 普通用户运行，只写 ./build
./install.sh --dry-run      # 预览将要做的事
sudo ./install.sh           # 安装并新建队列
```

`build.sh` 会：

1. 克隆 [OpenPrinting/foo2zjs](https://github.com/OpenPrinting/foo2zjs)（固定提交），编译 `foo2zjs` 和 `arm2hpdl`；
2. 下载固件 `sihp1020.img`（与 foo2zjs 的 `getweb 1020` 同一来源），校验 SHA-256，转换成 `sihp1020.dl`；
3. 编译 `sc-deviceid`；
4. 复制 gs 和资源文件。

`install.sh` 会：

- 把文件装到 `/Library/Printers/foo2zjs/`（全部 root:wheel）；
- 自动识别 USB 上的 1020（多台时用 `--uri` 指定）；
- **新建**队列 `HP_LaserJet_1020_foo2zjs`（可用 `--queue` 改名），不改动已有的队列和默认打印机。

装好后在打印对话框里选 **HP LaserJet 1020 (foo2zjs)**。原来那个不出纸的队列可以自己在「系统设置 → 打印机与扫描仪」里删掉。

## 验证

不耗纸的检查：

```bash
# 设备 ID：有 FWVER 说明固件已加载
/usr/libexec/cups/backend/usb 2>&1 | grep -i 1020

# 在 cupsd 的真实沙盒里跑一遍过滤器，输出到本机端口而不是打印机
sudo scripts/sandbox-test.sh some.pdf
```

出问题时看日志，每一单都会记录固件判断和 gs/foo2zjs 的错误：

```bash
grep pdftozjs-1020 /var/log/cups/error_log | tail
```

## 卸载

```bash
./uninstall.sh --dry-run
sudo ./uninstall.sh
```

## 已知限制

- 只在 **macOS 26.6（Apple Silicon，Mac Studio）+ MacTeX Ghostscript 10.07.0** 上验证过，A4 出纸正常。其他版本欢迎反馈。
- 只做了单面、单色、600 dpi；纸张支持 A4 / A5 / B5 / Letter / Legal / Executive。
- 打印前补传固件后固定等 8 秒，这是经验值。
- CUPS 会提示"打印机驱动程序已弃用"，这是 CUPS 对所有 PPD 队列的通用警告，目前不影响使用。

## 固件与许可

- 本仓库代码以 **GPL-2.0-or-later** 发布（见 [LICENSE](LICENSE)）。过滤器里的参数和管道写法参考了 foo2zjs 的 `foo2zjs-wrapper`。
- **仓库不包含 HP 固件，也不包含任何二进制。** 固件版权归 HP 所有，由 `build.sh` 在你本机下载和转换，请自行确认使用是否合规。

## 同类项目

在写这个之前，GitHub 上已经有人做过同样的事，各有取舍，可以对比着选：

- [OneCoinOnePlay/hp-laserjet-1020-macos](https://github.com/OneCoinOnePlay/hp-laserjet-1020-macos)：Apple Silicon 原生驱动，带安装器，每单都先发固件。思路和本项目最接近。
- [sksonip/hp-laserjet-1020-macos-helper](https://github.com/sksonip/hp-laserjet-1020-macos-helper)：一条命令安装，外加一个桌面上的固件加载器，打印机断电后手动点一下。
- [moleong/hp-laserjet-1020-macos](https://github.com/moleong/hp-laserjet-1020-macos)：foo2zjs + Homebrew，外加 Web 打印服务器。
- [i-SiddharthRajesh/hp-laserjet-1020-macos](https://github.com/i-SiddharthRajesh/hp-laserjet-1020-macos)：基于 HP 旧版驱动组件，作者自述为实验性。

本项目的不同之处主要是：用 CUPS side channel 检查 `FWVER`，只在需要时上传固件；复用系统里已有的 Ghostscript，不需要 Homebrew。

## 致谢

- [foo2zjs](https://github.com/OpenPrinting/foo2zjs)，作者 Rick Richardson，现由 OpenPrinting 维护。没有它就没有这个项目。

---

## English summary

The HP LaserJet 1020 is a host-based printer: it only understands HP's ZjStream (`CMD:ACL`, no PCL) and keeps its firmware in volatile memory, so on macOS jobs "complete" but nothing prints. This project installs a small CUPS filter that renders PDF with Ghostscript, converts it with [foo2zjs](https://github.com/OpenPrinting/foo2zjs), and uploads the firmware only when the printer's IEEE 1284 device ID (read over the CUPS side channel) lacks `FWVER`. Ghostscript is copied into `/Library/Printers/foo2zjs` because the cupsd sandbox refuses to exec it from `/usr/local`.

```bash
./build.sh && ./install.sh --dry-run && sudo ./install.sh
```

Requires the Xcode CLT and a self-contained Ghostscript (MacTeX's works; Homebrew's does not). No firmware or binaries are included; `build.sh` downloads the firmware and verifies its SHA-256. Tested on macOS 26.6 / Apple Silicon. Licensed GPL-2.0-or-later. See the list of similar projects above.
