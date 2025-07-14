<#
.SYNOPSIS
Add or update an annotation to a Kubernetes resource

.PARAMETER ResourceName
Kind of Kubernetes resource to add annotation to, e.g. ingress, service, deployment, etc.

.PARAMETER AnnotationName
Name of annotation to add or update

.PARAMETER AnnotationValue
Value of annotation to add or update

.PARAMETER Match
Regex to match names. Defaults to .* (all)

.PARAMETER Namespace
Namespace of Kubernetes resource to add annotation to, defaults to default

.EXAMPLE
.\Add-Annotation.ps1 -ResourceName ingress -AnnotationName "nginx.ingress.kubernetes.io/service-upstream" -AnnotationValue "true"

Searches for all ingress resources in the default namespace and adds or updates the annotation nginx.ingress.kubernetes.io/service-upstream=true

.EXAMPLE
.\Add-Annotation.ps1 -ResourceName ingress -AnnotationName "qqqq" -AnnotationValue "true" -match min.* | ft

Add qqqq=true to all ingress resources in the default namespace that start with min and format the output as a table

.OUTPUTS
PSCustomObject with ResourceName and Name properties
#>
function Add-Annotation {
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $ResourceName,
    [Parameter(Mandatory)]
    [string] $AnnotationName,
    [Parameter(Mandatory)]
    [string] $AnnotationValue,
    [string] $Match = '.*',
    [string] $Namespace = "default"
)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"
    Write-VerboseStatus "ResourceName: $ResourceName, AnnotationName: $AnnotationName, AnnotationValue: $AnnotationValue, Match: $Match, Namespace: $Namespace"

    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw "kubectl is not installed"
    }

    Write-VerboseStatus "kubectl get $ResourceName -n $Namespace -o json"
    $resources = (kubectl get $ResourceName -n $Namespace -o json | ConvertFrom-Json).items
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve $ResourceName in $Namespace"
    }

    foreach ($resource in $resources | Where-Object { $_.metadata.name -match $Match }) {
        $name = $resource.metadata.name
        Write-VerboseStatus "Adding annotation $AnnotationName=$AnnotationValue to $ResourceName $name in $Namespace namespace"
        $result = [PSCustomObject]@{
            ResourceName = $ResourceName
            Name = $name
            Exists = $true
            ValueMatched = $false
            Updated = $false
        }
        try {
            $existingValue = $resource.metadata.annotations.$AnnotationName
            if ($existingValue -eq $AnnotationValue) {
                Write-VerboseStatus "Annotation $AnnotationName=$AnnotationValue already exists on $ResourceName $name in $Namespace namespace"
                $result.ValueMatched = $true
                $result
                continue
            }
        } catch {
            $result.Exists = $false
        }

        if ($PSCmdlet.ShouldProcess("$ResourceName $name", "Add annotation $AnnotationName=$AnnotationValue")) {
            $null = kubectl annotate $ResourceName $name "$AnnotationName=$AnnotationValue" --namespace $Namespace --overwrite
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to add annotation $AnnotationName=$AnnotationValue to $ResourceName $name in $Namespace namespace"
            }
            $result.Updated = $true
        }
        $result
    }
}