 Here is Claude's plan:                                                                                                                                                            
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 AXI4 MASTER VIP 实施计划                                                                                                                                                          
                                                        
 修改记录

 ┌──────┬────────────┬──────────────────────────────────────────┐
 │ 版本 │    日期    │                 修改内容                 │
 ├──────┼────────────┼──────────────────────────────────────────┤
 │ v1.0 │ 2026-03-19 │ 初始计划                                 │
 ├──────┼────────────┼──────────────────────────────────────────┤
 │ v1.1 │ 2026-03-19 │ 移除scoreboard和coverage，仅保留编译目标 │
 ├──────┼────────────┼──────────────────────────────────────────┤
 │ v1.2 │ 2026-03-19 │ VCS添加-LDFLAGS -Wl,--no-as-needed选项   │
 ├──────┼────────────┼──────────────────────────────────────────┤
 │ v1.3 │ 2026-03-19 │ 添加VIP使用说明到README.md               │
 └──────┴────────────┴──────────────────────────────────────────┘

 1. 项目背景

 基于 AXI4_MASTER_VIP_SPEC.md 规格文档，创建一个完整的AXI4 Master VIP。VIP需支持完整的AXI4协议功能，包括多种突发类型、非对齐传输、突发拆分、带宽统计等高级特性。

 目标: 生成完整的VIP代码并使用VCS编译通过。

 2. 目录结构

 ai_cc_glm5_axi4_vip/
 ├── doc/                          # 协议参考文档（已存在）
 ├── sv/
 │   ├── axi4_pkg.sv               # 主包文件
 │   ├── axi4_if.sv                # AXI4接口定义（含SVA断言）
 │   ├── axi4_types.sv             # 类型定义和枚举
 │   ├── axi4_transaction.sv       # 事务类
 │   ├── axi4_config.sv            # 配置类
 │   ├── axi4_master_driver.sv     # Master驱动器
 │   ├── axi4_monitor.sv           # 监视器
 │   ├── axi4_sequencer.sv         # 序列器
 │   ├── axi4_master_agent.sv      # Master Agent
 │   ├── axi4_env.sv               # 环境类
 │   ├── axi4_base_sequence.sv     # 基础序列
 │   └── axi4_base_test.sv         # 基础测试
 ├── tb/
 │   ├── tb_top.sv                 # 测试平台顶层
 │   └── dut_slave_model.sv        # 简单从设备模型
 ├── Makefile                      # VCS编译脚本
 └── README.md                     # 使用说明（已存在）

 3. 核心组件设计

 3.1 axi4_types.sv - 类型定义

 - axi4_burst_type_e: FIXED(0), INCR(1), WRAP(2)
 - axi4_resp_type_e: OKAY(0), EXOKAY(1), SLVERR(2), DECERR(3)
 - axi4_transaction_type_e: READ, WRITE
 - 参数化宏定义：DATA_WIDTH, ADDR_WIDTH, ID_WIDTH

 3.2 axi4_config.sv - 配置类

 支持以下配置参数：
 - data_width: 数据位宽（默认128位）
 - addr_width: 地址位宽（默认32位）
 - id_width: ID位宽（默认4位）
 - max_outstanding: 最大未完成事务数
 - min_interval: 事务发送间隔周期
 - support_data_before_addr: 是否支持数据先发
 - data_before_addr_osd: 数据先发数量限制
 - rtimeout: 读超时阈值
 - wtimeout: 写超时阈值
 - enable_split: 是否启用突发拆分
 - split_burst_len: 拆分后最大突发长度（默认32）

 3.3 axi4_transaction.sv - 事务类

 字段包括：
 - 地址、数据、突发类型、突发长度
 - 事务大小(SIZE)、ID、QoS、保护属性
 - WSTRB掩码、响应状态
 - 统计信息：开始时间、结束时间、延迟

 3.4 axi4_if.sv - 接口与断言

 AXI4信号定义（分离读写通道）：
 - 写地址通道：AWADDR, AWLEN, AWSIZE, AWBURST, AWID, AWVALID, AWREADY等
 - 写数据通道：WDATA, WSTRB, WLAST, WVALID, WREADY等
 - 写响应通道：BRESP, BID, BVALID, BREADY等
 - 读地址通道：ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY等
 - 读数据通道：RDATA, RRESP, RLAST, RID, RVALID, RREADY等

 实现12条SVA断言

 3.5 axi4_master_driver.sv - 驱动器

 核心功能：
 1. 从sequencer获取事务
 2. 处理突发拆分（INCR>16拆分、2KB边界拆分）
 3. 处理非对齐传输
 4. 执行AXI4时序驱动
 5. 支持数据先于地址发送
 6. 超时检测与上报

 3.6 axi4_monitor.sv - 监视器

 核心功能：
 1. 被动监控总线信号
 2. 重建事务对象
 3. 收集带宽利用率统计
 4. 收集延迟统计（最大/平均读写延迟）
 5. 事务完成时输出统计信息

 3.7 axi4_sequencer.sv - 序列器

 标准UVM sequencer实现

 3.8 axi4_master_agent.sv - Agent

 包含：driver, sequencer, monitor
 支持active/passive模式配置

 3.9 axi4_env.sv - 环境

 顶层容器，实例化和连接所有组件

 3.10 axi4_base_sequence.sv - 基础序列

 提供基础读写序列模板

 3.11 axi4_base_test.sv - 基础测试

 提供基础测试用例模板

 4. Feature实现清单

 ┌─────┬─────────────────────────┬────────────────────────────────────────────┐
 │  #  │         Feature         │                  实现位置                  │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 1   │ INCR/FIXED/WRAP突发类型 │ axi4_transaction.sv, axi4_master_driver.sv │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 2   │ 非对齐传输              │ axi4_master_driver.sv                      │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 3   │ WSTRB掩码               │ axi4_transaction.sv, axi4_master_driver.sv │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 4   │ 突发拆分(split)         │ axi4_master_driver.sv                      │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 5   │ 总线参数配置            │ axi4_config.sv                             │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 6   │ 2KB地址边界拆分         │ axi4_master_driver.sv                      │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 7   │ 带宽利用率统计          │ axi4_monitor.sv                            │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 8   │ 读写延迟统计            │ axi4_monitor.sv                            │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 9   │ 数据先于地址发送        │ axi4_master_driver.sv                      │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 10  │ 事务超时配置            │ axi4_master_driver.sv, axi4_monitor.sv     │
 ├─────┼─────────────────────────┼────────────────────────────────────────────┤
 │ 11  │ 12条SVA断言             │ axi4_if.sv                                 │
 └─────┴─────────────────────────┴────────────────────────────────────────────┘

 5. Makefile设计

 # 使用VCS仿真器
 SIM = vcs

 # 文件列表
 SV_FILES = sv/axi4_types.sv \
            sv/axi4_config.sv \
            sv/axi4_transaction.sv \
            sv/axi4_if.sv \
            sv/axi4_sequencer.sv \
            sv/axi4_monitor.sv \
            sv/axi4_master_driver.sv \
            sv/axi4_master_agent.sv \
            sv/axi4_env.sv \
            sv/axi4_base_sequence.sv \
            sv/axi4_base_test.sv \
            sv/axi4_pkg.sv

 TB_FILES = tb/dut_slave_model.sv tb/tb_top.sv

 # VCS编译选项
 VCS_OPTS = -full64 -sverilog +incdir+sv -timescale=1ns/1ps \
            -debug_access+all -kdb -lca -ntb_opts uvm-1.2 \
            -LDFLAGS -Wl,--no-as-needed

 # 编译目标
 compile:
        vcs $(VCS_OPTS) $(SV_FILES) $(TB_FILES) -l compile.lo

 # 清理
 clean:
        rm -rf *.log *.key *.vpd DVE csrc simv* *.vdb AN.D

 .PHONY: compile clean

 6. 实施步骤

 Phase 1: 基础框架

 1. 创建目录结构
 2. 实现 sv/axi4_types.sv
 3. 实现 sv/axi4_config.sv
 4. 实现 sv/axi4_transaction.sv
 5. 实现 sv/axi4_if.sv（含SVA断言）

 Phase 2: 核心组件

 6. 实现 sv/axi4_sequencer.sv
 7. 实现 sv/axi4_master_driver.sv
 8. 实现 sv/axi4_monitor.sv

 Phase 3: 高层组件

 9. 实现 sv/axi4_master_agent.sv
 10. 实现 sv/axi4_env.sv

 Phase 4: 序列与测试

 11. 实现 sv/axi4_base_sequence.sv
 12. 实现 sv/axi4_base_test.sv
 13. 实现 sv/axi4_pkg.sv

 Phase 5: 测试平台

 14. 实现 tb/dut_slave_model.sv
 15. 实现 tb/tb_top.sv
 16. 创建 Makefile
 17. 更新 README.md（添加VIP使用说明）

 Phase 6: 编译验证

 18. 运行VCS编译
 19. 如编译报错，修复SV代码直至编译通过

 7. 验证方法

 1. 使用VCS编译所有SV文件
 2. 检查编译日志，确保无错误
 3. 如编译报错，按错误类型修复：
   - 语法错误：修正语法
   - 类型不匹配：修正类型声明
   - 未定义引用：添加缺失声明
 4. 循环修复直到编译通过

 8. README.md 使用说明

 README.md将包含以下内容：

 # AXI4 MASTER VIP

 ## 简介
 基于UVM的AXI4 Master VIP，支持完整的AXI4协议特性。

 ## 目录结构
 - sv/: VIP源代码
 - tb/: 测试平台
 - doc/: 协议参考文档

 ## 编译
 make compile

 ## 清理
 make clean

 ## 配置参数
 在axi4_config中可配置：
 - data_width: 数据位宽（默认128位）
 - addr_width: 地址位宽（默认32位）
 - id_width: ID位宽（默认4位）
 - max_outstanding: 最大未完成事务数
 - min_interval: 事务发送间隔周期
 - rtimeout/wtimeout: 读写超时阈值

 ## 使用示例
 1. 在testbench中实例化axi4_if接口
 2. 通过uvm_config_db设置配置和接口
 3. 在test中启动sequence执行读写事务