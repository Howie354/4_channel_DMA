# 4_channel_DMA
实现带有BD（Buffer Description缓存描述符）的四通道DMA控制器设计，每个通道包括配置寄存器模块，源端控制模 块，缓存模块和目的端控制模块

配置寄存器（DMA_RF模块）接收CPU指令信息，通过状态机实现源端（DMA_SRC_CTRL）到缓存模块（DMA_BUF）再到目的端（DMA_DST_CTRL）的数据传输，DMA_BUF支持地址非对齐数据的处理

DMA_ARBITER模块支持四通道轮询仲裁策略，配置寄存器接口采用memory接口，数据传输采用core_bus总线

完成设计文档编写，rtl代码coding，编写Testbench，仿真验证正确

//--------------待补充文档--------------
