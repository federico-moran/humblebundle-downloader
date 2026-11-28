# Wraps a made-up React Server Components payload in page HTML the way Humble's Next.js pages carry it:
# split into self.__next_f.push([1,"..."]) chunks of JavaScript string literals. Dot-source it in BeforeAll.
function New-FakePage([string]$Payload, [int]$ChunkSize = 200) {
    $chunks = for ($i = 0; $i -lt $Payload.Length; $i += $ChunkSize) {
        $literal = ConvertTo-Json -InputObject $Payload.Substring($i, [Math]::Min($ChunkSize, $Payload.Length - $i)) -Compress
        "<script>self.__next_f.push([1,$literal])</script>"
    }
    "<!DOCTYPE html><html><head><title>Fake</title></head><body><script>(self.__next_f=self.__next_f||[]).push([0])</script>$(-join $chunks)</body></html>"
}
