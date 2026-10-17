# 功能对照

基准：DeskMinder 2.0.9，本机已核对五页设置、五步引导与两段动画。补充来源：[官网](https://deskminder.appps.od.ua/)、[官方版本记录](https://apps.apple.com/us/app/deskminder-reminders-tasks/id6740942938?mt=12)。

| 模块 | 实现位置 | 内容 |
|---|---|---|
| 创建 | Widget.swift、WidgetInteraction.swift、WidgetSupport.swift、Core.swift | 加号、五态交互、126×34 紧凑起点、4 点／分钟连续拉伸 1–99、释放后无手柄、输入 1–999、具体时刻、空标题、多个计时、模式切换、Tab/↑/↓/Return/Escape |
| 活动项目 | Widget.swift | 分钟、截止时间、圆环、全文任务、独立底部提示完整标题、六项竖向加时、历史明确完成、稳定叉号取消、数量较多时水平滚动 |
| 浮窗 | App.swift、WidgetLayout.swift、WidgetInteraction.swift | NSPanel、暗色原生玻璃、线性 SF Symbols、设置期间浮窗／加号常显与实时尺寸预览、加号靠近唤出与 800ms 后直接隐藏、4 点阈值拖动保存、编辑状态保留草稿／焦点、显式激活键盘窗口、上下边缘移动、64 点动画画布与实际完成回收、统一右键菜单、顶部／底部／自定义、显示器、尺寸、全屏检测、桌面常驻或快捷唤出 |
| 菜单栏 | App.swift | 最近到期项目、悬停文本、图标动画、左键唤出、右键菜单 |
| 到期通知 | App.swift、SystemServices.swift | 后台置前并确认窗口可见、全屏模糊渐变、系统通知、声音、预览、10 秒自动关闭、稍后 1/5/7/10/15/30 分钟 |
| 专注音频 | Audio.swift | 原版四个背景音，AVAudioPlayer 单实例循环；切换替换、最后一个运行项目结束时停止 |
| 操作音／触感 | Audio.swift | drag-sound 拉伸；funky 创建；pong 收拢／完成；notification 到期；音效与触感开关 |
| 历史 | History.swift | 全部／提醒／任务、搜索、日期分组、活动／到期／完成／取消／已提醒结束、任意分钟加时、单项删除确认、清空已结束项目确认 |
| Apple 联动 | SystemServices.swift、AppModel.swift | 仅创建和管理本应用绑定条目；截止时间更新、主动完成、取消删除、已绑定条目外部完成回传 |
| 系统快捷键 | Settings.swift、SystemServices.swift | Carbon 注册六组快捷键；录制／清除／冲突提示；四个可编辑快速时长，初始 5/10/15/25 |
| 开机启动 | AppModel.swift | SMAppService.mainApp，默认关闭；权限／注册错误可见 |
| 设置 | Settings.swift | 通用、通知、专注、快捷键、关于；中英文切换 |
| 引导 | Onboarding.swift | 五步；使用本应用的毛玻璃、形变和圆环绘制演示创建与模式切换 |
| 可靠性 | Core.swift、AppModel.swift | SQLite 持久化、截止时间校准、唤醒核对、修订号与投递收据、排队提醒显示后记录收据、通知异步取消保护 |

## 有意保留的边界

- 第一版不迁移原版数据，不导入 Apple 提醒事项的新条目。自定义位置也保留尺寸滑块。
- 关于页为灵提醒自己的信息；没有原应用授权、购买或自动更新服务。
- 系统横幅的显示时长及最多四个操作由 macOS 控制；完整六个稍后选项在模糊提醒和历史中提供。
- 原音频字节保持一致。通知专用 CAF 为系统要求的 PCM 转码，背景音不转码。
- 全屏检测使用公开窗口元数据，无屏幕录制权限。其他应用的特殊窗口布局可能需要在实际使用中继续核验。
- 第一版动画和原生拖拽为独立重写的形变／回弹／提交过渡；没有将原版视频作为新应用组件。精细视觉一致性仍需使用者对照评价。


## 0.3.0 视觉更新

设置侧栏、系统分组内容、尺寸比例、HUD 浮窗材质、tooltip 提示材质、全屏 UI 材质，以及统一的历史与引导排版。系统辅助功能环境参与材质和动效选择；本轮未实测全部组合。旧交互、声音、图标及计时历史保持，设计与验证分别见 DESIGN.md、VERIFICATION.md。
