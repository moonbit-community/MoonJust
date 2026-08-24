# Phase 12 收口报告

## 结论

Phase 12 的功能、兼容、测试治理、源码布局、稳定 API、文档和发布审计
收口已完成。产品主交付物是 `cmd/just` Native/wasm1 二进制；稳定的可选
嵌入入口是 `ZSeanYves/MoonJust/api`。本报告合并并取代
`FINAL_RELEASE_REVIEW.md` 与 `PLATFORM_COMPATIBILITY.md` 的最终结论，
后两者只保留入口，避免最终状态漂移。

以下内容绑定本报告所在的 `main` 收口提交及其精确 head CI/RC evidence；
工作流必须
使用 CI 提供的 head SHA，不能使用 merge SHA、默认分支 SHA 或缺失 SHA。

## 固定基线与身份

- 上游：`just 1.57.0`
- 上游提交：`e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- MoonBit 模块：`ZSeanYves/MoonJust`
- MoonBit 模块元数据版本：`0.1.0`（Moon 工具链要求无 `v` 前缀）
- 产品与发布标签版本：`v0.1.0`
- GitHub 仓库 URL：`https://github.com/moonbit-community/MoonJust`
- 稳定接口：`ZSeanYves/MoonJust/api`
- completion：明确排除

本次工作开始前，候选分支 `codex/windows-runtime-performance` 的提交和
未提交实验改动保存在独立 stash，没有合并或带入 `main`。布局迁移从
`main` 基线 `6ac1e27ee288957fa9ec956d6847d60e56d8ba09` 开始。

## 源码布局与公共面

所有实现包已审查式重命名为 `src/*`，不存在第二套 `internal/*` 实现。
`moon.pkg`、生成接口、工具、CI、compat 清单、上游清单、coverage 合并器
和文档引用均已同步。生成的重复 `pkg.generated N.mbti` 与临时测试文件已
删除。

`api/pkg.generated.mbti` 与迁移前接口逐项比较，函数、错误、字段和方法集合
保持不变，仅模块路径从旧坐标变为 `ZSeanYves/MoonJust/api`。实现包保留
跨包编译、协议实现和 black-box 契约所需的 `pub`；没有发现可以安全私有化
而不改变这些契约的声明。架构检查确保 parser、AST、semantic、evaluator、
host 和 executor 实现类型不会泄漏到 facade。

## C 代码清理

生产 `src/host_native/platform.c`、`realpath.c` 和 `transaction.c` 已删除，
对应能力迁移到 MoonBit native/portable 文件，并只通过系统标准 ABI 或已批准的
`moonbitlang/async`/`moonbitlang/x/fs` 后端完成平台调用。保留的项目 C 清单严格为：

- `src/host_process/process_group.c`
- `src/host_process/signal_forward.c`
- `spikes/host-async/process_lifecycle/process_lifecycle.c`
- `spikes/host-async/signal_probe/signal_probe.c`

Native 迁移保持了 realpath 的符号链接与错误行为、范围读取的 EOF/短读边界、
独占临时文件、Full sync、覆盖写权限继承、只读目标拒绝、no-overwrite 原子失败、
executable 处理和临时文件清理。POSIX 路径传入 libc 时显式附加 NUL；Windows
路径使用宽字符 API，并覆盖驱动器和 UNC 前缀。测试辅助已从生产 C 导出中移到
`native_test.mbt`，不再产生项目自有测试桩。

静态审计命令：

```text
git ls-files '*.c' '*.h'
rg -n 'native-stub|moonjust_host_|extern "C"|extern "c"' src tools
```

审计结果：删除的 `moonjust_host_*` 符号和 `src/host_native` native-stub 均为
零；剩余 `native-stub` 只出现在允许的 process 桩和两个 spike 包。外部 libc
符号声明属于 MoonBit FFI 适配，不是项目自有 C 文件或新增第三方依赖。

## 测试治理与命名

