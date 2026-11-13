# API 接入说明（1.18.19）

## 推荐：DeepSeek 官方接口，支持完整功能

- 接口：`https://api.deepseek.com/chat/completions`
- 方法：`POST`；`Content-Type: application/json`
- 认证：`Authorization: Bearer <你自己的 API Key>`
- 默认模型：`deepseek-chat`
- 应用发送 `model`、`messages`（system 人设、user 场景及上下文）、`stream:false` 等字段，读取 `choices[0].message.content`。
- 目前人设/主动模式只接受官方 HTTPS 域名 `api.deepseek.com`，并不是任意 OpenAI 兼容接口都能直接替换。

运行 `setup.bat` 可配置；手动配置则使用以下文件：

`credentials.yaml`（由你本机创建，不要分享）：
```yaml
refs:
  DEEPSEEK_API_KEY: "这里填你自己的 sk- 开头密钥"
```

`config.json` 相关字段：
```json
{
  "fallbackUrl": "https://api.deepseek.com/chat/completions",
  "model": "deepseek-chat",
  "credentialFile": "credentials.yaml",
  "personaFile": "persona-大肥鱼.txt"
}
```
以上是相关字段示意，不要用它覆盖完整配置。

也支持进程环境变量 `DEEPSEEK_API_KEY`，优先于 YAML 文件。环境变量更改后必须重启助手。
不要将 Key 填到 `apiUrl`、人设、聊天框或公开日志里。密钥应由使用者自行申请，套餐/余额与作者互不共享。

## 兼容的本地聊天接口

`POST http://127.0.0.1:3100/api/game/chat`

```json
{"channel":"whisper","speaker":"队友","text":"最后一句","recent":[{"speaker":"队友","text":"前文"}]}
```

响应：
```json
{"ok":true,"reply":"一句话","delayMs":0}
```

- `channel` 取 `whisper|party|say`。真实游戏收件人/频道由插件原请求锁定，不由模型响应指定。
- 最多传最近 8 条上下文；返回 `ok:false` 或非成功 HTTP 状态会按已有错误处理报告。
- 若本地服务要求令牌，可把令牌单独存本机文件并设置 `consoleTokenFile`。仅 loopback 地址附加 `x-console-token`；不向第三方 URL 转发。
- 这个服务本身**不在包内**，使用者必须自己启动。`127.0.0.1` 指使用者的电脑，不是作者电脑。
- 本地路由仅用于未配置 `personaFile` 的普通 reply 模式；场景、信号、任务事件、私聊和公开自动回复仍走官方 DeepSeek。完整功能请按上节配置，不能只填一个本地 URL。

## 配置项

| 字段 | 说明 |
|---|---|
| character | 游戏完整角色名，例如 `角色名-服务器`；必填 |
| gameExe | 本机实际 `Wow.exe` 绝对路径；必填 |
| personaFile | 人设文本，相对路径相对于配置文件目录 |
| credentialFile | 自己的密钥 YAML 文件；相对路径同上 |
| model / fallbackUrl | 官方模型名和接口地址 |
| apiUrl / consoleTokenFile | 兼容本地接口及可选本地认证文件 |
| requestTimeoutMs | 请求超时，默认 12000，范围 1000～30000 |
| pollMs | 检测间隔，默认 150，范围 100～2000 |
| keywords | 默认 `大肥鱼`、`鲸鱼`；私聊并不要求关键词 |
| cooldownSeconds / hourlyLimit | 默认均为 0，不额外限流；0 表示不限 |
| paused | 托盘手动暂停状态，默认 false |
| hotkey / inputIdleMs | 旧兼容字段；不再注册全局热键，也不靠固定空闲等待通信 |

游戏内总控、分项开关、频道选择和窗口布局保存在游戏自己的 SavedVariables 中，不在本分享包里。

## 故障判断

- 401：Key 无效；余额/额度错误请检查自己的 API 账户。
- 超时：检查网络与接口状态。助手不保证每次固定三秒内完成，模型和网络会波动。
- API 有回复但游戏没显示：属于插件回传/角色绑定/前台读取问题，不等同 API 未接通。
- 分享前移除 `credentials.yaml`、配置中的私有路径、日志及聊天记忆。自动化和向外部 AI 发送聊天均需使用者知情同意。
