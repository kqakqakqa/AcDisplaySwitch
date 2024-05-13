param([switch]$Run)
Write-Host "AC Display Switch" -ForegroundColor:DarkCyan
Add-Type -AssemblyName System.Windows.Forms

# set admin permission
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $argRun = if ($Run) { "-Run" } else { "" }
    Start-Process -Verb RunAs ($PSHome + "\powershell.exe") "-ExecutionPolicy Bypass -File `"$PSCommandPath`" $argRun"
    exit
}

function ChooseMode {
    Write-Host "[1] Run this directly    " -NoNewline
    if ($scheduledTask) {
        Write-Host "[3] Unregister scheduled task    " -NoNewline
    }
    else {
        Write-Host "[2] Register this file as scheduled task    " -NoNewline
    }
    Write-Host "Choose a mode:" -ForegroundColor:Yellow -NoNewline
    $choice = Read-Host
    switch ($choice) {
        1 {
            Execute
        }
        2 {
            RegisterScheduledTask
        }
        3 {
            UnregisterScheduledTask
        }
        default {
            ChooseMode
        }
    }
}

function Execute {
    # get power status
    $isAcOnline = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq "Online"
    Write-Host "AC online: " -NoNewline
    Write-Host "$isAcOnline" -ForegroundColor:DarkGray

    # get display devices
    $displayDevices = Get-PnpDevice -Class display -FriendlyName *RTX*
    Write-Host "Display devices: " -NoNewline
    Write-Host $displayDevices.FriendlyName -ForegroundColor:DarkGray

    if ($isAcOnline) {
        Write-Host "Enabling... " -ForegroundColor:Yellow -NoNewline
        $errorDisplayDevices = $displayDevices | Where-Object { $_.Status -eq "Error" }
        if ($errorDisplayDevices) {
            Enable-PnpDevice -Confirm:$false -InstanceId (Get-PnpDevice -Class display -FriendlyName *RTX* -Status Error).InstanceId
            Write-Host "Enabled" -ForegroundColor:Yellow
        }
        else {
            Write-Host "Nothing to enable" -ForegroundColor:Yellow
        }
    }
    else {
        Write-Host "Disabling... " -ForegroundColor:Yellow -NoNewline
        $okDisplayDevices = $displayDevices | Where-Object { $_.Status -eq "Ok" }
        if ($okDisplayDevices) {
            Disable-PnpDevice -Confirm:$false -InstanceId (Get-PnpDevice -Class display -FriendlyName *RTX* -Status Ok).InstanceId
            Write-Host "Disabled" -ForegroundColor:Yellow
        }
        else {
            Write-Host "Nothing to disable" -ForegroundColor:Yellow
        }
    }
}

function RegisterScheduledTask {
    $scheduledTask = Get-ScheduledTask "AcDisplaySwitch" -ErrorAction SilentlyContinue
    if ($scheduledTask) {
        Write-Host "Scheduled task already exists"
    }
    else {
        # new scheduled task
        Write-Host "Registering scheduled task... " -ForegroundColor:Yellow -NoNewline
        $action = New-ScheduledTaskAction -Execute ($PSHome + "\powershell.exe") -Argument ("-WindowStyle Hidden -ExecutionPolicy Bypass  -File `"$PSCommandPath`" -Run")
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $userSid = $currentIdentity.User.Value
        $principal = New-ScheduledTaskPrincipal -Id "Author" -UserId $userSid -RunLevel Highest -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
        $triggerClass = Get-CimClass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
        $trigger = $triggerClass | New-CimInstance -ClientOnly
        $trigger.Enabled = $true
        $trigger.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name="Microsoft-Windows-Kernel-Power"] and EventID=105]]</Select></Query></QueryList>'
    
        $regSchTaskParams = @{
            TaskName  = "AcDisplaySwitch"
            # Description = ""
            # TaskPath  = "\"
            Action    = $action
            Principal = $principal
            Settings  = $settings
            Trigger   = $trigger
        }

        Register-ScheduledTask @regSchTaskParams
        Write-Host "Registered" -ForegroundColor:Yellow
    }
}

function UnregisterScheduledTask {
    $scheduledTask = Get-ScheduledTask "AcDisplaySwitch" -ErrorAction SilentlyContinue
    if ($scheduledTask) {
        Write-Host "Unegistering scheduled task... " -ForegroundColor:Yellow -NoNewline
        Unregister-ScheduledTask -TaskName "AcDisplaySwitch" -Confirm:$false
        Write-Host "Unregistered" -ForegroundColor:Yellow
    }
    else {
        Write-Host "Scheduled task already not exists"
    }
}



$scheduledTask = Get-ScheduledTask "AcDisplaySwitch" -ErrorAction SilentlyContinue
if ($scheduledTask) {
    Write-Host "Scheduled task already exists."
}

if (-not $Run) {
    ChooseMode
}

if ($Run) {
    Execute
}

if (-not $Run) {
    Write-Host "Press any key to exit..." -ForegroundColor:DarkCyan
    [Console]::Readkey() | Out-Null ;
}
else {
    Write-Host "Done" -ForegroundColor:DarkCyan
}
exit 