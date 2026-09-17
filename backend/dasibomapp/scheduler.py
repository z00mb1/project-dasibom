from apscheduler.schedulers.background import BackgroundScheduler
from django_apscheduler.jobstores import DjangoJobStore
from django.core.management import call_command
import logging

logger = logging.getLogger(__name__)

def crawl_protected():
    logger.info("크롤링 시작: 보호중이에요")
    call_command("crawl_safe182")

def crawl_missing():
    logger.info("크롤링 시작: 찾고있어요")
    call_command("crawl_safe182_missing")

def sync_missing():
    logger.info("동기화 시작: etc_spfeatr")
    call_command("sync_safe182_missing")

def start():
    scheduler = BackgroundScheduler()
    scheduler.add_jobstore(DjangoJobStore(), "default")

    # 매일 새벽 3시에 실행
    scheduler.add_job(crawl_protected, "cron", hour=3, minute=0,
                      id="crawl_protected", replace_existing=True)
    scheduler.add_job(crawl_missing,   "cron", hour=3, minute=30,
                      id="crawl_missing",   replace_existing=True)
    scheduler.add_job(sync_missing,    "cron", hour=4, minute=0,
                      id="sync_missing",    replace_existing=True)

    scheduler.start()
    logger.info("스케줄러 시작됨")