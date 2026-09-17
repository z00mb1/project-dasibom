import requests
import xmltodict
from datetime import datetime
from math import ceil
from django.core.management.base import BaseCommand
from dasibomapp.models import MissingPerson


class Command(BaseCommand):
    help = "Fetch ALL Missing Person data with safe paging (safe182 API)"

    def handle(self, *args, **options):

        self.stdout.write(self.style.WARNING("🔍 Fetching missing person data (XML mode, paging)..."))

        url = "https://www.safe182.go.kr/api/lcm/findChildList.do"

        total_saved = 0

        # ================================
        # 1) 먼저 totalCount 조회
        # ================================
        params = {
            "esntlId": "10000852",
            "authKey": "b2fef5b9118c42a6",
            "rowSize": 100,
            "pageNo": 1,
            "xmlUseYN": "Y",
        }

        res = requests.post(url, data=params, timeout=15)
        res.raise_for_status()

        data = xmltodict.parse(res.text)
        document = data.get("document")
        if not document:
            self.stderr.write(self.style.ERROR("❌ document 노드 없음"))
            return

        total_count = int(document.get("totalCount", 0))
        total_pages = ceil(total_count / 100)

        self.stdout.write(self.style.WARNING(f"📌 Total count = {total_count}, total pages = {total_pages}"))

        # ================================
        # 2) 페이지 반복 조회
        # ================================
        for page_no in range(1, total_pages + 1):

            self.stdout.write(self.style.WARNING(f"➡ Fetching page {page_no} ..."))

            params["pageNo"] = page_no
            res = requests.post(url, data=params, timeout=15)
            res.raise_for_status()

            data = xmltodict.parse(res.text)
            document = data.get("document")
            if not document:
                continue

            list_node = document.get("list")
            if not list_node:
                continue

            items = list_node.get("item")
            if not items:
                continue

            if isinstance(items, dict):
                items = [items]

            # ================================
            # 저장
            # ================================
            for item in items:

                seq = item.get("msspsnIdntfccd")
                if not seq:
                    continue

                MissingPerson.objects.update_or_create(
                    seq=seq,
                    defaults={
                        "name": item.get("nm"),
                        "age": safe_int(item.get("age")),
                        "sex": item.get("sexdstnDscd"),
                        "missing_date": parse_date(item.get("occrde")),
                        "detail": item.get("etcSpfeatr"),
                        "photo_url": item.get("tknphotoFile"),
                        "last_updated": datetime.now(),
                    }
                )

                total_saved += 1

        self.stdout.write(self.style.SUCCESS(f"✅ DONE — Saved total {total_saved} records."))


def parse_date(date_str):
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y%m%d").date()
    except:
        return None


def safe_int(v):
    try:
        return int(v)
    except:
        return None
