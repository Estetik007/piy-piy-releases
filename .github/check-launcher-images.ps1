$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TestWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")]
    public static extern bool PostMessageW(IntPtr window, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string caption);
    [DllImport("gdi32.dll")]
    public static extern uint GetPixel(IntPtr dc, int x, int y);
}
'@
[void][TestWindow]::SetProcessDPIAware()

function Wait-ForWindow([string] $caption) {
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $window = [TestWindow]::FindWindow('PiyPiyLauncher', $caption)
        if ($window -ne [IntPtr]::Zero) { return $window }
        Start-Sleep -Milliseconds 200
    }
    throw "Launcher window did not appear: $caption"
}

function Assert-Photo([IntPtr] $window, [double[]] $bounds, [string] $area) {
    # Keep the test window above other processes in the disposable runner.
    [void][TestWindow]::SetWindowPos($window, [IntPtr](-1), 0, 0, 0, 0, 0x43)
    Start-Sleep -Milliseconds 550
    $rect = [TestWindow+Rect]::new()
    if (-not [TestWindow]::GetClientRect($window, [ref]$rect)) { throw 'Could not read launcher bounds' }
    $dc = [TestWindow]::GetDC($window)
    if ($dc -eq [IntPtr]::Zero) { throw 'Could not read launcher pixels' }
    $colors = [System.Collections.Generic.HashSet[uint32]]::new()
    try {
        for ($row = 0; $row -lt 9; $row++) {
            for ($column = 0; $column -lt 12; $column++) {
                $x = [int]($rect.Right * ($bounds[0] + ($bounds[2] - $bounds[0]) * $column / 11))
                $y = [int]($rect.Bottom * ($bounds[1] + ($bounds[3] - $bounds[1]) * $row / 8))
                $color = [TestWindow]::GetPixel($dc, $x, $y)
                if ($color -ne [uint32]::MaxValue) { [void]$colors.Add($color) }
            }
        }
    } finally {
        [void][TestWindow]::ReleaseDC($window, $dc)
    }
    if ($colors.Count -lt 16) { throw "$area appears blank ($($colors.Count) distinct colors)" }
    Write-Host "$area rendered ($($colors.Count) distinct colors)"
}

$installer = Start-Process ./release-files/piy-piy-setup-0.1.7-x64.exe -ArgumentList '/S' -Wait -PassThru
if ($installer.ExitCode -ne 0) { throw "Installer exited with $($installer.ExitCode)" }
$launcher = Start-Process "$env:LOCALAPPDATA\Programs\piy-piy\piy-piy-launcher.exe" -PassThru
try {
    $window = Wait-ForWindow 'piy-piy'
    Assert-Photo $window @(0.12, 0.21, 0.58, 0.76) 'Home cover'
    [void][TestWindow]::PostMessageW($window, 0x111, [IntPtr]104, [IntPtr]::Zero)
    Assert-Photo $window @(0.09, 0.24, 0.61, 0.46) 'News cover'
    [void][TestWindow]::PostMessageW($window, 0x111, [IntPtr]106, [IntPtr]::Zero)
    [void][TestWindow]::PostMessageW($window, 0x111, [IntPtr]116, [IntPtr]::Zero)
    $gallery = Wait-ForWindow 'piy-piy · Фото выпуска'
    Assert-Photo $gallery @(0.28, 0.25, 0.72, 0.75) 'Full-screen photo'
} finally {
    if (-not $launcher.HasExited) { Stop-Process -Id $launcher.Id }
}
