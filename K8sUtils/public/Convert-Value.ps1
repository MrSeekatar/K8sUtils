<#
.SYNOPSIS
One pass replacement of variables in a file, similar to qetza.replacetokens.replacetokens-task.replacetokens in Azure DevOps

.DESCRIPTION
This is useful if you have a values.yaml file that has #{variable}# in it, and you want to replace those with values to run locally.
.PARAMETER ValuesFile
Name of the file to replace variables in

.PARAMETER VariableFile
Yaml file of variables to replace

.PARAMETER Variables
Has table of variables to replace, will override VariableFile

.PARAMETER StartDelimiter
Start delimiter for the variable to replace, defaults to #{

.PARAMETER EndDelimiter
End delimiter for the variable to replace, defaults to }#

.EXAMPLE
$newFolder = '~/code/PlatformApi'
$oldFolder = '~/temp/PlatformApi'
"dev","test","qa","prod","staging","demo" | % {
    Convert-Value -ValuesFile "$newFolder/DevOps/deploy/helm/api/values.yaml" -VariablesFile "$newFolder/DevOps/deploy/variables/variables-$_.yml" -Variables @{Environment=$_;ImageTag='1.2.3'} > "~/temp/valuesyaml/values-platformapi-$_.yaml"
}
bc ~/temp/valuesyaml "$oldFolder/Docker/helm/api"

Convert using a yaml file, then compare the results

.EXAMPLE
Convert-Value "~/code/BackendTemplate/DevOps/helm/values.yaml" `
        -Variables @{
            imageTag = 114090
            fullEnvironmentName = "dev"
            'cert-password' = $env:cert_password
            environment = "dev"
            availabilityZoneLower = "sc"
        } | Out-File ./new-values.yml

Convert using a hashtable of variables

.OUTPUTS
The file with the variables replaced
#>
function Convert-Value {
    [CmdletBinding()]
    param (
        [ValidateScript({ Test-Path $_ -PathType Leaf})]
        [string] $ValuesFile,
        [hashtable] $Variables,
        [string] $VariablesFile,
        [string] $StartDelimiter = '#{',
        [string] $EndDelimiter = '}#'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($VariablesFile) {
        $fileVariables = (Get-Content $VariablesFile -Raw) | ConvertFrom-Yaml
        foreach ($v in $fileVariables.variables) {
            Set-Variable -Name $v.name -Value $v.value
        }
    }

    if ($Variables) {
        foreach ($k in $Variables.Keys) {
            Set-Variable -Name $k -Value $Variables[$k]
        }
    }

    $content = (Get-Content $ValuesFile -Raw) -replace "$StartDelimiter([\w-]+)$EndDelimiter", '${$1}'
    Write-Verbose "Content: $content"
    $ExecutionContext.InvokeCommand.ExpandString($content)
}