# 独立开发版 1.18.21-dev.1

分支：`codex/knowledge-async`。基线是已发布源码 1.18.20；**不修改线上安装**。

## 隔离边界

- `DFY_PREVIEW` 编译标记使 EXE 只接受 `--self-test`。普通启动、`--probe`、`--job-test`、`--api-test`、桥接测试均以退出码 64 拒绝，不创建托盘、不读取游戏、不注入按键。
- 安装脚本在读取游戏配置前直接拒绝安装。不要手工覆盖正在使用的插件。
- 目录中没有线上配置、API Key、控制台令牌或聊天记录。模板默认 `knowledgeEnabled=false`。
- 离线测试只访问测试进程临时端口和假 HTTP 处理器，不访问正在使用的 3100 服务或 DeepSeek。
- 没有变更发言冷却、上限、总控和制作隔离；未合并稳定分支或发布新的正式安装包。

## 启动默认频道

每次登录或 `/reload` 后，公开发言目标默认设为“说”（SAY），并勾选该频道；其他监听勾选和自动开关保持原样。当前会话仍可手动切换频道，刷新界面不会重置选择。私聊和战网私聊仍回复原发送者，不转到“说”。启动本身不会发送消息。此修改仅在独立开发版，未部署线上。

离线回归：安装 Python `lupa` 后运行 `python tools/tests/startup_channel.py --root .`。

## 构建和测试

Windows + .NET 8 SDK：先复制 `config.example.json` 为 `config.json`，执行 `build.bat`，然后：

```powershell
.\WhaleChat.exe --self-test --root .
```

读取 `verification/desktop-test.json` 查看结果。也可以 `dotnet build desktop/WhaleChat.csproj -c Release` 后运行构建目录的 EXE，指定本开发目录为 `--root`。

## 修复内容

1. 检索调用链全部 `await`，网络延续不占用界面线程；WinForms Timer＋真实临时 HTTP 服务覆盖旧死锁场景。
2. 整次生成共享取消/超时预算，手册仅占其中默认 600ms；超时/网络错误自动跳过资料，外部取消照常传播。事件和标记不查询手册。
3. 本地名称索引提取句中实体，优先最长匹配，每次最多两个。不是把整句话交给精确名称搜索。
4. 成功缓存 5 分钟，明确无结果缓存 30 秒，网络/授权/解析错误不缓存。缓存按手册来源、凭据摘要和实体区分，最多 512 项。
5. 手册地址独立于模型 API，仅允许明确的本机回环 HTTP(S) 根地址；拒绝重定向。令牌只来自显式 `knowledgeTokenFile`，通过兼容现有桥接的 `x-console-token` 请求头传递，不放 URL，不自动复用模型配置中的控制台令牌。
6. 检索资料标为事实数据，不覆盖人设或当前游戏状态。不加入未核验的本服规则。

## 新配置项（仅为未来受控验收准备）

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `knowledgeEnabled` | `false` | 是否启用可选手册资料 |
| `knowledgeBaseUrl` | `http://127.0.0.1:3100` | 独立的本机手册服务，不跟随 `apiUrl` |
| `knowledgeTokenFile` | 空 | 明确授权的手册令牌文件，绝不提交 Git |
| `knowledgeIndexFile` | `knowledge/entities.json` | 仅名称索引，不是完整事实数据库 |
| `knowledgeTimeoutMs` | `600` | 单次检索总预算，范围 50～1500ms，不是发言冷却 |

名称索引来自用户已有手册表格，包含副本、物品、配方产物和技能名称。来源文件 SHA256 记录在 `knowledge/entities.manifest.json`；生成工具是 `tools/build-handbook-index.py`，不会修改原始手册。

完整事实仍由 `/api/handbook/search?q=名称` 及对应 `dungeon/item/recipe/spell` 接口提供。此开发版尚未对线上账号做真实聊天验收，也未验证新的服务器规则。解除预览隔离和部署必须另行明确确认；自动化存在账号风险。
