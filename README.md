# 随机行动启动器（RandomActionLauncher）

一款 macOS 本地菜单栏应用。用户预先添加可立即开始的文件、文件夹或视频；当不知道接下来做什么时，应用按权重随机给出一个候选项，并可用系统默认应用直接打开。

- 技术栈：Swift 6 + SwiftUI（必要时局部 AppKit），最低 macOS 14
- 存储：Core Data（代码化模型），数据全部留在本机，无网络、无遥测
- 权限：App Sandbox + 应用范围书签 + 用户选择文件只读

## 功能概览

- 通过系统文件选择器或拖放添加文件、文件夹、视频，自动做重复检测（基于安全作用域书签解析后的规范资源标识）
- 项目可编辑名称、备注、权重（低 1 / 中 2 / 高 3），状态可切换进行中 / 暂停 / 已完成
- 菜单栏面板一键「抽一个」，按权重随机抽取；「打开」与「重抽」同等显眼，支持无限重抽
- 抽中的项目进入 24 小时冷却，期间不再进入候选集合
- 资源被移动或磁盘卸载后标记不可用并可「重新定位」，不阻断其他候选
- 本地记录最少行为数据（会话、重抽次数、打开结果），不提供统计界面
- 空状态区分：尚未添加、全部暂停或完成、全部冷却中、路径不可用及混合原因

## 环境要求

- macOS 14 及以上
- Xcode Command Line Tools（提供 Swift 6 工具链）

## 构建与运行

```bash
./scripts/build.sh                          # 调试构建，输出 build/RandomActionLauncher.app
CONFIGURATION=release ./scripts/build.sh    # 发布构建
open build/RandomActionLauncher.app         # 启动（应用常驻菜单栏，无 Dock 图标）
```

## 测试

```bash
./scripts/test.sh    # 等价于 swift test，当前 69 项自动化测试
```

## 项目结构

```text
Sources/RandomActionLauncher/
  RandomActionLauncherApp.swift   应用入口，管理窗口与菜单栏场景
  MenuBarPanelView.swift          菜单栏面板界面
  ProjectManagerView.swift        项目管理界面
  Models/                         项目与会话模型、枚举与校验
  Persistence/                    Core Data 容器与仓储
  Services/                       导入、书签、抽取、冷却、打开、重新定位
  Features/                       界面协调对象（MainActor 串行状态）
Tests/RandomActionLauncherTests/  与源码模块对应的自动化测试
Configuration/                    应用信息与沙盒权限
scripts/                          可重复执行的构建 / 测试脚本
docs/requirements.md              已确认的完整需求文档（产品行为基线）
spec.md / plan.md                 实现规格与开发进度、验收记录
AGENT.md                          开发规则
```

## 文档

| 文档 | 作用 |
| --- | --- |
| [docs/requirements.md](docs/requirements.md) | 产品行为基线，冲突时以它为准 |
| [spec.md](spec.md) | 实现方式、模块职责与验收口径 |
| [plan.md](plan.md) | 九阶段任务状态、验证证据与 AC 001—012 追踪 |
| [AGENT.md](AGENT.md) | 开发与构建规则 |

## 当前状态

业务阶段完成 **5 / 9**（S1、S4、S7 已完成；S2、S3、S5、S6、S8、S9 待人工界面与真实磁盘验证）。构建、签名、发布配置和 69 项自动化测试均通过，菜单栏闭环、真实文件移动 / 外接磁盘、键盘与 VoiceOver 仍需人工验收，详见 `plan.md`。

## 明确不做

不自动扫描目录、不内置媒体播放器、不做账号 / 云同步 / 提醒打卡 / AI 推荐、无 Finder 扩展与统计仪表盘。删除项目只移除应用内记录，不会删除、移动或修改原始文件。
