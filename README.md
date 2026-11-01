# iPhone 安装链路验证

仅用于验证：Windows 编辑源码 → GitHub Actions macOS 编译 → 未签名 IPA → Windows 免费个人签名 → iPhone。

这不是每日打卡 App 的正式实现。没有任务列表、习惯频率、月历、月度统计或同步服务。

## 探针功能

- A、B 构建显示不同构建号，原始 Bundle ID 均为 `com.dailyhabit.chainprobe`。
- 首次点击才创建一个随机 UUID 标记，保存到 Application Support/ChainProbe/marker.json。
- 后续启动只读回；已存在的有效标记保持不变，损坏文件报错并保留。
- 用户主动申请通知权限，安排一条 30 秒通知；可取消、重新读取队列及分享文本摘要。
- 单 App、无扩展、无后端、无账号功能、无特殊签名能力。

## 构建

仓库必须为 Public，使用标准 `macos-15` 运行器。工作流在 main 上相关源码变更或手动操作时运行，不设置定时构建。当前锁定 Xcode 26.2 路径，最低部署目标为 iOS 17.0；运行器移除该工具时应明确更新配置，不能把失败当成成功。

1. GitHub → Actions → **Build unsigned iPhone probe** → Run workflow，或提交源码触发。
2. 工作流先运行测试标记的 Swift 测试，再编译 A、B。
3. 成功后下载 `chain-probe-运行号-尝试号` 产物（保留 3 天）。
4. 产物含两个 IPA、SHA256、构建清单、工具版本、存储测试结果和真机验收说明。
5. 在 Windows 核对 SHA256，再按 [真机验收步骤](docs/DEVICE-ACCEPTANCE.md) 安装。

**IPA 未签名，不能直接点开安装。CI 成功不代表 iPhone 安装、续签或通知通过。**

手动在具备 Xcode 的 Mac 运行相同流程：

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
bash scripts/build.sh
```

脚本要求新工作副本，不自动删除旧构建。修改工程生成器后运行 `node scripts/project.mjs`，连同生成的工程提交；CI 用 `--check` 验证二者一致。没有第三方 Swift 包或工程生成器依赖。

## 验证边界

| 检查 | 运行位置 | 能证明什么 |
|---|---|---|
| Swift 磁盘测试 | Actions 的 macOS | 标记读写、重开、损坏保护；不证明 iPhone 升级保留数据 |
| xcodebuild | Actions 的 macOS | iPhoneOS 源码编译；不证明安装成功 |
| IPA 校验 | Actions 的 macOS | ZIP CRC、Info.plist、arm64、无签名、SHA256 |
| C04～C09 | 目标 iPhone + Windows | 实际安装、更新、续签、持久化、锁屏通知与取消 |

初始源码交付时，远端编译与真机测试均尚未执行。请以实际 Actions 运行及本地验收记录为准，不把本说明中的步骤视作通过记录。

## 费用与凭据

公开仓库的标准托管构建适用 GitHub 免费规则；产物和缓存仍有各自计费边界。本工作流只留少量短期产物，不使用大型运行器或付费服务。签名在 Windows 本地完成，不向仓库或 Actions 上传 Apple 密码、证书、描述文件、设备配对文件和真实用户记录。

免费个人签名通常约 7 天失效，需提前刷新。刷新签名与重新构建是两件事；每次更新继续使用同一账号和签名配置，不卸载原 App。

## 官方参考

- [GitHub Actions 计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [macOS 15 镜像工具清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [AltStore Classic Windows 安装](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore 免费签名与刷新](https://faq.altstore.io/altstore-classic/your-altstore)
- [Apple 本地通知](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
