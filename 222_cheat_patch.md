# 222 作弊需要修改的文件与补丁对照表

## 需要修改的文件（相对 222.ipa 内部）

| 操作 | 路径 | 说明 |
|---|---|---|
| **新增** | `Payload/cf.app/Frameworks/CFCheatHook.dylib` | 运行时 hook 动态库，包含全部 6+1 条 patch 逻辑 |
| **修改** | `Payload/cf.app/cf` | 在 Mach-O 的 `LC_LOAD_DYLIB` 列表追加 `@executable_path/Frameworks/CFCheatHook.dylib`（由 `insert_dylib` 完成），使 iOS 启动时加载 |
| **重签** | `Payload/cf.app/_CodeSignature/` 及所有 Mach-O | ad-hoc 签名，TrollStore 可直接安装 |

## 补丁对照：111 二进制 patch → 222 运行时 patch

| # | 111（二进制 patch，偏移→字节） | 222（运行时 hook，按方法定位后写指令） |
|---|---|---|
| 1 | `0x171A48C`: `ff0301d1` → `c0035fd6`（`sub sp`→`ret`） | 找 `WNGameBase.WNTradingHouseSystem.UITradingSystemController::FindItemInPutOnNewTab`，入口写 `ret` (`0xD65F03C0`) |
| 2 | `0x4D314CC`: `20` → `00`（`mov w0,#1`→`#0`） | 找 `WNFrontEndGame.PetAssiActivityItemContentController::GetViewAssetId`，入口写 `mov w0,#0; ret` |
| 3 | `0x4E0F838`: 15 字节，强制 `x1=1, s0=0, s2=0` | 找 `WNFrontEndGame.NavigationControllerUtil::CheckRoleItemIDAvailable`，入口写 `mov w1,#1; fmov s0,wzr; fmov s2,wzr; b原逻辑` |
| 4 | `0x4EC88C4`: `fmul s9,s0,s1` → `fmul s9,s1,s1` | 找 `IIPSMobile.IIPSMobilePufferInterface::PufferPluginSetFileStatus`，函数内扫描 `0x1E210809` 改为 `0x1E210829` |
| 5 | `0x4FF1BD8`: `ff4301d1` → `c0035fd6`（`sub sp`→`ret`） | 找 `gcloud_voice.GCloudVoiceEngine::JoinTeamRoom`，入口写 `ret` |
| 6 | `0x51B38E9`: `blr x9` → `mov w0,#1` | 找 `WNGameBase.WeaponGadgetSkillController::< >xLuaBaseProxy_GetViewAssetId`，入口写 `mov w0,#1; ret` |
| 7 | `0x7FAA721`: `ldr s0,[x0,#0x78]` → `fmov s0,#1.5` | 引擎层 getter，无 IL2CPP 方法名，**222 成品中未复刻**（patch 1/3/6 已覆盖主要作弊路径） |

## 222 中目标方法的定位信息（来自 global-metadata.dat v29）

- 方法表：偏移 `13876096`、stride `32`、token 字段在条目 `+20`
- 字符串表：偏移 `2528028`；类型表：偏移 `49022740`、stride `88`
- 目标方法索引：P1=196077, P2=115569, P3=118769, P4=44942, P5=41706, P6=164550
- 222 导出的关键 API：`il2cpp_domain_get`, `il2cpp_domain_get_assemblies`, `il2cpp_assembly_get_image`, `il2cpp_class_from_name`, `il2cpp_class_get_method_from_name`（均由 `UnityFramework` 导出）

## 构建环境要求

- macOS + Xcode Command Line Tools
- Theos（`export THEOS=~/theos`）
- `insert_dylib`（注入 LC_LOAD_DYLIB）
- `ldid` 或 `codesign`（ad-hoc 签名）
- 成品用 **TrollStore** 安装

## 验证方法

安装后打开游戏，通过 macOS 控制台/ syslog 过滤 `[CFCheat]` 标签，应看到 6 条 `patched @0x...` 日志；若出现 `METHOD NOT FOUND` 说明类名/方法名在后续版本有变动，需重新解析 metadata 更新 `cheat_hook.m` 中的字符串。
