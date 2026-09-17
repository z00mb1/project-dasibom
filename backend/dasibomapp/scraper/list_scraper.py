#todo seq,이름,나이,성별,날짜,썸네일만 추출
#todo list_scraper.py
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from webdriver_manager.chrome import ChromeDriverManager
from bs4 import BeautifulSoup
import time


class Safe182ListScraper:

    BASE_MAIN = "https://www.safe182.go.kr/home/main.do"
    LIST_URL = "https://www.safe182.go.kr/home/lcm/lcmMssList.do?rptDscd=2"

    def __init__(self):
        options = webdriver.ChromeOptions()
        options.add_argument("--disable-blink-features=AutomationControlled")
        options.add_argument("--headless")   # <- 서버 배포 시 HEADLESS 추천
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")

        self.driver = webdriver.Chrome(
            service=Service(ChromeDriverManager().install()),
            options=options
        )

    def open_main(self):
        self.driver.get(self.BASE_MAIN)
        time.sleep(1)

    def go_list(self, page=1):
        url = f"{self.LIST_URL}&pageIndex={page}"
        self.driver.get(url)
        time.sleep(1)
        return BeautifulSoup(self.driver.page_source, "html.parser")

    def detect_total_pages(self):
        soup = self.go_list(1)
        page_info = soup.select_one(".page_info")
        if not page_info:
            return 1
        return int(page_info.text.split("/")[-1])

    def parse_list_items(self, soup):
        items = []
        cards = soup.select("ul > li.col-sm-4")

        for li in cards:
            try:
                seq = li.select_one("dt a")["onclick"].split("'")[1]
                name = li.select_one("dt a").text.strip()

                dd = li.select("dd")

                gender = dd[0].select_one(".gal-desc").text.strip() if len(dd) > 0 else None
                age = dd[1].select_one(".gal-desc").text.strip() if len(dd) > 1 else None
                missing_date = dd[2].select_one(".gal-desc").text.strip() if len(dd) > 2 else None
                address = dd[3].select_one(".gal-desc").text.strip() if len(dd) > 3 else None

                img = li.select_one("img")
                photo_url = img.get("src") if img else None

                items.append({
                    "seq": seq,
                    "name": name,
                    "gender": gender,
                    "age": age,
                    "missing_date": missing_date,
                    "address": address,
                    "photo_url": photo_url,
                })
            except:
                continue

        return items

    def quit(self):
        self.driver.quit()
