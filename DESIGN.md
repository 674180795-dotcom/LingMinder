# 0.3.0 材质与界面设计

设计采用安静、轻盈的桌面工具风格：彩色品牌图标是主要视觉锚点，功能界面使用系统强调色、细线图标和有节奏的留白。保留原有紧凑浮窗尺寸与交互，不增加闲置、提交或收拢动画。

## 来源与采用范围

- [Apple Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials)：材质用于表达层次，操作与导航浮于内容之上；内容区保持可读，按用途选择原生材质，尊重辅助功能设置。
- [Apple Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)：优先标准组件，减少自定义背景，分别检查可读性、透明度与动态效果。
- [liquid-glass-skills](https://github.com/YordiLorenzo/liquid-glass-skills)：阅读主技能、版本可用性、AppKit 与旧系统回退章节；以 Apple 文档和本机 SDK 声明核验版本要求。没有执行仓库安装命令或引入第三方依赖。

本机构建仍固定使用 macOS 15.5 SDK，真机是 macOS 15.8.1。原生 `NSGlassEffectView` 需要 macOS 26；本机 26.2 SDK 的 AppKit 头文件也明确标注这个版本。本次交付使用 `NSVisualEffectView`，属于标准模糊材质，**没有实现或宣称原生 Liquid Glass 的折射与合并效果**。未来升级 SDK 和系统时，需单独采用并验证新 API；当前版本运行于 macOS 26 也不会自动变成自定义 Liquid Glass。

## 界面分工

| 界面 | 实现与目的 |
|---|---|
| 桌面浮窗 | `.hudWindow`、窗口外背景混合、低强度染色、单条渐变细边缘。固定浅色前景，保持在复杂桌面上的辨识度。 |
| 标题提示 | `.toolTip` 语义材质；保留独立窗口、换行与屏幕边界处理。 |
| 设置侧栏 | `.sidebar`、窗口内背景混合，跟随系统深浅色；图标 20 点，统一导航行与选中状态。 |
| 设置内容 | 系统窗口背景与控件背景，普通分组面板，不叠加多层玻璃；系统开关、选择器、滑块和按钮。 |
| 全屏提醒 | `.fullScreenUI` 原生背景模糊与较轻的深色渐变；大标题、细类型标签、主次按钮层级，保留倒计时圆环和稍后菜单。 |
| 历史与引导 | 统一字体、间距与强调色；引导内的深色浮窗演示使用浅色文字，释放后示意提交图标。 |

## 辅助功能与行为边界

降低透明度时，浮窗和全屏背景回退为实色。提高对比度时，增加背景遮罩和内容面板边缘对比。减少动态效果时，关闭引导循环演示，并让拖拽释放即时结束形变；不改变计时或输入行为。不修改系统偏好。

品牌图标、状态栏图标、全部音频素材与播放核心保留。输入焦点、拖动移动、动画留白、设置期间常显、真实到期投递、Apple 绑定与历史状态继续沿用已有逻辑。实际验证范围见 [VERIFICATION.md](VERIFICATION.md)。
