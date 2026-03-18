# AI\_UVM\_md

# UVM 编码规范总结（50 条）  
# 命名规范 (1-8)                                                                                                                                     

  1. 每行只放一个声明或语句

  2. 变量使用小写字母加下划线分隔（如 my\_variable）

  3. 常量使用大写字母加下划线分隔（如 MY\_CONSTANT）

  4. 实例名称只允许包含 a-z, A-Z, 0-9 和下划线

  5. 成员变量使用前缀 m\_（如 m\_data）

  6. 标准实例命名为 m\_sequencer, m\_driver, m\_monitor

  7. 使用后缀标识类型：\_env, \_agent, \_config, \_port, \_export, \_vif, \_t, \_pkg

  8. 避免在重写方法定义开头使用 virtual 关键字

#  代码结构 (9-16)

  9. 避免使用 UVM 明确标记为 deprecated 的特性

  10. 不使用内部特性（UVM Class Reference 未文档化的）

  11. 构建验证环境时聚焦于可重用性

  12. 类定义在 package 内

  13. 使用 include 指令在 package 内组织文件

  14. 避免在编译单元范围使用通配符导入

  15. 包含 uvm\_macros.svh 并导入 uvm\_pkg::\*

  16. 保持规范化的 agent 结构（每个接口一个 agent）

#  时钟与接口 (17-23)

  17. 时钟在 SystemVerilog 模块中生成，不在 UVM 类环境中

  18. 优先使用 SystemVerilog 模块而非 program

  19. 在 SystemVerilog 接口内使用 clocking blocks

  20. Driver 使用非阻塞 try\_\* 方法获取事务

  21. Monitor 不应给接口中的变量或线网赋值

  22. 在接口中使用并发断言和 cover property

  23. 使用虚接口访问 SystemVerilog 接口

# 事务 (Transaction) (24-29)

  24. 扩展 uvm\_sequence\_item 类

  25. 使用 \`uvm\_object\_utils 宏注册（放在第一行）

  26. 不使用字段宏

  27. 在类成员变量前使用 rand 限定符

  28. 重写 convert2string, do\_copy, do\_compare, do\_print, do\_record 方法

  29. 使用 factory 实例化事务

# 序列 (Sequence) (30-36)

  30. 扩展 \`uvm\_sequence 类，参数化为事务类型

  31. 在 pre\_start 和 post\_start 方法中处理初始化/清理

  32. body 方法只执行原始功能行为

  33. 不使用 \`uvm\_do 宏家族

  34. 启动 sequence 前先调用 randomize 方法

  35. 通过调用 start 方法启动 sequence

  36. 使用 \`uvm\_declare\_p\_sequencer 宏

# 激励与相位 (37-42)

  37. 使用 virtual sequence 协调多个 agent 的行为

  38. Virtual sequence 在 null sequencer 上启动

  39. Sequence 不应感知 phase

  40. 仅在覆盖 run\_phase 的方法中生成激励（driver/monitor/subscriber/scoreboard 中禁止）

  41. 在 pre\_start 中 raise objection，在 post\_start 中 drop objection

  42. 调用每个 objection 的 set\_propagate\_mode(0) 方法

# 组件 (Component) (43-46)

  43. 扩展适当的 uvm\_component 子类

  44. 使用 \`uvm\_component\_utils 宏注册

  45. 在 build\_phase 方法中实例化组件

  46. 实例化形式：var\_name = component\_type::type\_id::create("var\_name", this)

  47. 直接扩展 UVM 基类时不调用 super.build\_phase

# 连接与配置 (47-50)

  48. 虚接口封装在配置对象内

  49. 在 connect\_phase 方法中进行连接

  50. 使用配置数据库 \`uvm\_config\_db 而非资源数据库

  51. 组件在 build\_phase 中获取和设置配置参数

  52. 检查 uvm\_config\_db#(T)::get 返回的 bit

  53. 始终使用 factory 实例化 transaction/sequence/component

  54. 工厂重载形式：old\_type\_name::type\_id::set\_type\_override(new\_type\_name::get\_type())

# 测试与消息 (51-55)

  55. 测试不应直接生成激励

  56. 测试用于设置配置参数和工厂重载

  57. 使用 8 个标准报告宏之一 \`uvm\_info

  58. 消息 ID 设为静态字符串或 get\_type\_name()

  59. 默认 verbosity 设为高数值（减少消息报告）