$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class Icons {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ShellInfo {
        public IntPtr Icon;
        public int IconIndex;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct BitmapHeader {
        public uint Size;
        public int Width, Height;
        public ushort Planes, Bits;
        public uint Compression, ImageSize;
        public int XPelsPerMeter, YPelsPerMeter;
        public uint Colors, ImportantColors;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(string file, uint attributes, out ShellInfo info, uint size, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern uint ExtractIconEx(string file, int index, out IntPtr large, IntPtr small, uint count);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr icon);

    [DllImport("user32.dll")]
    private static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int w, int h, uint step, IntPtr brush, uint flags);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateDIBSection(IntPtr dc, ref BitmapHeader header, uint usage, out IntPtr bits, IntPtr section, uint offset);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr dc, IntPtr bitmap);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr bitmap);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr dc);

    [DllImport("gdi32.dll")]
    private static extern bool GdiFlush();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string caption);

    [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")]
    public static extern IntPtr GetClassIcon(IntPtr window, int index);

    public static int[] Pixels(IntPtr icon) {
        if (icon == IntPtr.Zero) throw new InvalidOperationException("Missing icon handle");
        const int size = 32;
        IntPtr dc = CreateCompatibleDC(IntPtr.Zero);
        var header = new BitmapHeader { Size = 40, Width = size, Height = -size, Planes = 1, Bits = 32 };
        IntPtr bits;
        IntPtr bitmap = CreateDIBSection(dc, ref header, 0, out bits, IntPtr.Zero, 0);
        IntPtr old = SelectObject(dc, bitmap);
        try {
            var pixels = new int[size * size];
            Marshal.Copy(pixels, 0, bits, pixels.Length);
            if (!DrawIconEx(dc, 0, 0, icon, size, size, 0, IntPtr.Zero, 3)) {
                throw new Win32Exception("DrawIconEx failed");
            }
            GdiFlush();
            Marshal.Copy(bits, pixels, 0, pixels.Length);
            return pixels;
        } finally {
            SelectObject(dc, old);
            DeleteObject(bitmap);
            DeleteDC(dc);
        }
    }

    public static int[] Shortcut(string file) {
        ShellInfo info;
        if (SHGetFileInfo(file, 0, out info, (uint)Marshal.SizeOf(typeof(ShellInfo)), 0x100) == IntPtr.Zero) {
            throw new InvalidOperationException("SHGetFileInfo failed for " + file);
        }
        try { return Pixels(info.Icon); }
        finally { DestroyIcon(info.Icon); }
    }

    public static int[] FileIcon(string file, int index) {
        IntPtr icon;
        if (ExtractIconEx(file, index, out icon, IntPtr.Zero, 1) != 1) {
            throw new InvalidOperationException("Missing executable icon " + index + " in " + file);
        }
        try { return Pixels(icon); }
        finally { DestroyIcon(icon); }
    }
}
'@

function Assert-DrawnIcon([int[]] $pixels, [string] $label) {
    $amberPixels = 0
    foreach ($pixel in $pixels) {
        $red = ($pixel -shr 16) -band 255
        $green = ($pixel -shr 8) -band 255
        $blue = $pixel -band 255
        if ($red -ge 150 -and $red - $green -gt 15 -and $green - $blue -gt 20) {
            $amberPixels++
        }
    }
    if ($amberPixels -lt 15) { throw "Missing branded artwork for $label ($amberPixels amber pixels)" }
    Write-Host "Rendered $label ($amberPixels amber pixels)"
}

$path = Join-Path $env:LOCALAPPDATA 'Programs\piy-piy'
$previous = Join-Path $env:RUNNER_TEMP 'piy-piy-setup-0.1.9-x64.exe'
Invoke-WebRequest 'https://github.com/Estetik007/piy-piy-releases/releases/download/v0.1.9/piy-piy-setup-0.1.9-x64.exe' -OutFile $previous
if ((Get-FileHash $previous).Hash -ne '0cc80a38f440a594cb3a2311831af4cd9f3e7fa9fa5309940fcf1182c7136b2b') {
    throw 'Unexpected 0.1.9 installer'
}
$firstInstall = Start-Process $previous -Wait -PassThru -ArgumentList '/S'
if ($firstInstall.ExitCode -ne 0) { throw "0.1.9 setup failed: $($firstInstall.ExitCode)" }
$reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\piy-piy'
New-ItemProperty $reg -Name DesktopShortcuts -Value 1 -PropertyType DWORD -Force | Out-Null
$setupPath = (Resolve-Path './release-files/piy-piy-setup-0.1.10-x64.exe').Path
$setup = Start-Process $setupPath -Wait -PassThru -ArgumentList '/S'
if ($setup.ExitCode -ne 0) { throw "0.1.10 setup failed: $($setup.ExitCode)" }

$launcher = Join-Path $path 'piy-piy-launcher.exe'
$game = Join-Path $path 'versions\0.1.10\piy-piy.exe'
Assert-DrawnIcon ([Icons]::FileIcon($game, 0)) 'game executable'
$launcherPixels = [Icons]::FileIcon($launcher, 0)
$gameShortcutPixels = [Icons]::FileIcon($launcher, 1)
Assert-DrawnIcon $launcherPixels 'launcher executable'
Assert-DrawnIcon $gameShortcutPixels 'game shortcut resource'
if (($launcherPixels -join ',') -eq ($gameShortcutPixels -join ',')) {
    throw 'The game and launcher use the same artwork'
}

$shell = New-Object -ComObject WScript.Shell
$folders = @(
    [Environment]::GetFolderPath('DesktopDirectory')
    [Environment]::GetFolderPath('Programs')
)
foreach ($folder in $folders) {
    $labels = @('piy-piy — Лаунчер.lnk', 'piy-piy — Игра.lnk')
    $arguments = @('', '--play')
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $linkPath = Join-Path $folder $labels[$i]
        if (-not (Test-Path $linkPath)) { throw "Shortcut missing: $linkPath" }
        $link = $shell.CreateShortcut($linkPath)
        $iconPath, $iconIndex = $link.IconLocation -split ',\s*', 2
        if ($link.TargetPath -ne $launcher -or $link.Arguments -ne $arguments[$i] -or
            $iconPath -ne $launcher -or $iconIndex -ne [string]$i) {
            throw "Invalid shortcut $linkPath ($($link.TargetPath); $($link.Arguments); $($link.IconLocation))"
        }
        Assert-DrawnIcon ([Icons]::Shortcut($linkPath)) $linkPath
    }
}

$app = Start-Process $launcher -PassThru
try {
    $window = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 50 -and $window -eq [IntPtr]::Zero; $attempt++) {
        Start-Sleep -Milliseconds 200
        $window = [Icons]::FindWindow('PiyPiyLauncher', 'piy-piy')
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Launcher window missing' }
    Assert-DrawnIcon ([Icons]::Pixels([Icons]::GetClassIcon($window, -14))) 'large launcher window icon'
    Assert-DrawnIcon ([Icons]::Pixels([Icons]::GetClassIcon($window, -34))) 'small launcher window icon'
} finally {
    if (-not $app.HasExited) { Stop-Process -Id $app.Id }
}
