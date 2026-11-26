BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
}

Describe 'Find-ServerActionId' {
    # Minified JS shaped like the site's public chunks. The IDs are made up.
    It 'finds the ID of the named action among the page''s scripts' {
        $scripts = @(
            '(globalThis.TURBOPACK||=[]).push(["chunks/a.js",{1:e=>{"use strict";let t=1}}]);'
            'var r=(0,x.createServerReference)("70aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01",x.callServer,void 0,x.findSourceMapURL,"getSignedUrlsForEntitlements");'
        )

        Find-ServerActionId -Script $scripts -Name getSignedUrlsForEntitlements | Should -Be '70aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01'
    }

    It 'picks the right one of several actions in one script' {
        $script = 'let a=(0,x.createServerReference)("70bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb01",x.callServer,void 0,x.findSourceMapURL,"redeemEntitlementAction"),' +
            'b=(0,x.createServerReference)("70cccccccccccccccccccccccccccccccccccccccc02",x.callServer,void 0,x.findSourceMapURL,"getSignedUrlsForEntitlements"),' +
            'Y=(0,x.createServerReference)("40dddddddddddddddddddddddddddddddddddddddd03",x.callServer,void 0,x.findSourceMapURL,"recordDownload");'

        Find-ServerActionId -Script $script -Name getSignedUrlsForEntitlements | Should -Be '70cccccccccccccccccccccccccccccccccccccccc02'
        Find-ServerActionId -Script $script -Name recordDownload | Should -Be '40dddddddddddddddddddddddddddddddddddddddd03'
    }

    It 'returns nothing when no script names the action' {
        $script = 'let a=(0,x.createServerReference)("70bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb01",x.callServer,void 0,x.findSourceMapURL,"addToCartAction");'

        Find-ServerActionId -Script $script, '' -Name getSignedUrlsForEntitlements | Should -BeNullOrEmpty
    }
}
