# 开屏广告清理 · SplashAdKiller

一个通用的 iOS 越狱插件：**自动跳过第三方 App 的开屏广告**。

装一次，全设备生效，不需要为每个 App 单独写规则。

- 冷启动：开屏广告界面不再停留，直接进主页
- 热启动：从后台切回来时弹出的开屏广告同样处理
- 只作用于第三方 App，不碰 SpringBoard 和系统应用
- 同时支持 **rootful** 和 **rootless** 越狱

> 仅限个人设备自用。部分 App 的服务条款可能不允许去除广告，风险自负。

---

## 一、它到底做了什么

没有去抓某个 App 的私有接口，也没有硬编码某一家广告 SDK，而是用三层「软」手段，从不同角度覆盖：

| 层 | 做法 | 覆盖的场景 |
| --- | --- | --- |
| ① 控制器层 | Hook `UIViewController`，发现类名像开屏广告的控制器（`SplashAdViewController`、`BUSplashAdView`…），出现即关闭 | 独立全屏广告页 |
| ② 点击层 | 启动后 12 秒内持续扫描可见窗口，找到文案为「跳过 / Skip」的控件并触发点击 | 带倒计时按钮的贴片式开屏 |
| ③ 遮挡层 | 在广告容器里把占屏 40% 以上的大图 / 视频视图设为透明 | 广告已经铺满但「跳过」还没出现的几秒 |

配套的保护：

- 只注入含 `UIApplication` 的进程，系统守护进程完全不加载
- `com.apple.*` 的系统 App 直接跳过
- 支持按 Bundle ID 黑名单 / 白名单
- 类名里带 `config`、`manager`、`request`、`cache` 等词的不拦截，避免误杀

---

## 二、目录结构

```
splash-ad-killer/
├── Tweak.xm                          # Logos Hook：控制器拦截
├── SADCore.h / SADCore.m             # 引擎：类名识别、自动点击、遮挡
├── SplashAdKiller.plist              # 注入过滤器（只进含 UIApplication 的进程）
├── Makefile                          # Theos 编译配置
├── control                           # deb 包元信息
├── config/
│   └── com.dsh.splashadkiller.plist  # 默认配置（可选，装到手机上）
├── scripts/build.sh                  # macOS 本地编译脚本
└── .github/workflows/build.yml       # GitHub Actions 自动编译
```

---

## 三、编译出 deb（推荐，Windows 也能用）

你手上没有 Mac 也没关系，用 GitHub 的免费 macOS 机器编译。

### 1. 建一个仓库

1. 打开 <https://github.com/new>
2. Repository name 随便填，例如 `SplashAdKiller`
3. 选 **Public**（私有仓库的 Actions 会消耗额度）
4. 不要勾选任何初始化文件，直接 **Create repository**

### 2. 把文件传上去

**方法 A：网页拖拽（最简单）**

1. 在新建的空仓库页面点 **uploading an existing file**
2. 把 `splash-ad-killer` 文件夹里的**所有内容**拖进去（不是拖文件夹本身，要拖里面的文件）
3. 注意 `.github` 是隐藏文件夹，Windows 资源管理器里要先开启「显示隐藏项目」才能看到
4. 点 **Commit changes**

**方法 B：GitHub Desktop**

