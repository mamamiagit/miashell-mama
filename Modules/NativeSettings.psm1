Set-StrictMode -Version Latest

function Initialize-ToolkitNativeSettings {
    # Fixed source, never profile- or user-supplied code. Compilation alone does
    # not call user32. Only getters are public on the compiled bridge; writes use the journaled wrapper.
    if ($null -ne ('WindowsPerformanceToolkit.NativePreferencesV4' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace WindowsPerformanceToolkit {
    public static class NativePreferencesV4 {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SystemParametersInfoW(uint action, uint parameter, IntPtr data, uint flags);

        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow
        private static int[] ReadValues(uint action, int bytes, bool animation) {
            IntPtr data = Marshal.AllocHGlobal(bytes);
            try {
                for (int i = 0; i < bytes; i += 4) Marshal.WriteInt32(data, i, 0);
                if (animation) Marshal.WriteInt32(data, 0, bytes);
                if (!SystemParametersInfoW(action, animation ? (uint)bytes : 0, data, 0))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                int[] values = new int[animation ? 1 : 3];
                for (int i = 0; i < values.Length; i++) values[i] = Marshal.ReadInt32(data, animation ? 4 : i * 4);
                return values;
            } finally { Marshal.FreeHGlobal(data); }
        }
        public static int[] GetMouse() { return ReadValues(0x0003, 12, false); }
        public static int GetAnimation() { return ReadValues(0x0048, 8, true)[0]; }

        // Reviewed setters are internal. The PowerShell wrapper reaches them only
        // after validating a durable current-user write intent and confirmation.
        private static void WriteValues(uint action, int[] values, bool animation) {
            int bytes = animation ? 8 : 12;
            IntPtr data = Marshal.AllocHGlobal(bytes);
            try {
                if (animation) {
                    Marshal.WriteInt32(data, 0, bytes);
                    Marshal.WriteInt32(data, 4, values[0]);
                } else {
                    for (int i = 0; i < 3; i++) Marshal.WriteInt32(data, i * 4, values[i]);
                }
                // Persist current-user preference and notify applications.
                if (!SystemParametersInfoW(action, animation ? (uint)bytes : 0, data, 0x0001 | 0x0002))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally { Marshal.FreeHGlobal(data); }
        }
        internal static void SetMouse(int threshold1, int threshold2, int acceleration) {
            if (threshold1 < 0 || threshold2 < 0 || acceleration < 0 || acceleration > 2)
                throw new ArgumentOutOfRangeException("mouse");
            WriteValues(0x0004, new int[] { threshold1, threshold2, acceleration }, false);
        }
        internal static void SetAnimation(int enabled) {
            if (enabled != 0 && enabled != 1) throw new ArgumentOutOfRangeException("enabled");
            WriteValues(0x0049, new int[] { enabled }, true);
        }
    }
}
'@ -ErrorAction Stop
}

function Get-ToolkitNativeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('mouse','animations')][string]$OperationId)
    $result = [pscustomobject]@{ State='Error'; Value=$null; Source='SystemParametersInfoW'; Detail='Windows interactive desktop required.' }
    if ($env:OS -ne 'Windows_NT') { $result.State='Unsupported'; return $result }
    try {
        Initialize-ToolkitNativeSettings
        if ($OperationId -eq 'mouse') {
            $values = [WindowsPerformanceToolkit.NativePreferencesV4]::GetMouse()
            $result.Value = [pscustomobject]@{ Threshold1=$values[0]; Threshold2=$values[1]; Acceleration=$values[2] }
        } else {
            $result.Value = [pscustomobject]@{ MinAnimate=[WindowsPerformanceToolkit.NativePreferencesV4]::GetAnimation() }
        }
        $result.State='Known'; $result.Detail='Current session API read; this is not a system backup.'
    } catch {
        $result.Detail='Native preference read failed (desktop access, policy, compilation, or Windows API error). No value is assumed.'
    }
    $result
}


function Invoke-ToolkitNativeWrite {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId,
          [Parameter(Mandatory)][ValidateSet('mouse','animations')][string]$OperationId,[switch]$Restore)
    if ($env:OS -ne 'Windows_NT' -or -not (Get-ToolkitOperationPermission -SystemInfo (Get-ToolkitSystemInfo)).Allowed) { throw 'Interactive Windows desktop required.' }
    $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context (Get-ToolkitContext)
    $entry=@($record.Entries | Where-Object { $_.Id -eq $OperationId })
    $required=if ($Restore) { 'Restoring' } else { 'Applying' }
    if ($entry.Count -ne 1 -or $record.Status -ne $required -or $entry[0].State -ne $required) { throw 'Native write requires durable matching intent.' }
    if (-not $Restore -and -not $record.Validation -and -not (Test-ToolkitNativeValidation -Directory $Directory)) { throw 'Native validation is missing or expired.' }
    $value=if ($Restore) { $entry[0].Original } else { $entry[0].Target }
    $value=ConvertTo-ToolkitOperationValue -OperationId $OperationId -Value $value
    if (-not $PSCmdlet.ShouldProcess($OperationId,'Write the durably journaled preference value')) { return }
    Initialize-ToolkitNativeSettings
    $type='WindowsPerformanceToolkit.NativePreferencesV4' -as [type]
    if ($OperationId -eq 'mouse') {
        $method=$type.GetMethod('SetMouse',[Reflection.BindingFlags]'NonPublic,Static')
        $null=$method.Invoke($null,[object[]]@([int]$value.Threshold1,[int]$value.Threshold2,[int]$value.Acceleration))
    } else {
        $method=$type.GetMethod('SetAnimation',[Reflection.BindingFlags]'NonPublic,Static')
        $null=$method.Invoke($null,[object[]]@([int]$value.MinAnimate))
    }
}
Export-ModuleMember -Function Get-ToolkitNativeState, Invoke-ToolkitNativeWrite
