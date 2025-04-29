<#
.SYNOPSIS
    Updates Newtonsoft.Json and Newtonsoft.Json.Schema binaries from their GitHub releases.

.DESCRIPTION
    This script downloads the latest release versions of Newtonsoft.Json and Newtonsoft.Json.Schema from GitHub,
    extracts the required DLL files (net45 versions), and places them in the destination directory.
    It also updates the version numbers in THIRD_PARTY_LICENSES file.

.NOTES
    File Name: update-newtonsoft.ps1
    Author: GitHub Copilot
#>

# Parameters
param(
	[Parameter(Mandatory = $false)]
	[string]$DestinationPath = "$PSScriptRoot\..\..\resources\lib",

	[Parameter(Mandatory = $false)]
	[string]$TempDirectory = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'NewtonsoftUpdate'),

	[Parameter(Mandatory = $false)]
	[string]$LicenseFilePath = "$PSScriptRoot\..\..\THIRD_PARTY_LICENSES"
)

# Create the necessary directories if they don't exist
if (-not (Test-Path -Path $DestinationPath)) {
	New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
	Write-Host "Created destination directory: $DestinationPath"
}

if (Test-Path -Path $TempDirectory) {
	Remove-Item -Path $TempDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null
Write-Host "Created temporary directory: $TempDirectory"

# GitHub API URLs for latest releases
$JsonRepoUrl = 'https://api.github.com/repos/JamesNK/Newtonsoft.Json/releases/latest'
$SchemaRepoUrl = 'https://api.github.com/repos/JamesNK/Newtonsoft.Json.Schema/releases/latest'

# Function to download and extract a release
function Get-LatestRelease {
	param (
		[string]$ApiUrl,
		[string]$OutPath,
		[string]$ProductName
	)

	try {
		Write-Host "Fetching latest $ProductName release information..."
		$releaseInfo = Invoke-RestMethod -Uri $ApiUrl -Method Get -Headers @{
			'Accept' = 'application/vnd.github.v3+json'
		}

		$zipAsset = $releaseInfo.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1

		if ($null -eq $zipAsset) {
			throw 'No ZIP asset found in the latest release'
		}

		$zipUrl = $zipAsset.browser_download_url
		$zipPath = Join-Path -Path $OutPath -ChildPath $zipAsset.name

		Write-Host "Downloading $ProductName v$($releaseInfo.tag_name) from $zipUrl"
		Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

		$extractPath = Join-Path -Path $OutPath -ChildPath $ProductName
		if (Test-Path -Path $extractPath) {
			Remove-Item -Path $extractPath -Recurse -Force
		}
		New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

		Write-Host "Extracting $ProductName ZIP archive..."
		Unblock-File -Path $zipPath
		Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

		return @{
			Version     = $releaseInfo.tag_name
			ExtractPath = $extractPath
		}
	}
	catch {
		Write-Error "Failed to download and extract $ProductName release: $_"
		throw
	}
}

# Function to find and copy a DLL file
function Copy-DllFile {
	param (
		[string]$ExtractPath,
		[string]$DllName,
		[string]$Destination,
		[string]$Version
	)

	try {
		$dllPath = Get-ChildItem -Path $ExtractPath -Recurse -Filter $DllName |
			Where-Object { $_.FullName -match '(/|\\)net45(/|\\)' } |
			Select-Object -First 1 -ExpandProperty FullName

		if ($dllPath) {
			Copy-Item -Path $dllPath -Destination $Destination -Force
			# Get actual assembly version from the DLL
			Write-Host "Successfully updated $DllName to version $Version"
			return @{
				Success = $true
				Version = $Version
			}
		}
		else {
			throw "Could not find $DllName in the net45 directory"
		}
	}
	catch {
		Write-Error "Error processing ${DllName}: $_"
		throw
	}
}

# Function to update version numbers in THIRD_PARTY_LICENSES file
function Update-LicenseFile {
	param (
		[string]$FilePath,
		[string]$JsonVersion,
		[string]$SchemaVersion
	)

	try {
		if (-not (Test-Path -Path $FilePath)) {
			Write-Warning "License file not found at $FilePath - skipping update"
			return
		}

		$content = Get-Content -Path $FilePath -Raw

		# Update Newtonsoft.Json version
		$content = $content -replace '(?<=\*\* Newtonsoft\.Json; version )[0-9.]+(?= -- https://github\.com/JamesNK/Newtonsoft\.Json)', $JsonVersion

		# Update Newtonsoft.Json.Schema version
		$content = $content -replace '(?<=\*\* Newtonsoft\.Json\.Schema; version )[0-9.]+(?= -- https://github\.com/JamesNK/Newtonsoft\.Json\.Schema)', $SchemaVersion

		# Write updated content back to file
		Set-Content -Path $FilePath -Value $content -NoNewline
		Write-Host "Successfully updated version numbers in $FilePath"
	}
	catch {
		Write-Error "Error updating license file: $_"
		throw
	}
}

# Get the latest releases
try {
	$jsonRelease = Get-LatestRelease -ApiUrl $JsonRepoUrl -OutPath $TempDirectory -ProductName 'Newtonsoft.Json'
	$schemaRelease = Get-LatestRelease -ApiUrl $SchemaRepoUrl -OutPath $TempDirectory -ProductName 'Newtonsoft.Json.Schema'

	# Copy the DLL files to the destination
	Copy-DllFile -ExtractPath $jsonRelease.ExtractPath -DllName 'Newtonsoft.Json.dll' -Destination $DestinationPath -Version $jsonRelease.Version | Out-Null
	Copy-DllFile -ExtractPath $schemaRelease.ExtractPath -DllName 'Newtonsoft.Json.Schema.dll' -Destination $DestinationPath -Version $schemaRelease.Version | Out-Null

	# Update the license file with new version numbers
	Update-LicenseFile -FilePath $LicenseFilePath -JsonVersion $jsonRelease.Version -SchemaVersion $schemaRelease.Version

	Write-Host 'Update completed successfully!' -ForegroundColor Green
}
catch {
	Write-Error "Error updating Newtonsoft binaries: $_"
	exit 1
}
finally {
	# Clean up temporary files
	if (Test-Path -Path $TempDirectory) {
		Write-Host 'Cleaning up temporary files...'
		Remove-Item -Path $TempDirectory -Recurse -Force
	}
}
