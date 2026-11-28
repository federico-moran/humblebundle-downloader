BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
}

Describe 'Get-PagePayload' {
    It 'joins the data chunks of a page into one payload, decoding escaped quotes, backslashes and unicode' {
        # Written by hand in the shape of Humble's Next.js pages; every value is made up.
        $html = @'
<!DOCTYPE html><html><head><title>Your Library</title></head><body>
<script>(self.__next_f=self.__next_f||[]).push([0])</script>
<script>self.__next_f.push([1,"1:\"$Sreact.fragment\"\n2:{\"title\":\"Caf\u00e9 \\\"Quoted\\\" Guide\",\"path\":\"C:\\\\books\"}\n"])</script>
<script>self.__next_f.push([1,"3:[\"second chunk\"]\n"])</script>
</body></html>
'@

        $payload = Get-PagePayload -Html $html

        $payload | Should -BeExactly ("1:`"`$Sreact.fragment`"`n" + '2:{"title":"Café \"Quoted\" Guide","path":"C:\\books"}' + "`n3:[`"second chunk`"]`n")
    }

    It 'returns nothing for a page without data chunks (an error page, say)' {
        $html = '<!DOCTYPE html><html><body><h1>The page you requested cannot be found</h1></body></html>'

        Get-PagePayload -Html $html | Should -BeNullOrEmpty
    }
}
