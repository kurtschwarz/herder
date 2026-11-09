#!/bin/bash
# Writes the Sparkle appcast for one release to stdout. The publish job in
# .github/workflows/herder-package.yml attaches it to the release beside the
# DMG, and every installed copy reads the one on the latest release.
#
# One item, the release itself: an appcast only has to say what is newest.
# Unsigned, so writing it needs no secret. What Sparkle checks before
# installing is the DMG's own signature, made by the build job.
#
# VERSION    the marketing version, e.g. 0.2.0
# BUILD      the DMG's CFBundleVersion, which is what Sparkle compares
# MINIMUM    the DMG's LSMinimumSystemVersion, e.g. 26.0
# URL        where the DMG is downloaded from
# SIGNATURE  the DMG's EdDSA signature, from sign_update
# LENGTH     the DMG's size in bytes
# LINK       the release's page
# NOTES      the release notes, in Markdown. May be empty.
set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${BUILD:?BUILD is required}"
: "${MINIMUM:?MINIMUM is required}"
: "${URL:?URL is required}"
: "${SIGNATURE:?SIGNATURE is required}"
: "${LENGTH:?LENGTH is required}"
: "${LINK:?LINK is required}"

# CDATA cannot hold "]]>", so any in the notes is split across two sections.
notes="${NOTES:-}"
notes="${notes//]]>/]]]]><![CDATA[>}"
published="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

# Sparkle wants major.minor.patch.
minimum="$MINIMUM"
while [[ "$minimum" != *.*.* ]]; do minimum="$minimum.0"; done

# The build is arm64 only: package.sh builds for the runner's arch alone.
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Herder</title>
        <item>
            <title>Version $VERSION</title>
            <link>$LINK</link>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <pubDate>$published</pubDate>
            <description sparkle:format="markdown"><![CDATA[$notes]]></description>
            <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
        </item>
    </channel>
</rss>
EOF
