$ErrorActionPreference = "Stop"

$utils = (Resolve-Path "$PSScriptRoot\Modules\Utils").Path
Import-Module $utils

$variables = (Resolve-Path "$PSScriptRoot\variables.ps1").Path
. $variables


$TEMPLATES_DIR = Join-Path $PSScriptRoot "templates"


function New-Environment {
    $service = Get-Service $EPMD_SERVICE_NAME -ErrorAction SilentlyContinue
    if($service) {
        Stop-Service -Force -Name $EPMD_SERVICE_NAME
        Start-ExternalCommand { sc.exe delete $EPMD_SERVICE_NAME } -ErrorMessage "Failed to delete exiting EPMD service"
    }
    New-Directory -RemoveExisting $EPMD_DIR
    New-Directory $EPMD_SERVICE_DIR
    New-Directory $EPMD_LOG_DIR
}

function New-EPMDWindowsAgent {
    $epmdBinary = Join-Path $ERTS_DIR "bin\epmd.exe"
    if(!(Test-Path $epmdBinary)) {
        Throw "The EPMD binary $epmdBinary doesn't exist. Cannot configure the EPMD agent Windows service"
    }
    $context = @{
        "service_name" = $EPMD_SERVICE_NAME
        "service_display_name" = "DCOS EPMD Windows Agent"
        "service_description" = "Windows Service for the DCOS EPMD Agent"
        "service_binary" = $epmdBinary
        "service_arguments" = "-port $EPMD_PORT"
        "log_dir" = $EPMD_LOG_DIR
    }
    Start-RenderTemplate -TemplateFile "$TEMPLATES_DIR\windows-service.xml" -Context $context -OutFile "$EPMD_SERVICE_DIR\epmd-service.xml"
    $serviceWapper = Join-Path $EPMD_SERVICE_DIR "epmd-service.exe"
    Invoke-WebRequest -UseBasicParsing -Uri $SERVICE_WRAPPER_URL -OutFile $serviceWapper
    $p = Start-Process -FilePath $serviceWapper -ArgumentList @("install") -NoNewWindow -PassThru -Wait
    if($p.ExitCode -ne 0) {
        Throw "Failed to set up the EPMD Windows service. Exit code: $($p.ExitCode)"
    }
    Start-ExternalCommand { sc.exe failure $EPMD_SERVICE_NAME reset=5 actions=restart/1000 }
    Start-ExternalCommand { sc.exe failureflag $EPMD_SERVICE_NAME 1 }
    Start-Service $EPMD_SERVICE_NAME
}

try {
    New-Environment
    New-EPMDWindowsAgent
    Open-WindowsFirewallRule -Name "Allow inbound TCP Port $EPMD_PORT for EPMD" -Direction "Inbound" -LocalPort $EPMD_PORT -Protocol "TCP"
    Open-WindowsFirewallRule -Name "Allow inbound UDP Port $EPMD_PORT for EPMD" -Direction "Inbound" -LocalPort $EPMD_PORT -Protocol "UDP"
} catch {
    Write-Output $_.ToString()
    exit 1
}
Write-Output "Successfully installed the EPMD Windows agent"
exit 0
