# 🍣 寿司郎 (Sushiro) 极客排队助手

这是一个纯 Bash 编写的微信小程序抓取脚本，专门用于查询**中国大陆地区寿司郎（Sushiro）**的实时排队数据。

与官方的小程序相比，本助手专为**真实在排队等待的干饭人**设计了诸多 UX 级增强功能，包括进度条看板、排队速度追踪和主动弹窗/推送提醒，让你排队去逛街时也能对进度了如指掌。

## ✨ 核心特色功能 (UX Enhancements)

- ⏳ **预估等待时间 (`estimate`)**：基于排队桌型（吧台 / 四人桌）的平均翻台率，直接为你估算大概还需等待多少分钟，而不是只给你一个干巴巴的“50桌”。
- 🚀 **消化速度追踪 (`track`)**：静默追踪排队队列。每分钟汇报“过去一分钟消化了多少桌”，让你一眼看穿前面的队伍是“卡住了”还是“跑得飞快”。
- 📱 **主动弹窗与推送 (`alert`)**：不用再一直低头刷新小程序。设置一个阈值（如剩 5 桌时），触发后 **macOS 会弹出系统通知**，如果你配置了 iOS Bark，你的 **iPhone 也会收到推送**“快到了！请速回门店”。
- 📊 **动态排队看板 (`dash`)**：极客风全屏控制台，像下载进度条一样实时展示你排队的进度百分比。

## 📦 快速开始

**系统要求**：macOS / Linux, 需要安装 `curl` 和 `jq`。

```bash
# 进入脚本所在目录并赋予执行权限
cd 寿司郎
chmod +x sushiro.sh

# 1. 查询附近/想去的门店的 ID
./sushiro.sh search 中关村

# 2. 查该门店的动态排队进度条 (假设起始是 45 桌)
./sushiro.sh dash 3014 45

# 3. 设置 iPhone 联动推送 (当剩 5 桌时通知我)
export BARK_KEY="您的_IOS_BARK_KEY"
./sushiro.sh alert 3014 5
```

## 🛠️ 全部可用命令列表

### 增强排队体验
| 命令 | 用法 | 说明 |
|------|------|------|
| `dash` | `./sushiro.sh dash <门店ID> [起始桌数]` | 渲染动态的排队进度条面板，每 15 秒自动刷新。 |
| `alert` | `./sushiro.sh alert <门店ID> <阈值>` | 后台挂机。当队伍小于该阈值时弹窗/推送，并退出脚本。 |
| `track` | `./sushiro.sh track <门店ID> [刷新秒数]` | 监控队伍消化速度，判断当前排队是快是慢。 |
| `estimate`| `./sushiro.sh estimate <门店ID> [table/counter]`| 智能估算排队时间（吧台倍数3，普通桌倍数5）。 |

### 基础查询数据
| 命令 | 用法 | 说明 |
|------|------|------|
| `summary` | `./sushiro.sh summary` | 汇总全国各城市的营业门店数与总排队桌数。 |
| `search` | `./sushiro.sh search <关键字>` | 模糊搜索店名、商圈、地址，获取对应门店的 ID。 |
| `stores` | `./sushiro.sh stores [--city=北京] [--waiting]` | 列出所有门店。支持按城市或“正在排队”过滤。 |
| `store` | `./sushiro.sh store <门店ID>` | 获取某家店的详情。 |
| `areas` | `./sushiro.sh areas` | 获取所有商圈/行政区列表。 |

## 🔗 关于推送 (iOS Bark Integration)
本项目默认使用 macOS 的 `osascript` 提供桌面提醒。若要联动手机：
1. 在 App Store 下载 [Bark](https://apps.apple.com/cn/app/bark-customed-notifications/id1407223620)
2. 获取你的私有 Key (形如 `AbCdEf123456`)
3. 在终端里设置环境变量 `export BARK_KEY="AbCdEf123456"` 即可。

---
*免责声明：本脚本仅使用寿司郎微信小程序的公开查询接口，通过合法抓取技术（curl+jq）呈现公开的排队数据，不得用于恶意并发访问等危害服务端的操作。*
