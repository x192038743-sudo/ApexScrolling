# 验证证据（原始日志）

这些是开发过程中真实运行产生的日志，用于复核结论，不参与构建。

| 文件 | 说明 |
|---|---|
| `acc5.log` / `acc_fix.log` | Android 模拟器上的端到端验收日志（`integration_test/beta_acceptance_test.dart`）。`acc5.log` 为修复前最后一次成功运行，`acc_fix.log` 为修复 `UnmountedRefException` 后的运行。 |
| `soak1.log` / `soak_fix.log` | 连续上滑 50 张的压测日志（`integration_test/feed_soak_test.dart`）：耗时、最慢单张、六源分布。 |
| `howto_before.txt` / `howto_after2.txt` | 「实用技能」源质量抽样对比：修正前 vs 加入实用主题白名单与会话去重之后。 |

复现方式见 [../测试版说明.md](../测试版说明.md) 第 4 节。
