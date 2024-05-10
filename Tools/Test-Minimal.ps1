function Test-Minimal {
    param (
        [string] $src_HostAddress = "http://my-k8s-example1.com"
    )

    Invoke-RestMethod "$src_HostAddress/info"

}