1. 安装 [GitHub Desktop](https://desktop.github.com/)
2. `File → Add local repository`，选中 `splash-ad-killer` 文件夹
3. 点 **Publish repository**，取消勾选 “Keep this code private”

**方法 C：命令行**

```bash
cd splash-ad-killer
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/SplashAdKiller.git
git push -u origin main
```

### 3. 等编译完成

1. 打开仓库页面 → 顶部 **Actions**
2. 会看到一条 `Build tweak` 正在跑，等它变成绿色对勾（第一次要下载 iOS SDK，约 10–20 分钟）
3. 点进去，页面底部 **Artifacts** 里有两个压缩包：
   - `SplashAdKiller-rootful` → 给 unc0ver / Taurine / checkra1n
   - `SplashAdKiller-rootless` → 给 Dopamine / palera1n rootless

### 4. 装到手机

把对应压缩包解压，得到 `.deb`，用下面任意一种方式安装：

- **Filza**：把 deb 传到手机，点开 → 右上角「安装」
- **Sileo / Zebra**：`Sources` 里添加本地文件，或直接用 Filza 打开
- **SSH**：`scp` 传上去后执行 `dpkg -i xxx.deb`

装完执行一次 **Respring**（Sileo 装完一般会提示），然后把目标 App 从后台彻底划掉再打开。

---

## 四、有 Mac 的话本地编译

```bash
# 一次性准备
brew install ldid xz dpkg
git clone --recursive https://github.com/theos/theos.git ~/theos
git clone --depth 1 https://github.com/theos/sdks.git ~/theos/sdks
export THEOS=~/theos

# 编译
cd splash-ad-killer
./scripts/build.sh rootless   # 或 rootful
```

产物在 `packages/` 目录。

---

## 五、装哪个版本？

在手机上用 Filza 或 SSH 看一眼：

```bash
ls -d /var/jb
```

- **存在 `/var/jb`** → rootless（Dopamine、palera1n rootless、XinaA15 等），装 `iphoneos-arm64`
- **不存在** → rootful（unc0ver、Taurine、checkra1n、palera1n rootful），装 `iphoneos-arm`

装错版本不会变砖，但插件不会生效，卸载重装即可。

---

## 六、配置（可选）

默认全部开启，开箱即用。需要微调时，编辑这个文件：

```
/var/mobile/Library/Preferences/com.dsh.splashadkiller.plist
```

用 Filza 直接编辑，或者用 NewTerm / SSH 执行 `defaults`：

```bash
# 临时关闭整个插件
defaults write com.dsh.splashadkiller Enabled -bool false

# 只关闭自动点击，保留控制器拦截
defaults write com.dsh.splashadkiller AutoSkip -bool false

# 把某个 App 加入黑名单（不处理它）
defaults write com.dsh.splashadkiller DisabledBundles -array com.tencent.xin com.eg.android.AlipayGphone

# 只对某几个 App 生效（白名单，非空时优先级高于黑名单）
defaults write com.dsh.splashadkiller EnabledBundles -array com.zhihu.ios

# 某个 App 的开屏类名不在内置关键词里，补充关键词
defaults write com.dsh.splashadkiller ExtraKeywords -string "MyAppLaunchAd,XXWelcomeAd"
```

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `Enabled` | bool | `true` | 总开关 |
| `AutoSkip` | bool | `true` | 自动点「跳过」 |
| `BlockControllers` | bool | `true` | 拦截开屏广告控制器 |
| `MaskAdContent` | bool | `true` | 遮挡广告画面 |
| `HotStart` | bool | `true` | 处理热启动广告 |
| `VerboseLog` | bool | `false` | 输出调试日志 |
| `LaunchWindow` | number | `12` | 启动后监听秒数（3–30） |
| `ExtraKeywords` | string | 空 | 额外类名关键词，逗号分隔 |
| `DisabledBundles` | array | 空 | 不处理的 App |
| `EnabledBundles` | array | 空 | 只处理的 App |

> 配置是在 **App 进程启动时**读取的。改完必须把 App 从后台彻底划掉再打开，热启动不算。

---

## 七、调试

1. 打开日志：

```bash
defaults write com.dsh.splashadkiller VerboseLog -bool true
```

2. Mac 连上手机看日志：

```bash
log stream --device --predicate 'subsystem == "com.dsh.splashadkiller"'
```

或者用 `idevicesyslog | grep SAD`。

3. 正常会看到类似：

```
[SAD] 开始监听 (launch, 12 秒)
[SAD] 关闭开屏广告控制器: ZHLSplashAdViewController
[SAD] 点击跳过: 跳过 3 (UIButton)
```

哪个 App 没效果，就看它启动时打印的类名，把特征词补进 `ExtraKeywords`。

---

## 八、已知限制 / 排错

| 现象 | 原因与处理 |
| --- | --- |
| 某 App 卡在启动页或闪退 | 拦截了它自己的启动控制器。把 Bundle ID 加进 `DisabledBundles` |
| 广告没了，但界面空白几秒 | 遮挡层把广告画面透明了，等「跳过」出现就会关。可以把 `MaskAdContent` 设为 `false` |
| 完全没反应 | 先确认装的是 rootful 还是 rootless 版本；再确认 App 已彻底重启（不是从后台切回） |
| 开了 `VerboseLog` 日志里也没有 `[SAD]` | 插件没被注入。确认 `dpkg -l com.dsh.splashadkiller` 显示已安装；极少数越狱的过滤器实现不认 `Classes`，可把 `SplashAdKiller.plist` 改成 `Mode = Any` 后重新编译 |
| 银行 / 支付类 App 打不开 | 这类 App 有越狱检测，与插件无关；把 Bundle ID 加黑名单 |
| 某个 App 更新后失效 | 广告 SDK 换了类名，用 `ExtraKeywords` 补；或等插件更新 |

其它说明：

- 插件**不修改** App 二进制，不注入 IPA，只在运行时 Hook
- 开屏广告如果被做进首页首帧（不是独立页面），只能遮挡，无法真正「跳过」
- 摇一摇 / 扭一扭广告：因为跳过了整个广告页，不会误触发

---

## 九、卸载

```bash
dpkg -r com.dsh.splashadkiller
```

或在 Sileo / Zebra 的「已安装」里卸载，然后 Respring。

---

## 十、说明

本项目仅用于个人学习与自用，请遵守各 App 的服务条款，不要将修改后的 App 二次分发。

插件按「现状」提供，不保证对所有 App、所有系统版本生效。