16 个原 `coverage_test.mbt`/`coverage_wbtest.mbt` 已按行为重命名为诊断、
恢复、表达式、规划、输出、错误、图发现、项目属性等测试文件。测试名称和
fixture 不再以 coverage 命名；错误测试使用 code、span、exit code 和诊断
一致性断言，输出测试使用关键内容或 round-trip 断言。

新增 `tools/quality/check_naming.py`，仅使用 Python 标准库检查 MoonBit 源
文件、函数/方法和常量命名，并纳入统一 runner 的 `fast` DAG；其自测覆盖
通过和违规两种情况。当前生产 MoonBit 命名审计无违规。

## 跨平台与上游兼容

支持矩阵为 Linux x86_64、macOS arm64、Windows x86_64 Native，以及一个
Ubuntu 构建、由三平台 gate 消费并校验哈希的共享 wasm1 产物。Native、平台、
signal、process 和 interactive evidence 不跨主机缓存。官方差分固定使用
上游提交，completion 单独排除。

Native 与共享 wasm1 的完整行为结果均为零未登记失败。Linux MoonX 在无效
UTF-8 cwd 的两个上游场景仍为明确 `not-applicable`：

- `non_unicode::warn_for_non_unicode_invocation_directory`
- `non_unicode::warn_for_non_unicode_justfile_path`

这是 MoonX 宿主边界限制，不是 MoonJust 的兼容失败。macOS `arm64`/Rust
`aarch64` 和 Windows 路径/换行行为均由平台化测试覆盖；不使用 workload
特判或结果硬编码。

## 本地二次复检

迁移后以下检查通过：

```text
moon info
moon fmt
moon fmt --check
moon check --target all --warn-list +73 --deny-warn
moon test --target native       # 1119 passed, 0 failed
moon test --target wasm         # 1097 passed, 0 failed
python3 tools/quality/check_naming.py
python3 tools/quality/check_naming_test.py
python3 tools/runner.py run --mode fast
```

`fast` runner 覆盖格式、架构边界、命名、全目标检查和工具测试；统一 evidence
必须绑定最终 head SHA 后，才能作为远端阶段出口。verify、compat、release
仍按同一 runner 和精确 SHA 协议执行。

本次迁移后的二次本地复检还通过了 host_native 定向 9/9、全量 Native
1119/1119、全量 Wasm 1097/1097、`moon check --target all --warn-list +73
--deny-warn`、命名/架构检查，以及上游 2,417 条注册清单和官方差分 smoke。
Release/三平台 artifact evidence 仍须由精确 head 的 CI/RC 提供，不能由本机
macOS 结果替代。官方 signal gate 在空闲重跑中通过 14/14；完整官方 harness
在 macOS 的 `dotenv::fifo` 仍受本机 environment-source/FIFO 能力限制，表现为
上游测试自身的环境读取返回码差异，Linux CI 是该项的权威验证主机。该本机限制
没有改变此次 host-native C 清理的定向测试、Native/Wasm 全量测试或其他兼容门禁。

## 性能、体积与发布例外

本阶段不继续处理体积和 Windows Native 性能。当前候选体积约为冻结绿色
基线的 1.1x，体积门禁保持独立可见，不降低阈值。Windows `dag-1000` 与
`project-parameters` 的性能问题保留为已知例外；它们不改变功能或跨平台
兼容结论。权威性能应使用云端 RC workflow 的冷启动/warm 交错数据，不以
维护者个人电脑绝对延迟作为发布事实。

## 远端出口

直接在 `main` 进行三个逻辑提交并普通推送，禁止 force push。每个提交和最终
head 都必须等待对应精确 SHA 的主分支 CI 与 RC；功能、兼容、覆盖率、警告、
重复性、工具和官方差分 job 必须成功。体积门禁与上述 Windows 性能例外必须
在 evidence 中显式可见，不能隐藏或放宽。

历史阶段证据继续保留在各 `PHASE_*_REPORT.md`；当前发布入口为本报告和
[`RELEASE_AUDIT.md`](RELEASE_AUDIT.md)。
