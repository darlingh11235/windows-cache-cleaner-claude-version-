[CmdletBinding()]
param()

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 缓存类别定义
#   Roots：字符串表示递归扫描整个目录；@{ Path; Pattern } 表示只扫描该目录顶层、
#          文件名匹配正则 Pattern 的文件。路径中可以使用 * 通配符（如浏览器多个配置文件）。
#   Risk ：Low = 可放心清理；Medium = 有短暂副作用；High = 一般不建议清理。
# ---------------------------------------------------------------------------
$localLow = Join-Path $env:USERPROFILE 'AppData\LocalLow'

$script:Categories = @(
    [pscustomobject]@{
        Id = 'UserTemp'; Name = '当前用户临时文件'; Icon = '&#xE8B7;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = '软件安装、解压、运行时留下的临时文件，通常是最大的一块。'
        Cause = '安装包解压、程序运行时写入的中间文件、浏览器下载暂存、更新程序的残留等。很多程序用完后不会主动删除，日积月累可达数 GB。'
        Purpose = '只在程序运行的那一刻有用，例如安装过程中的解压内容、文档编辑的临时副本。程序结束后基本不再需要。'
        Impact = '一般没有影响。正在被程序使用的文件会自动跳过；若某个安装程序正在进行中，可能需要重新运行它。'
        Advice = '推荐清理。清理前关闭正在安装或运行的软件效果更好。'
        Roots = @([System.IO.Path]::GetTempPath()); Processes = @()
    },
    [pscustomobject]@{
        Id = 'WindowsTemp'; Name = 'Windows 系统临时文件'; Icon = '&#xE770;'; Risk = 'Low'; NeedsAdmin = $true
        Summary = '系统服务、Windows 更新和以管理员身份运行的安装程序产生的临时文件。'
        Cause = '系统组件、驱动安装程序、Windows 更新以及以 SYSTEM / 管理员身份运行的程序在 C:\Windows\Temp 中写入的工作文件。'
        Purpose = '为系统级任务提供临时工作空间，任务结束后通常不再使用。'
        Impact = '多数文件可以安全删除；被系统占用的文件会跳过。需要管理员权限才能访问。'
        Advice = '推荐清理（需以管理员身份运行）。'
        Roots = @((Join-Path $env:windir 'Temp')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'ExplorerCache'; Name = '缩略图与图标缓存'; Icon = '&#xE91B;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = '资源管理器为图片、视频生成的预览图和图标数据库。'
        Cause = '每次在资源管理器中以缩略图方式浏览图片、视频、文档时，Windows 都会把生成的预览图写入 thumbcache_*.db；图标也会缓存到 iconcache_*.db。'
        Purpose = '下次打开同一文件夹时直接显示预览，不必重新解码文件，浏览更快。'
        Impact = 'Windows 会自动重建。清理后第一次打开图片较多的文件夹时，缩略图会慢一些出现。当前正在使用的数据库会跳过。'
        Advice = '可以清理。缩略图显示错乱或图标异常时尤其推荐。'
        Roots = @(@{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'); Pattern = '^(thumbcache|iconcache).*\.db$' }); Processes = @()
    },
    [pscustomobject]@{
        Id = 'WER'; Name = 'Windows 错误报告'; Icon = '&#xE783;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = '程序崩溃或无响应后生成、等待或已发送给微软的错误报告。'
        Cause = '当程序崩溃、无响应或系统出现问题时，Windows 错误报告服务（WER）会收集日志和内存片段，打包成报告存放在本地。'
        Purpose = '用于向微软或软件开发者反馈问题，也可在“可靠性监视器”中查看历史问题记录。'
        Impact = '删除后无法再查看或提交这些旧的错误报告，不影响系统和软件的正常运行。系统级报告需要管理员权限。'
        Advice = '推荐清理，除非你正在排查某个程序的崩溃问题。'
        Roots = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp')
        ); Processes = @()
    },
    [pscustomobject]@{
        Id = 'DeliveryOptimization'; Name = '传递优化缓存'; Icon = '&#xE895;'; Risk = 'Low'; NeedsAdmin = $true
        Summary = 'Windows 更新“传递优化”下载并用于分享给其他电脑的更新文件。'
        Cause = 'Windows 更新和应用商店通过“传递优化”下载内容时，会把文件片段缓存在本地，以便分享给局域网或互联网上的其他电脑。'
        Purpose = '加速同一网络中其他电脑的更新下载，同时减少重复下载。对本机来说，更新安装完成后就没有用处了。'
        Impact = '不会卸载已安装的更新。如果之后需要相同内容，Windows 会重新下载。需要管理员权限。'
        Advice = '推荐清理。'
        Roots = @((Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization\Cache')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'INetCache'; Name = '系统网页组件缓存'; Icon = '&#xE12B;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = 'IE 内核及使用它的应用（如部分 Office 插件、旧版软件）缓存的网页文件。'
        Cause = '旧版 Internet Explorer 内核（WinINet）以及调用它的软件在显示网页内容时，会缓存图片、脚本、样式表等资源。'
        Purpose = '再次访问同一网页内容时可以直接从本地读取，加快加载。'
        Impact = '使用该内核的软件下次加载网页内容时会重新下载，稍慢一点；不会删除登录状态（Cookie 不在此目录）。'
        Advice = '可以清理。'
        Roots = @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'CrashDumps'; Name = '程序崩溃转储'; Icon = '&#xEBE8;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = '应用程序崩溃时保存的内存转储文件（.dmp），单个可能有数百 MB。'
        Cause = '程序意外崩溃时，Windows 或程序本身把当时的内存状态写成 .dmp 文件，保存在 %LOCALAPPDATA%\CrashDumps。'
        Purpose = '供开发者用调试器分析崩溃原因。普通用户基本用不到。'
        Impact = '删除后无法再分析过去的崩溃，不影响任何程序运行。'
        Advice = '推荐清理，除非软件技术支持要求你提供这些文件。'
        Roots = @((Join-Path $env:LOCALAPPDATA 'CrashDumps')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'Edge'; Name = 'Microsoft Edge 浏览器缓存'; Icon = '&#xE774;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = 'Edge 保存的网页图片、脚本、视频片段和 GPU 编译缓存。'
        Cause = '浏览网页时，Edge 会把图片、脚本、样式、视频片段等资源存入磁盘缓存（Cache、Code Cache、GPUCache），所有用户配置文件各有一份。'
        Purpose = '再次访问同一网站时直接从本地读取，页面打开更快、更省流量。'
        Impact = '只清理缓存，不会删除书签、密码、历史记录和登录状态（Cookie）。清理后首次打开常用网站会稍慢。浏览器运行时部分文件被占用会跳过。'
        Advice = '可以清理。建议先完全关闭 Edge 再清理。'
        Roots = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\*\Cache'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\*\Code Cache'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\*\GPUCache')
        ); Processes = @('msedge')
    },
    [pscustomobject]@{
        Id = 'Chrome'; Name = 'Google Chrome 浏览器缓存'; Icon = '&#xE774;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = 'Chrome 保存的网页图片、脚本、视频片段和 GPU 编译缓存。'
        Cause = '浏览网页时，Chrome 会把图片、脚本、样式、视频片段等资源存入磁盘缓存（Cache、Code Cache、GPUCache），每个用户配置文件各有一份。'
        Purpose = '再次访问同一网站时直接从本地读取，页面打开更快、更省流量。'
        Impact = '只清理缓存，不会删除书签、密码、历史记录和登录状态（Cookie）。清理后首次打开常用网站会稍慢。浏览器运行时部分文件被占用会跳过。'
        Advice = '可以清理。建议先完全关闭 Chrome 再清理。'
        Roots = @(
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\*\Cache'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\*\Code Cache'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\*\GPUCache')
        ); Processes = @('chrome')
    },
    [pscustomobject]@{
        Id = 'Firefox'; Name = 'Mozilla Firefox 浏览器缓存'; Icon = '&#xE774;'; Risk = 'Low'; NeedsAdmin = $false
        Summary = 'Firefox 保存的网页资源缓存（cache2）。'
        Cause = '浏览网页时，Firefox 把图片、脚本、样式等资源写入每个配置文件下的 cache2 目录。'
        Purpose = '再次访问同一网站时直接从本地读取，页面打开更快、更省流量。'
        Impact = '只清理缓存，不会删除书签、密码、历史记录和登录状态。清理后首次打开常用网站会稍慢。'
        Advice = '可以清理。建议先完全关闭 Firefox 再清理。'
        Roots = @((Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles\*\cache2')); Processes = @('firefox')
    },
    [pscustomobject]@{
        Id = 'DirectX'; Name = 'DirectX 着色器缓存'; Icon = '&#xE7FC;'; Risk = 'Medium'; NeedsAdmin = $false
        Summary = '游戏和图形程序编译好的着色器，用来减少画面卡顿。'
        Cause = '游戏或图形程序第一次渲染某种画面效果时，需要把着色器编译成显卡能执行的代码，DirectX 会把结果保存在 D3DSCache 目录。'
        Purpose = '下次遇到同样的画面效果时直接使用编译结果，避免游戏中途因为现场编译而卡顿。'
        Impact = '会自动重新生成。清理后游戏首次启动或首次进入某些场景时，可能出现短暂卡顿或加载变慢。'
        Advice = '视情况清理：显卡驱动更新后、游戏画面异常时适合清理；平时不必频繁清理。'
        Roots = @((Join-Path $env:LOCALAPPDATA 'D3DSCache')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'GpuVendor'; Name = '显卡驱动着色器缓存'; Icon = '&#xE950;'; Risk = 'Medium'; NeedsAdmin = $false
        Summary = 'NVIDIA / AMD / Intel 驱动自己维护的着色器缓存（DX、OpenGL、Vulkan）。'
        Cause = '显卡驱动在编译 DirectX、OpenGL、Vulkan 着色器时，会把结果存在各自的目录中（如 NVIDIA\DXCache、AMD\DxCache、Intel\ShaderCache）。'
        Purpose = '与 DirectX 着色器缓存作用相同：让游戏和 3D 程序再次运行时更流畅。'
        Impact = '驱动会自动重建。清理后游戏首次运行可能更卡、加载更久。游戏运行时部分文件被占用会跳过。'
        Advice = '视情况清理：更新显卡驱动后，或游戏出现画面错误、闪退时适合清理。'
        Roots = @(
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
            (Join-Path $env:ProgramData 'NVIDIA Corporation\NV_Cache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\VkCache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\GLCache'),
            (Join-Path $localLow 'Intel\ShaderCache')
        ); Processes = @()
    },
    [pscustomobject]@{
        Id = 'WindowsUpdate'; Name = 'Windows 更新下载文件'; Icon = '&#xE896;'; Risk = 'Medium'; NeedsAdmin = $true
        Summary = 'Windows 更新下载后用于安装的更新包（SoftwareDistribution\Download）。'
        Cause = 'Windows 更新先把更新包下载到 C:\Windows\SoftwareDistribution\Download，再进行安装。安装完成后这些文件常常会残留。'
        Purpose = '为尚未完成的更新提供安装文件。更新安装完成后基本不再需要。'
        Impact = '不会卸载已安装的更新。如果有更新正在下载或等待重启安装，清理后需要重新下载。正在使用的文件会跳过。需要管理员权限。'
        Advice = '在“设置 → Windows 更新”中没有待安装/待重启的更新时再清理。'
        Roots = @((Join-Path $env:windir 'SoftwareDistribution\Download')); Processes = @()
    },
    [pscustomobject]@{
        Id = 'SystemDumps'; Name = '系统蓝屏转储'; Icon = '&#xE7BA;'; Risk = 'Medium'; NeedsAdmin = $true
        Summary = '系统蓝屏（BSOD）时生成的 MEMORY.DMP 与小型转储，可能非常大。'
        Cause = '电脑蓝屏或系统崩溃时，Windows 会把内存内容写入 C:\Windows\MEMORY.DMP 以及 C:\Windows\Minidump 中的小型转储文件。'
        Purpose = '用于分析蓝屏原因（例如判断是哪个驱动导致的崩溃）。'
        Impact = '删除后无法再分析以前的蓝屏原因，不影响系统运行。需要管理员权限。'
        Advice = '如果你正在排查蓝屏问题，请先保留；否则可以清理。'
        Roots = @(
            @{ Path = $env:windir; Pattern = '^MEMORY\.DMP$' },
            (Join-Path $env:windir 'Minidump')
        ); Processes = @()
    },
    [pscustomobject]@{
        Id = 'Recent'; Name = '最近使用的文件记录'; Icon = '&#xE81C;'; Risk = 'Medium'; NeedsAdmin = $false
        Summary = '“快速访问 / 最近使用的文件”中的快捷方式，属于隐私使用痕迹。'
        Cause = '每次打开文件或文件夹，Windows 会在 Recent 目录中创建一个快捷方式（.lnk），用于记录你最近打开过什么。'
        Purpose = '让资源管理器“快速访问”和开始菜单显示你最近打开的文件，方便再次打开。'
        Impact = '“最近使用的文件”列表会被清空，之后会重新开始记录。只删除快捷方式，不会删除你的实际文件。'
        Advice = '在意隐私（如多人共用电脑）时清理；否则保留以便快速找到常用文件。'
        Roots = @(@{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Recent'); Pattern = '\.lnk$' }); Processes = @()
    },
    [pscustomobject]@{
        Id = 'Prefetch'; Name = '预读取数据 (Prefetch)'; Icon = '&#xE916;'; Risk = 'High'; NeedsAdmin = $true
        Summary = 'Windows 记录程序启动行为的文件，用来加快程序和开机启动速度。'
        Cause = 'Windows 会记录每个程序启动时读取了哪些文件，保存为 C:\Windows\Prefetch 中的 .pf 文件。'
        Purpose = '下次启动同一程序时提前把需要的数据读入内存，让程序和系统启动更快。这些文件本身很小，总共通常只有几十 MB。'
        Impact = '清理后一段时间内开机和打开常用程序会变慢，Windows 需要重新学习。几乎释放不了多少空间。需要管理员权限。'
        Advice = '一般不建议清理。网上说“清 Prefetch 能提速”是误解，只在排查特定问题时才需要。'
        Roots = @((Join-Path $env:windir 'Prefetch')); Processes = @()
    }
)

$script:RiskInfo = @{
    Low    = [pscustomobject]@{ Label = '低风险'; Fore = '#15803D'; Back = '#DCFCE7'; Accent = '#16A34A'; IconBack = '#ECFDF5' }
    Medium = [pscustomobject]@{ Label = '中风险'; Fore = '#B45309'; Back = '#FEF3C7'; Accent = '#D97706'; IconBack = '#FFFBEB' }
    High   = [pscustomobject]@{ Label = '高风险'; Fore = '#B91C1C'; Back = '#FEE2E2'; Accent = '#DC2626'; IconBack = '#FEF2F2' }
}

$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:ScanResults = @{}
$script:Cards = @{}
$script:SelectedId = $null
$script:Busy = $false
$script:PumpCounter = 0
$script:Closing = $false
$script:ScriptPath = $PSCommandPath

# ---------------------------------------------------------------------------
# 主窗口
# ---------------------------------------------------------------------------
[xml]$windowXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows 缓存清理工具" Width="1260" Height="820" MinWidth="1020" MinHeight="640"
        WindowStartupLocation="CenterScreen" Background="#F3F5FA"
        FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="13" Foreground="#1F2937"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="BaseButton" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#374151"/>
      <Setter Property="BorderBrush" Value="#D1D5DB"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.75"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#4F46E5"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#4F46E5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#E11D48"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#E11D48"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#6366F1"/>
      <Setter Property="Margin" Value="0,14,0,4"/>
    </Style>
    <Style x:Key="SectionBody" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="LineHeight" Value="21"/>
      <Setter Property="Foreground" Value="#374151"/>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- 顶部横幅 -->
    <Border Grid.Row="0" CornerRadius="16" Padding="26,20">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#4F46E5" Offset="0"/>
          <GradientStop Color="#7C3AED" Offset="0.6"/>
          <GradientStop Color="#A855F7" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="24" Foreground="White" VerticalAlignment="Center" Margin="0,0,12,0"/>
            <TextBlock Text="Windows 缓存清理工具" FontSize="24" FontWeight="Bold" Foreground="White" VerticalAlignment="Center"/>
            <Border x:Name="AdminBadge" CornerRadius="10" Padding="10,3" Margin="14,0,0,0" VerticalAlignment="Center" Background="#33FFFFFF">
              <TextBlock x:Name="AdminBadgeText" Text="普通权限" Foreground="White" FontSize="12"/>
            </Border>
          </StackPanel>
          <TextBlock Margin="0,8,0,0" Foreground="#E0E7FF" TextWrapping="Wrap"
                     Text="每一项缓存都写明了产生原因、用途和清理后的影响。默认不勾选任何项目，由你自己决定清理什么；扫描只读取，不会修改任何文件。"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#26FFFFFF" CornerRadius="12" Padding="20,10" Margin="20,0,0,0" MinWidth="150">
          <StackPanel>
            <TextBlock Text="扫描到的缓存" Foreground="#E0E7FF" FontSize="12"/>
            <TextBlock x:Name="TotalSize" Text="—" Foreground="White" FontSize="26" FontWeight="Bold"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="2" Background="#26FFFFFF" CornerRadius="12" Padding="20,10" Margin="12,0,0,0" MinWidth="150">
          <StackPanel>
            <TextBlock x:Name="SelectedCountText" Text="已勾选 0 项" Foreground="#E0E7FF" FontSize="12"/>
            <TextBlock x:Name="SelectedSize" Text="0 B" Foreground="White" FontSize="26" FontWeight="Bold"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <!-- 权限提示 -->
    <Border x:Name="AdminBanner" Grid.Row="1" Margin="0,14,0,0" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" CornerRadius="10" Padding="16,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" Foreground="#D97706" FontSize="16" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock Grid.Column="1" VerticalAlignment="Center" Foreground="#92400E" TextWrapping="Wrap"
                   Text="当前以普通权限运行：标有「需管理员」的项目只能扫描到部分内容，清理时无权限的文件会被跳过。"/>
        <Button x:Name="ElevateButton" Grid.Column="2" Style="{StaticResource BaseButton}" Padding="14,6" Content="以管理员身份重新启动"/>
      </Grid>
    </Border>

    <!-- 风险图例 -->
    <Grid Grid.Row="2" Margin="2,14,0,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="缓存项目" FontSize="16" FontWeight="SemiBold" Margin="0,0,18,0"/>
        <Ellipse Width="9" Height="9" Fill="#16A34A" VerticalAlignment="Center"/>
        <TextBlock Text=" 低风险：可放心清理" Foreground="#6B7280" Margin="2,0,16,0" VerticalAlignment="Center"/>
        <Ellipse Width="9" Height="9" Fill="#D97706" VerticalAlignment="Center"/>
        <TextBlock Text=" 中风险：有短暂副作用，按需清理" Foreground="#6B7280" Margin="2,0,16,0" VerticalAlignment="Center"/>
        <Ellipse Width="9" Height="9" Fill="#DC2626" VerticalAlignment="Center"/>
        <TextBlock Text=" 高风险：一般不建议清理" Foreground="#6B7280" Margin="2,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock Grid.Column="1" Text="点击卡片查看详细说明" Foreground="#9CA3AF" VerticalAlignment="Center"/>
    </Grid>

    <!-- 主体：卡片列表 + 详情 -->
    <Grid Grid.Row="3">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="400"/>
      </Grid.ColumnDefinitions>
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,0,10,0">
        <StackPanel x:Name="CardPanel"/>
      </ScrollViewer>

      <Border Grid.Column="1" Margin="10,0,0,10" Background="White" CornerRadius="14" BorderBrush="#E5E7EB" BorderThickness="1">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="22,20">
            <StackPanel Orientation="Horizontal">
              <Border x:Name="DetailIconBox" Width="46" Height="46" CornerRadius="12" Background="#EEF2FF">
                <TextBlock x:Name="DetailIcon" Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="#6366F1"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="DetailName" Text="请选择一个缓存项目" FontSize="17" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="290"/>
                <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                  <Border x:Name="DetailRiskBox" CornerRadius="8" Padding="8,1" Background="#F3F4F6">
                    <TextBlock x:Name="DetailRisk" Text="—" FontSize="11" FontWeight="SemiBold" Foreground="#6B7280"/>
                  </Border>
                  <Border x:Name="DetailAdminBox" CornerRadius="8" Padding="8,1" Margin="6,0,0,0" Background="#EEF2FF" Visibility="Collapsed">
                    <TextBlock Text="需管理员" FontSize="11" FontWeight="SemiBold" Foreground="#4F46E5"/>
                  </Border>
                </StackPanel>
              </StackPanel>
            </StackPanel>

            <Border Margin="0,16,0,0" Background="#F9FAFB" CornerRadius="10" Padding="14,10">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                  <TextBlock Text="占用空间" Foreground="#6B7280" FontSize="12"/>
                  <TextBlock x:Name="DetailSize" Text="—" FontSize="18" FontWeight="Bold"/>
                </StackPanel>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="文件数量" Foreground="#6B7280" FontSize="12"/>
                  <TextBlock x:Name="DetailCount" Text="—" FontSize="18" FontWeight="Bold"/>
                </StackPanel>
              </Grid>
            </Border>

            <TextBlock Style="{StaticResource SectionTitle}" Text="■ 为什么会产生"/>
            <TextBlock x:Name="DetailCause" Style="{StaticResource SectionBody}" Text="在左侧点击任意卡片，这里会显示该缓存的产生原因、用途和清理影响。"/>
            <TextBlock Style="{StaticResource SectionTitle}" Text="■ 它有什么用"/>
            <TextBlock x:Name="DetailPurpose" Style="{StaticResource SectionBody}" Text="—"/>
            <TextBlock Style="{StaticResource SectionTitle}" Text="■ 清理后会怎样"/>
            <TextBlock x:Name="DetailImpact" Style="{StaticResource SectionBody}" Text="—"/>

            <Border x:Name="DetailAdviceBox" Margin="0,16,0,0" CornerRadius="10" Padding="14,10" Background="#EEF2FF">
              <StackPanel>
                <TextBlock Text="建议" FontWeight="SemiBold" Foreground="#4338CA" FontSize="12"/>
                <TextBlock x:Name="DetailAdvice" Style="{StaticResource SectionBody}" Margin="0,3,0,0" Text="—"/>
              </StackPanel>
            </Border>

            <TextBlock Style="{StaticResource SectionTitle}" Text="■ 所在位置"/>
            <TextBlock x:Name="DetailPaths" Style="{StaticResource SectionBody}" FontFamily="Consolas, Microsoft YaHei UI" FontSize="12" Foreground="#4B5563" Text="—"/>
            <TextBlock x:Name="DetailWarning" Style="{StaticResource SectionBody}" Margin="0,10,0,0" Foreground="#B45309" Visibility="Collapsed"/>
            <Button x:Name="OpenFolderButton" Style="{StaticResource BaseButton}" Margin="0,16,0,0" HorizontalAlignment="Left" IsEnabled="False">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE838;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <TextBlock Text="在资源管理器中打开"/>
              </StackPanel>
            </Button>
          </StackPanel>
        </ScrollViewer>
      </Border>
    </Grid>

    <!-- 底部操作栏 -->
    <Border Grid.Row="4" Margin="0,6,0,0" Background="White" CornerRadius="14" Padding="18,12" BorderBrush="#E5E7EB" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
          <TextBlock x:Name="StatusText" Text="准备就绪。" Foreground="#4B5563" TextTrimming="CharacterEllipsis"/>
          <ProgressBar x:Name="Progress" Height="6" Margin="0,8,0,0" Minimum="0" Maximum="1" Value="0"
                       Foreground="#6366F1" Background="#EEF2FF" BorderThickness="0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="SelectLowButton" Style="{StaticResource BaseButton}" Content="勾选所有低风险项"/>
          <Button x:Name="SelectNoneButton" Style="{StaticResource BaseButton}" Content="取消全选"/>
          <Button x:Name="ScanButton" Style="{StaticResource PrimaryButton}" Content="重新扫描"/>
          <Button x:Name="CleanButton" Style="{StaticResource DangerButton}" Content="清理已勾选项目…" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$script:Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $windowXaml))
$ui = @{}
foreach ($name in @('AdminBadge', 'AdminBadgeText', 'TotalSize', 'SelectedCountText', 'SelectedSize', 'AdminBanner', 'ElevateButton',
        'CardPanel', 'DetailIconBox', 'DetailIcon', 'DetailName', 'DetailRiskBox', 'DetailRisk', 'DetailAdminBox', 'DetailSize',
        'DetailCount', 'DetailCause', 'DetailPurpose', 'DetailImpact', 'DetailAdviceBox', 'DetailAdvice', 'DetailPaths',
        'DetailWarning', 'OpenFolderButton', 'StatusText', 'Progress', 'SelectLowButton', 'SelectNoneButton', 'ScanButton', 'CleanButton')) {
    $ui[$name] = $script:Window.FindName($name)
}
$script:UI = $ui

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function New-Brush([string]$Color) {
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}

function Format-ByteCount {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Invoke-UIPump {
    # 让界面在长时间操作中保持刷新（相当于 WinForms 的 DoEvents）。
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $callback = [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; return $null }
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $callback, $frame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Step-UIPump {
    $script:PumpCounter++
    if (($script:PumpCounter % 400) -eq 0) { Invoke-UIPump }
}

function Test-IsReparsePoint($Info) {
    return (($Info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-RootSpecs {
    # 把类别中的 Roots 展开为实际存在的目录（处理 * 通配符），并标明扫描方式。
    param([pscustomobject]$Category)
    $specs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($root in $Category.Roots) {
        if ($root -is [hashtable]) { $path = [string]$root.Path; $pattern = [string]$root.Pattern }
        else { $path = [string]$root; $pattern = $null }

        $dirs = @()
        if ($path.Contains('*')) {
            try { $dirs = @(Get-Item -Path $path -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }) } catch { $dirs = @() }
        }
        elseif ([System.IO.Directory]::Exists($path)) {
            $dirs = @([System.IO.DirectoryInfo]::new($path))
        }
        foreach ($dir in $dirs) {
            if (Test-IsReparsePoint $dir) { continue }
            $specs.Add([pscustomobject]@{ Path = [System.IO.Path]::GetFullPath($dir.FullName); Pattern = $pattern })
        }
    }
    return @($specs.ToArray())
}

function Get-CacheFiles {
    param([pscustomobject]$Category)
    $files = New-Object 'System.Collections.Generic.List[object]'
    $dirs = New-Object 'System.Collections.Generic.List[object]'
    $errors = 0
    $total = [long]0
    $specs = @(Get-RootSpecs -Category $Category)

    foreach ($spec in $specs) {
        if ($spec.Pattern) {
            try {
                foreach ($item in ([System.IO.DirectoryInfo]::new($spec.Path).GetFiles())) {
                    if (Test-IsReparsePoint $item) { continue }
                    if ($item.Name -match $spec.Pattern) {
                        $files.Add([pscustomobject]@{ Path = $item.FullName; Length = [long]$item.Length; Root = $spec.Path })
                        $total += [long]$item.Length
                    }
                }
            }
            catch { $errors++ }
            continue
        }

        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($spec.Path)
        while ($pending.Count -gt 0 -and -not $script:Closing) {
            $directory = $pending.Pop()
            try { $children = ([System.IO.DirectoryInfo]::new($directory)).GetFileSystemInfos() }
            catch { $errors++; continue }
            foreach ($item in $children) {
                if (Test-IsReparsePoint $item) { continue }
                if ($item -is [System.IO.DirectoryInfo]) {
                    $pending.Push($item.FullName)
                    $dirs.Add([pscustomobject]@{ Path = $item.FullName; Root = $spec.Path })
                }
                else {
                    $files.Add([pscustomobject]@{ Path = $item.FullName; Length = [long]$item.Length; Root = $spec.Path })
                    $total += [long]$item.Length
                }
                Step-UIPump
            }
        }
    }

    return [pscustomobject]@{
        Files = $files; Dirs = $dirs; Errors = $errors; Total = $total
        Missing = ($specs.Count -eq 0); Roots = @($specs | ForEach-Object { $_.Path })
    }
}

function Test-PathWithinRoot {
    param([string]$Root, [string]$Path)
    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Get-RunningProcessNames {
    param([pscustomobject]$Category)
    if (-not $Category.Processes -or $Category.Processes.Count -eq 0) { return @() }
    return @(Get-Process -Name $Category.Processes -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique)
}

function Get-DisplayRoots {
    param([pscustomobject]$Category)
    $lines = foreach ($root in $Category.Roots) {
        if ($root -is [hashtable]) { '{0}  （仅 {1}）' -f $root.Path, $root.Pattern } else { [string]$root }
    }
    return ($lines -join "`r`n")
}

# ---------------------------------------------------------------------------
# 卡片
# ---------------------------------------------------------------------------
function New-CategoryCard {
    param([pscustomobject]$Category)
    $risk = $script:RiskInfo[$Category.Risk]
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    $adminVisibility = if ($Category.NeedsAdmin) { 'Visible' } else { 'Collapsed' }
    $cardXaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="White" CornerRadius="12" Padding="16,14" Margin="0,0,0,10"
        BorderBrush="#E5E7EB" BorderThickness="1.5" Cursor="Hand">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/>
      <ColumnDefinition Width="Auto"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <CheckBox x:Name="Check" VerticalAlignment="Center" Margin="0,0,14,0" Cursor="Hand">
      <CheckBox.LayoutTransform><ScaleTransform ScaleX="1.35" ScaleY="1.35"/></CheckBox.LayoutTransform>
    </CheckBox>
    <Border Grid.Column="1" Width="44" Height="44" CornerRadius="11" Background="$($risk.IconBack)" VerticalAlignment="Center">
      <TextBlock Text="$($Category.Icon)" FontFamily="Segoe MDL2 Assets" FontSize="19" Foreground="$($risk.Accent)"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="2" Margin="14,0,12,0" VerticalAlignment="Center">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="$(& $esc $Category.Name)" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <Border CornerRadius="8" Padding="8,1" Margin="10,0,0,0" Background="$($risk.Back)" VerticalAlignment="Center">
          <TextBlock Text="$($risk.Label)" FontSize="11" FontWeight="SemiBold" Foreground="$($risk.Fore)"/>
        </Border>
        <Border CornerRadius="8" Padding="8,1" Margin="6,0,0,0" Background="#EEF2FF" VerticalAlignment="Center" Visibility="$adminVisibility">
          <TextBlock Text="需管理员" FontSize="11" FontWeight="SemiBold" Foreground="#4F46E5"/>
        </Border>
      </StackPanel>
      <TextBlock Text="$(& $esc $Category.Summary)" Foreground="#6B7280" FontSize="12" Margin="0,5,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Grid.Column="3" VerticalAlignment="Center" MinWidth="120">
      <TextBlock x:Name="Size" Text="—" FontSize="17" FontWeight="Bold" HorizontalAlignment="Right"/>
      <TextBlock x:Name="Info" Text="尚未扫描" FontSize="11" Foreground="#9CA3AF" HorizontalAlignment="Right" Margin="0,3,0,0"/>
    </StackPanel>
  </Grid>
</Border>
"@
    $card = [Windows.Markup.XamlReader]::Parse($cardXaml)
    $card.Tag = $Category.Id
    $check = $card.FindName('Check')
    $check.Tag = $Category.Id
    return [pscustomobject]@{ Border = $card; Check = $check; Size = $card.FindName('Size'); Info = $card.FindName('Info') }
}

function Set-CardSelected {
    param([string]$Id)
    $script:SelectedId = $Id
    foreach ($key in $script:Cards.Keys) {
        $border = $script:Cards[$key].Border
        if ($key -eq $Id) { $border.BorderBrush = New-Brush '#6366F1'; $border.Background = New-Brush '#FAFAFF' }
        else { $border.BorderBrush = New-Brush '#E5E7EB'; $border.Background = New-Brush 'White' }
    }
    Show-Details -Id $Id
}

function Show-Details {
    param([string]$Id)
    $category = $script:Categories | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $category) { return }
    $risk = $script:RiskInfo[$category.Risk]
    $u = $script:UI
    $u.DetailIcon.Text = [System.Net.WebUtility]::HtmlDecode($category.Icon)
    $u.DetailIcon.Foreground = New-Brush $risk.Accent
    $u.DetailIconBox.Background = New-Brush $risk.IconBack
    $u.DetailName.Text = $category.Name
    $u.DetailRisk.Text = $risk.Label
    $u.DetailRisk.Foreground = New-Brush $risk.Fore
    $u.DetailRiskBox.Background = New-Brush $risk.Back
    $u.DetailAdminBox.Visibility = if ($category.NeedsAdmin) { 'Visible' } else { 'Collapsed' }
    $u.DetailCause.Text = $category.Cause
    $u.DetailPurpose.Text = $category.Purpose
    $u.DetailImpact.Text = $category.Impact
    $u.DetailAdvice.Text = $category.Advice
    $u.DetailAdviceBox.Background = New-Brush $risk.IconBack
    $u.DetailPaths.Text = Get-DisplayRoots -Category $category

    $warnings = @()
    if ($category.NeedsAdmin -and -not $script:IsAdmin) { $warnings += '⚠ 当前不是管理员权限，此项可能扫描不全，清理时无权限的文件会被跳过。' }
    $running = @(Get-RunningProcessNames -Category $category)
    if ($running.Count -gt 0) { $warnings += ('⚠ 检测到相关程序正在运行（{0}），建议先关闭再清理，否则部分文件会被占用而跳过。' -f ($running -join '、')) }
    $u.DetailWarning.Text = $warnings -join "`r`n"
    $u.DetailWarning.Visibility = if ($warnings.Count -gt 0) { 'Visible' } else { 'Collapsed' }

    $result = $script:ScanResults[$Id]
    if ($result) {
        if ($result.Missing) { $u.DetailSize.Text = '0 B'; $u.DetailCount.Text = '0' }
        else { $u.DetailSize.Text = Format-ByteCount $result.Total; $u.DetailCount.Text = '{0:N0}' -f $result.Files.Count }
        $u.OpenFolderButton.IsEnabled = ($result.Roots.Count -gt 0)
    }
    else {
        $u.DetailSize.Text = '—'; $u.DetailCount.Text = '—'
        $u.OpenFolderButton.IsEnabled = $false
    }
}

function Update-Card {
    param([pscustomobject]$Category)
    $card = $script:Cards[$Category.Id]
    $result = $script:ScanResults[$Category.Id]
    if (-not $result) { return }
    if ($result.Missing) {
        $card.Size.Text = '0 B'
        $card.Size.Foreground = New-Brush '#9CA3AF'
        $card.Info.Text = '未找到（未安装或不存在）'
        $card.Border.Opacity = 0.6
        return
    }
    $card.Border.Opacity = 1
    $card.Size.Text = Format-ByteCount $result.Total
    $card.Size.Foreground = if ($result.Total -ge 100MB) { New-Brush '#E11D48' } elseif ($result.Total -gt 0) { New-Brush '#1F2937' } else { New-Brush '#9CA3AF' }
    $info = '{0:N0} 个文件' -f $result.Files.Count
    if ($result.Errors -gt 0) { $info += (' · {0} 处无权读取' -f $result.Errors) }
    $running = @(Get-RunningProcessNames -Category $Category)
    if ($running.Count -gt 0) { $info += ' · 程序运行中' }
    $card.Info.Text = $info
}

function Update-Summary {
    $total = [long]0
    foreach ($result in $script:ScanResults.Values) { $total += [long]$result.Total }
    $script:UI.TotalSize.Text = if ($script:ScanResults.Count -gt 0) { Format-ByteCount $total } else { '—' }

    $selectedTotal = [long]0
    $count = 0
    foreach ($category in $script:Categories) {
        if ($script:Cards[$category.Id].Check.IsChecked) {
            $count++
            $result = $script:ScanResults[$category.Id]
            if ($result) { $selectedTotal += [long]$result.Total }
        }
    }
    $script:UI.SelectedCountText.Text = "已勾选 $count 项"
    $script:UI.SelectedSize.Text = Format-ByteCount $selectedTotal
    $script:UI.CleanButton.IsEnabled = (-not $script:Busy) -and ($count -gt 0) -and ($script:ScanResults.Count -gt 0)
}

function Set-Busy {
    param([bool]$Value)
    $script:Busy = $Value
    foreach ($name in @('ScanButton', 'SelectLowButton', 'SelectNoneButton', 'ElevateButton')) { $script:UI[$name].IsEnabled = -not $Value }
    foreach ($card in $script:Cards.Values) { $card.Check.IsEnabled = -not $Value }
    Update-Summary
}

# ---------------------------------------------------------------------------
# 扫描与清理
# ---------------------------------------------------------------------------
function Invoke-Scan {
    param([object[]]$Only)
    $targets = if ($Only) { @($Only) } else { @($script:Categories) }
    Set-Busy $true
    $script:UI.Progress.Maximum = [Math]::Max(1, $targets.Count)
    $script:UI.Progress.Value = 0
    $index = 0
    foreach ($category in $targets) {
        if ($script:Closing) { return }
        $index++
        $card = $script:Cards[$category.Id]
        $script:UI.StatusText.Text = "正在扫描：$($category.Name)（$index / $($targets.Count)）"
        $card.Size.Text = '…'
        $card.Info.Text = '扫描中…'
        Invoke-UIPump
        try { $script:ScanResults[$category.Id] = Get-CacheFiles -Category $category }
        catch {
            $script:ScanResults[$category.Id] = [pscustomobject]@{ Files = @(); Dirs = @(); Errors = 1; Total = [long]0; Missing = $true; Roots = @() }
        }
        Update-Card -Category $category
        $script:UI.Progress.Value = $index
        Update-Summary
        Invoke-UIPump
    }
    $script:UI.StatusText.Text = '扫描完成。点击卡片了解每项缓存，勾选你决定清理的项目后点击“清理已勾选项目…”。'
    Set-Busy $false
    if ($script:SelectedId) { Show-Details -Id $script:SelectedId }
}

function Invoke-Clean {
    $selected = @($script:Categories | Where-Object { $script:Cards[$_.Id].Check.IsChecked })
    if ($selected.Count -eq 0) { return }
    $unscanned = @($selected | Where-Object { -not $script:ScanResults.ContainsKey($_.Id) })
    if ($unscanned.Count -gt 0) {
        [void][System.Windows.MessageBox]::Show('请先完成扫描，再清理所选项目。', '需要先扫描', 'OK', 'Information')
        return
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $notes = New-Object 'System.Collections.Generic.List[string]'
    $fileCount = 0
    $sum = [long]0
    foreach ($category in $selected) {
        $result = $script:ScanResults[$category.Id]
        $fileCount += $result.Files.Count
        $sum += $result.Total
        $lines.Add(('• [{0}] {1}：{2:N0} 个文件，约 {3}' -f $script:RiskInfo[$category.Risk].Label, $category.Name, $result.Files.Count, (Format-ByteCount $result.Total)))
        if ($category.Risk -ne 'Low') { $notes.Add(('「{0}」— {1}' -f $category.Name, $category.Impact)) }
        $running = @(Get-RunningProcessNames -Category $category)
        if ($running.Count -gt 0) { $notes.Add(('「{0}」相关程序正在运行（{1}），部分文件会被跳过。' -f $category.Name, ($running -join '、'))) }
    }
    if ($fileCount -eq 0) {
        [void][System.Windows.MessageBox]::Show('所选项目中没有可清理的文件。', '没有可清理内容', 'OK', 'Information')
        return
    }

    $prompt = "即将删除以下项目中扫描到的文件（共约 $(Format-ByteCount $sum)）：`r`n`r`n$($lines -join "`r`n")"
    if ($notes.Count -gt 0) { $prompt += "`r`n`r`n请注意：`r`n$($notes -join "`r`n")" }
    $prompt += "`r`n`r`n删除后不会进入回收站。正在使用或无权限的文件会自动跳过。确定继续吗？"
    $answer = [System.Windows.MessageBox]::Show($prompt, '确认清理', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Set-Busy $true
    $script:UI.CleanButton.IsEnabled = $false
    $script:UI.Progress.Maximum = [Math]::Max(1, $fileCount)
    $script:UI.Progress.Value = 0
    $deleted = 0
    $skipped = 0
    $freed = [long]0
    $position = 0
    foreach ($category in $selected) {
        $result = $script:ScanResults[$category.Id]
        foreach ($file in $result.Files) {
            if ($script:Closing) { return }
            $position++
            if (($position % 50) -eq 0) {
                $script:UI.StatusText.Text = "正在清理：$($category.Name)（$position / $fileCount）"
                $script:UI.Progress.Value = $position
                Invoke-UIPump
            }
            if (-not (Test-PathWithinRoot -Root $file.Root -Path $file.Path)) { $skipped++; continue }
            try {
                $info = [System.IO.FileInfo]::new($file.Path)
                if (-not $info.Exists) { continue }
                if (Test-IsReparsePoint $info) { $skipped++; continue }
                if ($info.IsReadOnly) { $info.IsReadOnly = $false }
                $length = $info.Length
                $info.Delete()
                $deleted++
                $freed += $length
            }
            catch { $skipped++ }
        }
        # 删除清理后变空的子目录（不删除缓存根目录本身，也不跟随符号链接）。
        foreach ($dir in @($result.Dirs | Sort-Object { $_.Path.Length } -Descending)) {
            if (-not (Test-PathWithinRoot -Root $dir.Root -Path $dir.Path)) { continue }
            try {
                $dirInfo = [System.IO.DirectoryInfo]::new($dir.Path)
                if (-not $dirInfo.Exists -or (Test-IsReparsePoint $dirInfo)) { continue }
                if ($dirInfo.GetFileSystemInfos().Count -eq 0) { $dirInfo.Delete($false) }
            }
            catch { }
        }
    }
    $script:UI.Progress.Value = $script:UI.Progress.Maximum
    foreach ($category in $selected) { $script:Cards[$category.Id].Check.IsChecked = $false }
    Set-Busy $false
    Invoke-Scan -Only $selected
    $script:UI.StatusText.Text = "清理完成：释放 $(Format-ByteCount $freed)，删除 $deleted 个文件，跳过 $skipped 个。"
    [void][System.Windows.MessageBox]::Show("清理完成！`r`n`r`n释放空间：$(Format-ByteCount $freed)`r`n成功删除：$deleted 个文件`r`n跳过（占用中或无权限）：$skipped 个文件`r`n`r`n已重新扫描所清理的项目。", '清理结果', 'OK', 'Information')
}

# ---------------------------------------------------------------------------
# 组装界面与事件
# ---------------------------------------------------------------------------
if ($script:IsAdmin) {
    $ui.AdminBadgeText.Text = '管理员权限'
    $ui.AdminBadge.Background = New-Brush '#3322C55E'
    $ui.AdminBanner.Visibility = 'Collapsed'
}

foreach ($category in $script:Categories) {
    $card = New-CategoryCard -Category $category
    $script:Cards[$category.Id] = $card
    [void]$ui.CardPanel.Children.Add($card.Border)
    $card.Border.add_MouseLeftButtonUp({ param($s, $e) Set-CardSelected -Id ([string]$s.Tag) })
    $card.Check.add_Checked({ param($s, $e) Update-Summary })
    $card.Check.add_Unchecked({ param($s, $e) Update-Summary })
}

$ui.ScanButton.add_Click({ if (-not $script:Busy) { Invoke-Scan } })
$ui.CleanButton.add_Click({ if (-not $script:Busy) { Invoke-Clean } })
$ui.SelectNoneButton.add_Click({ foreach ($card in $script:Cards.Values) { $card.Check.IsChecked = $false } })
$ui.SelectLowButton.add_Click({
    foreach ($category in $script:Categories) {
        $result = $script:ScanResults[$category.Id]
        $hasFiles = $result -and -not $result.Missing -and $result.Files.Count -gt 0
        $script:Cards[$category.Id].Check.IsChecked = ($category.Risk -eq 'Low') -and $hasFiles
    }
})
$ui.OpenFolderButton.add_Click({
    $result = $script:ScanResults[$script:SelectedId]
    if ($result -and $result.Roots.Count -gt 0) { Start-Process explorer.exe -ArgumentList "`"$($result.Roots[0])`"" }
})
$ui.ElevateButton.add_Click({
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$script:ScriptPath`""
        $script:Window.Close()
    }
    catch { [void][System.Windows.MessageBox]::Show('未能以管理员身份启动（可能取消了授权）。', '提示', 'OK', 'Information') }
})

$script:Window.add_Closing({ $script:Closing = $true })
$script:Window.add_ContentRendered({
    Set-CardSelected -Id $script:Categories[0].Id
    Invoke-Scan
})

[void]$script:Window.ShowDialog()
