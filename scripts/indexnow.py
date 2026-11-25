"""Tell IndexNow search engines (Bing, Yandex, Seznam, Naver) about new or changed pages.

Usage: python indexnow.py [--all]
Without --all, only sitemap URLs whose lastmod is within the last 2 days are sent.
"""
import json, sys, urllib.request, xml.etree.ElementTree as ET
from datetime import date, timedelta

HOST = "roamwise.live"
KEY = "a97fdb5e702b9752db92b42bd24c88df"  # also served by Caddy at /<KEY>.txt
NS = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def pick(sitemap_xml, send_all, today):
    since = today - timedelta(days=2)
    urls = []
    for u in ET.fromstring(sitemap_xml).findall("s:url", NS):
        loc = u.findtext("s:loc", namespaces=NS)
        lastmod = u.findtext("s:lastmod", default="", namespaces=NS)[:10]
        if send_all or (lastmod and date.fromisoformat(lastmod) >= since):
            urls.append(loc)
    return urls


def main():
    send_all = "--all" in sys.argv
    with urllib.request.urlopen(f"https://{HOST}/sitemap.xml", timeout=30) as r:
        urls = pick(r.read(), send_all, date.today())
    print(f"{len(urls)} URL(s) to submit")
    if not urls:
        return
    body = json.dumps({"host": HOST, "key": KEY, "keyLocation": f"https://{HOST}/{KEY}.txt",
                       "urlList": urls}).encode()
    req = urllib.request.Request("https://api.indexnow.org/indexnow", data=body,
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=30) as r:
        print("IndexNow response:", r.status)  # 200/202 = accepted


if __name__ == "__main__":
    main()
