from datetime import date
from indexnow import pick

XML = b"""<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
<url><loc>https://roamwise.live/</loc></url>
<url><loc>https://roamwise.live/guides/a</loc><lastmod>2026-11-24</lastmod></url>
<url><loc>https://roamwise.live/guides/b</loc><lastmod>2026-11-18T10:00:00Z</lastmod></url>
</urlset>"""

assert pick(XML, False, date(2026, 11, 25)) == ["https://roamwise.live/guides/a"]
assert len(pick(XML, True, date(2026, 11, 25))) == 3
print("ok")
