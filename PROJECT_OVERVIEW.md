# SSH Terminal - iOS App

## 项目结构

```
SmartSSH/
├── SmartSSHApp.swift          # App 入口
├── Info.plist                    # App 配置
├── Assets.xcassets/              # 图片资源
├── SmartSSH.xcdatamodeld/     # Core Data 模型
│
├── Models/
│   └── Host.swift                # Host 模型
│
├── Views/
│   ├── ContentView.swift         # 主视图
│   ├── HostsView.swift           # 主机列表
│   ├── AddHostView.swift         # 添加主机
│   ├── TerminalView.swift        # 终端视图
│   ├── KeysView.swift            # 密钥管理
│   ├── SnippetsView.swift        # 代码片段
│   └── SettingsView.swift        # 设置
│
├── Services/
│   ├── DataController.swift      # Core Data + iCloud
│   └── SSHManager.swift          # SSH 连接管理
│
└── ViewModels/
    └── (待添加)
```

## 如何在 Xcode 中打开

1. 打开 Xcode
2. File → New → Project
3. 选择 iOS → App
4. 产品名称: SmartSSH
5. 保存到: `/Users/jianpinghuang/projects/`
6. 复制这些文件到新项目中

## 已完成功能

- [x] 项目结构
- [x] UI 框架（所有视图）
- [x] Core Data 模型
- [x] SSH Manager（模拟）
- [x] iCloud 同步配置
- [x] 密钥生成逻辑

## 下一步

### 1. 实现真实 SSH 连接

需要集成 SSH 库。有两个选择：

**选项 A: NMSSH (推荐)**
```ruby
# Podfile
platform :ios, '15.0'
use_frameworks!

target 'SmartSSH' do
  pod 'NMSSH', '~> 2.3'
end
```

**选项 B: libssh2**
- 需要手动编译
- 更灵活但更复杂

### 2. 添加 SFTP 功能

### 3. 添加 AI 功能

### 4. 添加订阅系统

## 商业化计划

| 功能 | 免费版 | Pro ($4.99/月) |
|------|--------|----------------|
| SSH 连接 | ✅ | ✅ |
| 主机数量 | 5个 | 无限 |
| SFTP | ❌ | ✅ |
| iCloud 同步 | ❌ | ✅ |
| AI 功能 | ❌ | ✅ |
| 主题 | 基础 | 全部 |

## 竞品对比

| 功能 | Termius | 我们 |
|------|---------|------|
| 价格 | $10/月 | $4.99/月 |
| 云同步 | 付费 | 免费 |
| AI | 无 | 有 |
| 原生性能 | Electron | Swift |

## 下一步

1. 在 Xcode 创建项目
2. 安装 CocoaPods
3. 集成 NMSSH
4. 实现真实 SSH 连接
5. 测试基本功能

要我帮你做哪一步？
