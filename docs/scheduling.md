# 定时任务：launchd 与 cron

备份的触发源有两个：**git 钩子**（每次提交后顺手备份一次，可选）和**定时任务**（兜底：
长期不提交、钩子被绕过、关机错过都要靠它）。

`cold-backup` 只管定时任务这一半：

```sh
cold-backup schedule install [--at 12:00] [--kind launchd|cron] [--program 路径] [--label ID]
cold-backup schedule status
cold-backup schedule uninstall
cold-backup schedule install --dry-run     # 只打印将要写入的内容，不碰系统
```

- 默认 `--at 12:00`；`--kind` 不写时，macOS 用 launchd，其他平台用 cron。
- 装出来的任务每天跑一次 `<program> --daily --trigger=launchd|cron`。
- `--daily` = 补跑一次备份 + 逐份校验 + 状态检查；任何一项不过就非零退出（launchd/cron 会记下）。

## macOS（launchd）

写入 `~/Library/LaunchAgents/<label>.plist`（默认 label `com.cold-backup.daily`），
然后用 `launchctl bootstrap gui/<uid>` 加载；失败时退回 `launchctl load -w`。
日志：`<LOGDIR>/launchd.out.log` 与 `launchd.err.log`。

## Linux（cron）

往 crontab 里写一段带哨兵的受管区块，安装/卸载都只动这一段：

```
# >>> cold-backup >>>
0 12 * * * /path/to/cold-backup --daily --trigger=cron >> /path/to/schedule.log 2>&1
# <<< cold-backup <<<
```

写入策略是「先写临时文件、再 `crontab <文件>`」，失败时原 crontab 不动；写完回读一次
确认哨兵行真的在。**没有做 systemd timer** —— 需要的话自己写一个 unit 调
`cold-backup --daily` 即可，退出码语义是一样的。

## 用别的程序跑（`--program`）

默认跑的就是 `cold-backup` 自己。`--program` 让你把它交给别的可执行文件去跑：

```sh
cold-backup schedule install --program /Applications/MyBackup.app/Contents/MacOS/MyBackup
```

程序会被调用成 `<program> --daily --trigger=launchd`。

装的时候会检查这个路径**是不是可执行文件**：不是就当场警告（任务每天都会调用它，
指向一个跑不起来的路径 = 每天静默失败，而「每日任务到底跑没跑」正是这个工具要回答的问题）。
`--dry-run` 同样会检查并打印警告。

## macOS 的 TCC 坑（重要）

如果 `DEST` 在 `~/Library/CloudStorage/`（OneDrive、Google Drive、Dropbox 的新版客户端）
或 `~/Library/Mobile Documents/`（iCloud Drive）下面，那么**后台任务默认读不到那里已有的文件**：

- 写入（新建文件）通常没问题；
- 读取/修改**别的进程创建的**已有文件会被拒（EPERM）。

结果是备份看起来在跑，但轮转删不掉旧产物、`--status` 啥也看不到。
`cold-backup` 会明确报出来（`--status` 里出现 `fda-blocked`），不会假装正常。两种解法：

1. 在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里，给**运行这个任务的程序**授权；
   注意授权是绑在「可执行文件 + 签名」上的 —— 换了二进制、改了签名，都要重新授权。
2. 用一个已经拿到授权的主体去跑：`schedule install --program /path/to/那个程序`。

在终端里手动跑不受这个限制（终端本身通常已经有权限）。

## 验证装好了

```sh
cold-backup schedule status        # 任务在不在、加载没有
launchctl print gui/$(id -u)/com.cold-backup.daily | head -20   # macOS：看 state 与 last exit code
crontab -l | sed -n '/cold-backup/,+1p'                          # Linux
cold-backup --status               # 最终以「最近一次成功时间」说话
```

装完建议手动踢一次，别等第二天：

```sh
launchctl kickstart -k gui/$(id -u)/com.cold-backup.daily    # macOS
# Linux：把 crontab 里那条命令复制出来直接跑一遍
```

## 和 git 钩子一起用

定时任务是兜底，不是唯一入口。想让「每次提交都顺手备份」，在仓库的 post-commit 里调：

```sh
#!/usr/bin/env bash
[ "${COLD_BACKUP_DISABLE:-0}" = "1" ] && exit 0
command -v cold-backup >/dev/null 2>&1 || exit 0
nohup cold-backup --trigger=post-commit >/dev/null 2>&1 &
```

两点注意：

- **一定放后台**（`&`），并且把输出丢掉：钩子里同步跑备份会让每次提交卡住。
- 备份有锁（`<LOGDIR>/.lock`），并发提交时后到的实例会等锁，不会互相踩。
