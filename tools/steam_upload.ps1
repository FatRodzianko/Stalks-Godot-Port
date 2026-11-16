<#
.SYNOPSIS
    Writes the two SteamPipe build scripts for a release build, and prints the
    steamcmd command that uploads it.

.DESCRIPTION
    SteamPipe is told what to upload by two text files in Valve's VDF format:
    an app build script naming the branch and the depots, and a depot build
    script naming the folder of files. Both are short, both are regenerated
    every time, and neither belongs in version control — they carry a depot id
    that is read off the partner site and a path that is local to one machine.

    This script writes them into the content root's parent and then stops. It
    does NOT upload. Uploading needs a Steam login and two-factor code, which
    is the owner's to type, and a failed upload is much easier to understand
    when the command that caused it is visible. Pass -Run to have it invoke
    steamcmd for you once you have read the command.

    See docs/publishing.md for where each value comes from.

.PARAMETER DepotId
    The depot to upload into, read from the Steamworks partner site under
    SteamPipe > Depots. It is NOT the App ID, and it is not safe to guess.

.PARAMETER Branch
    The branch to set live. Use a named test branch while testing. "default"
    publishes to everybody who owns the game, so it is refused here unless
    -AllowDefaultBranch is also passed.

.EXAMPLE
    .\tools\steam_upload.ps1 -DepotId 1821801 -Branch testing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int] $DepotId,

    [Parameter(Mandatory = $true)]
    [string] $Branch,

    # The folder holding the release build. The default matches the "Windows
    # Release" export preset in export_presets.cfg.
    [string] $ContentRoot = "$PSScriptRoot\..\..\stalks-release",

    [string] $Description = "Stalks Stalks Stalks $(Get-Date -Format 'yyyy-MM-dd HH:mm')",

    [switch] $AllowDefaultBranch,

    [switch] $Run
)

$ErrorActionPreference = "Stop"

$AppId = 1821800

if ($Branch -eq "default" -and -not $AllowDefaultBranch) {
    throw "Branch 'default' publishes to everyone who owns the game. Pass -AllowDefaultBranch if that is really what you want."
}

if (-not (Test-Path $ContentRoot)) {
    throw "No such folder: $ContentRoot. Export the 'Windows Release' preset first - see docs/exporting.md."
}

$ContentRoot = (Resolve-Path $ContentRoot).Path

# What a usable build looks like. Checked here because an empty or wrong
# folder uploads successfully and breaks only when somebody installs it.
$exe = Join-Path $ContentRoot "StalksStalksStalks.exe"
$pck = Join-Path $ContentRoot "StalksStalksStalks.pck"
foreach ($required in @($exe, $pck)) {
    if (-not (Test-Path $required)) {
        throw "Missing $required. That folder does not hold a complete build."
    }
}

# Valve's own guidance: steam_appid.txt is a development-only file and must
# not ship. The export preset excludes it; this catches a hand-copied one.
$stray = Join-Path $ContentRoot "steam_appid.txt"
if (Test-Path $stray) {
    throw "steam_appid.txt is in the build folder and must not be uploaded. Delete it and export again."
}

$outputDir = Split-Path -Parent $ContentRoot
$appScript = Join-Path $outputDir "app_build_$AppId.vdf"
$depotScript = Join-Path $outputDir "depot_build_$DepotId.vdf"
$logDir = Join-Path $outputDir "steam_build_output"

$appVdf = @"
"appbuild"
{
	"appid" "$AppId"
	"desc" "$Description"
	"buildoutput" "$logDir"
	"contentroot" "$ContentRoot"
	"setlive" "$Branch"
	"preview" "0"
	"local" ""

	"depots"
	{
		"$DepotId" "$depotScript"
	}
}
"@

$depotVdf = @"
"DepotBuildConfig"
{
	"DepotID" "$DepotId"
	"contentroot" "$ContentRoot"

	"FileMapping"
	{
		"LocalPath" "*"
		"DepotPath" "."
		"recursive" "1"
	}

	"FileExclusion" "steam_appid.txt"
	"FileExclusion" "*.pdb"
}
"@

Set-Content -Path $appScript -Value $appVdf -Encoding UTF8
Set-Content -Path $depotScript -Value $depotVdf -Encoding UTF8

Write-Output "Wrote $appScript"
Write-Output "Wrote $depotScript"
Write-Output "Content root: $ContentRoot"
Write-Output ""
Write-Output "Files that will be uploaded:"
Get-ChildItem -Path $ContentRoot -Recurse -File |
    ForEach-Object { Write-Output ("  {0}  ({1:N0} bytes)" -f $_.Name, $_.Length) }
Write-Output ""

$command = "steamcmd +login <your-steam-account> +run_app_build `"$appScript`" +quit"
Write-Output "Now run, from the Steamworks SDK's tools\ContentBuilder\builder folder:"
Write-Output ""
Write-Output "  $command"
Write-Output ""
Write-Output "Branch '$Branch' is set live by that command. Nobody sees it until you"
Write-Output "give the branch a password or select it on the partner site."

if ($Run) {
    $steamcmd = Get-Command steamcmd -ErrorAction SilentlyContinue
    if ($null -eq $steamcmd) {
        throw "steamcmd is not on PATH. Run the command above from the SDK folder yourself."
    }
    & $steamcmd.Source "+run_app_build" $appScript "+quit"
}
