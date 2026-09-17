from django.apps import AppConfig


class DasibomappConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'dasibomapp'

    def ready(self):
        # Firebase 초기화 (settings가 아닌 app ready 시점에 1번만 실행)
        from dasibom import firebase_admin_setup

        # 스케줄러 시작
        from . import scheduler
        scheduler.start()