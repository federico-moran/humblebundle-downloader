BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
}

Describe 'ConvertFrom-SignedUrlReply' {
    # Replies shaped like the getSignedUrlsForEntitlements server action's. Links and signatures are made up.
    It 'gives each file''s signed link by file name, leaving out torrents, and when the links expire' {
        $reply = '0:{"a":"$@1","q":"","i":false,"b":"fakeBuildId"}' + "`n" +
            '1:{"ok":true,"data":{"signedUrls":{"fakebook":{"fakebook_ebook":{' +
            '"fakebook.epub":"https://cdn.example.test/fakebook.epub?t=st=1~exp=2~hmac=aa",' +
            '"fakebook.epub.torrent":"https://cdn.example.test/torrents/fakebook.epub.torrent?t=st=1~exp=2~hmac=bb",' +
            '"fakebook.pdf":"https://cdn.example.test/fakebook.pdf?t=st=1~exp=2~hmac=cc"}}},"expiresAt":"2027-01-02T03:04:05.000Z"}}' + "`n"

        $signed = ConvertFrom-SignedUrlReply -Text $reply

        @($signed.Urls.Keys | Sort-Object) | Should -Be @('fakebook.epub', 'fakebook.pdf')
        $signed.Urls['fakebook.pdf'] | Should -Be 'https://cdn.example.test/fakebook.pdf?t=st=1~exp=2~hmac=cc'
        $signed.ExpiresAt | Should -Be ([datetime]::new(2027, 1, 2, 3, 4, 5, [DateTimeKind]::Utc))
    }

    It 'fails when Humble answers ok:false' {
        $reply = '0:{"a":"$@1","q":"","i":false,"b":"fakeBuildId"}' + "`n" + '1:{"ok":false,"error":"Entitlement not found"}'

        { ConvertFrom-SignedUrlReply -Text $reply } | Should -Throw '*did not sign*Entitlement not found*'
    }

    It 'fails when Humble answers ok:true with no links' {
        $reply = '0:{"a":"$@1","q":"","i":false,"b":"fakeBuildId"}' + "`n" + '1:{"ok":true,"data":{"signedUrls":{},"expiresAt":"2027-01-02T03:04:05.000Z"}}'

        { ConvertFrom-SignedUrlReply -Text $reply } | Should -Throw '*no links*'
    }

    It 'fails without repeating the page when the reply is not a server action''s (an HTML error page, say)' {
        $reply = '<!DOCTYPE html><html><body><h1>The page you requested cannot be found</h1></body></html>'

        { ConvertFrom-SignedUrlReply -Text $reply } | Should -Throw '*not the reply*'
        try { ConvertFrom-SignedUrlReply -Text $reply } catch { $_.Exception.Message | Should -Not -Match '<' }
    }
}
