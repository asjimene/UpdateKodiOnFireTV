<#
.SYNOPSIS
	Updates Kodi on all Amazon Fire TVs on the local network
.DESCRIPTION
	Updates Kodi on all Amazon Fire TVs on the local network (only tested on Fire TV sticks)
.EXAMPLE
	PS C:\> .\UpdateKodiOnFire.ps1
.NOTES
	Ensure you can adb connect to your Amazon Fire TV devices before running this script, no version checking is currently done on the
	Fire TV devices, and Kodi will be reinstalled (with settings kept) regardless of whether the app is already up-to-date
	
	Author:
	Andrew Jimenez (https://twitter.com/AndrewJimenez_, https://github.com/asjimene)
#>

$ProgressPreference = "SilentlyContinue"

if (-not (Test-Path "$env:TEMP\oui.txt" -ErrorAction SilentlyContinue)) {
	Write-Output "Downloading Latest OUI List"
	Invoke-WebRequest -Uri "http://linuxnet.ca/ieee/oui.txt" -OutFile $env:TEMP\oui.txt	
}

$LatestOUIs = Get-Content "$env:TEMP\oui.txt"
$OUIHashTable = @{ }
Write-Output "Parsing OUI List"
foreach ($Line in $LatestOUIs -split '[\r\n]') {
	if ($Line -match "^[A-F0-9]{6}" -and $Line -like "*Amazon *") {
		#$line        
		# Line looks like: 2405F5     (base 16)        Integrated Device Technology (Malaysia) Sdn. Bhd.
		$LinetoProcess = ($Line -replace '\s+', ' ').Replace(' (base 16) ', '|').Trim() + "`n"
		try {
			$HashTableData = $LinetoProcess.Split('|')
			$OUIHashTable.Add($HashTableData[0], $HashTableData[1])
		}
		catch [System.ArgumentException] { } # Catch if mac is already added to hash table
	}
}
Write-Output "Finished Parsing OUI List"

$ActiveDevices = Get-NetNeighbor -State Reachable | ForEach-Object {
	[PSCustomObject]@{
		IP     = $_.IPAddress
		MAC    = $_.LinkLayerAddress
		Vendor = $OUIHashtable.Get_Item($($_.LinkLayerAddress.Replace("-", "").Substring(0, 6)))
	}
}

$amazonDevices = $ActiveDevices | Where-Object Vendor -Match "Amazon"
Write-Output "Amazon Devices:" $amazonDevices.IP
# clear adb connections

foreach ($amazonDevice in $amazonDevices) {
	adb disconnect
	& adb connect $amazonDevice.IP
	$deviceIP = (& adb devices)[1].split("`t")[0]
	$modelgroup = & adb -s $deviceIP shell getprop ro.nrdp.modelgroup
	$abigroup = & adb -s $deviceIP shell getprop ro.product.cpu.abi
	#$abigroup
	if ($modelgroup -like "*FIRETV*") {
		Write-Output "Model Group is like FIRETV - Continuing"

		if ($abigroup -like "armeabi-v7a*") {
			$URI = "http://mirrors.kodi.tv/releases/android/arm/"
			
		}
		else {
			$URI = "http://mirrors.kodi.tv/releases/android/arm64-v8a/"
		}
		$rels = Invoke-WebRequest $URI
		$apkdownload = (($rels.Links) | Where-Object { $_.outertext -like "kodi*.apk" } | Sort-Object { [version]($_.outertext.split("-")[1]) } -Descending | Select-Object -first 1).outertext	
		#Write-Output "Checking if $apkdownload already exists"
		if (-not (Test-Path "$env:USERPROFILE\Downloads\$apkdownload" -ErrorAction SilentlyContinue)) {
			Write-Output "Downloading $apkdownload"
			Invoke-WebRequest "$URI$apkdownload" -OutFile "$env:USERPROFILE\Downloads\$apkdownload"
		}
		Write-Host "Installing $apkdownload to $deviceIP in 20 seconds, ctrl+c to cancel before then"
		Start-Sleep 20
		& adb -s $deviceIP install -r "$env:USERPROFILE\Downloads\$apkdownload"
	}

}
adb disconnect