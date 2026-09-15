# WxPayMonitor-Magisk

纯 Magisk 微信收款通知回调模块。无需安装 APK、无需开启通知读取权限。

由 root shell 周期性执行 `dumpsys notification --noredact`，筛选微信收款助手通知，
再使用 `curl` 上报到支付平台。

适配平台：[无限支付官网](https://www.ulimitx.cn)

## 功能

- 纯 Magisk shell 实现，ZIP 中不包含 APK。
- 默认仅扫描 `com.tencent.mm`。
- 默认仅匹配“微信收款助手”或“收款到账”，不会转发普通聊天通知。
- 回调失败保留本地队列，后续周期自动重试。
- 按通知标题与正文去重，避免同一条常驻通知重复上报。
- 配置每个监控周期重新读取，修改后无需重启。
- 首次启动只建立当前通知基线，不补发安装前的旧收款通知。

## 前置条件

- Android 设备已安装 Magisk。
- 系统中存在可用的 `curl`；可以另外安装 curl Magisk 模块。
- 微信已允许显示收款助手通知。

## 安装

1. 从 [Releases](../../releases) 下载 `WxPayMonitor-magisk.zip`。
2. 在 Magisk 管理器中选择“从本地安装”。
3. 刷入 ZIP 并重启手机。
4. 填写模块配置文件。

模块不会安装独立 App。

## 配置文件

固定路径：

```text
/data/adb/modules/wxpay_monitor/config/config.properties
```

模板中的平台地址、商户 ID、密钥均为空，必须按自己的支付平台后台填写：

```properties
enabled=true

platform_address=
report_api_path=/api/report/app
merchant_id=
merchant_key=
communication_key=
sign_mode=empty

monitor_period_seconds=10
curl_path=/system/bin/curl

packages=com.tencent.mm
title_keywords=微信收款助手
message_keywords=收款到账
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `platform_address` | 平台根地址，不要以 `/` 结尾 |
| `report_api_path` | 监听上报接口路径 |
| `merchant_id` | 平台要求的商户 ID 或回调标识 |
| `merchant_key` | 平台要求的回调 Token/商户密钥 |
| `communication_key` | 预留通讯密钥，当前空签名协议不会使用 |
| `sign_mode` | 当前兼容值为 `empty` |
| `monitor_period_seconds` | 扫描、配置重载和失败重试周期，默认 10 秒 |
| `curl_path` | curl 可执行文件路径；路径不可用时会从 `PATH` 查找 |
| `packages` | 允许扫描的包名，多个值使用英文逗号分隔 |
| `title_keywords` | 标题关键词，多个值使用英文逗号分隔 |
| `message_keywords` | 正文关键词，多个值使用英文逗号分隔 |

修改后最多等待一个监控周期即可生效。

## 日志与排障

运行日志：

```text
/data/adb/modules/wxpay_monitor/logs/monitor.log
```

查看模块状态：

```sh
ps -A -o PID,PPID,ARGS | grep wxpay_monitor/service.sh
tail -n 100 /data/adb/modules/wxpay_monitor/logs/monitor.log
```

日志状态：

- `BASELINE complete`：首次启动基线已建立。
- `QUEUED`：已识别收款通知并进入上报队列。
- `SENT ... HTTP=200`：平台明确返回成功。
- `RETRY`：平台未确认成功，队列将在后续周期重试。
- `ERROR curl not found`：curl 模块未启用或 `curl_path` 不正确。

部分系统会很快移除通知。如果出现漏单，可将 `monitor_period_seconds` 调低至
`2`～`5` 秒，并关闭微信通知折叠、通知隐藏及省电限制。

## 构建

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

产物：`dist/WxPayMonitor-magisk.zip`。

构建脚本会排除 APK、签名文件和本地构建目录。

## 隐私与安全

- 只读取 Android 当前通知列表，不读取微信数据库。

## 许可证

本项目使用 MIT License。
