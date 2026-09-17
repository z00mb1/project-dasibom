from django.core.management.base import BaseCommand
from dasibomapp.services.safe182 import sync_safe182_missing_persons


class Command(BaseCommand):
    help = "Sync ALL missing persons data from Safe182 OpenAPI"

    def handle(self, *args, **options):
        self.stdout.write("Starting Safe182 missing persons FULL sync...")

        page = 1
        total_created = 0
        total_updated = 0

        while True:
            result = sync_safe182_missing_persons(page=page)

            created = result["created"]
            updated = result["updated"]

            total_created += created
            total_updated += updated

            self.stdout.write(
                f"Page {page}: created={created}, updated={updated}"
            )

            # 더 이상 데이터 없으면 종료
            if created + updated == 0:
                break

            page += 1

        self.stdout.write(
            self.style.SUCCESS(
                f"Done! TOTAL created={total_created}, updated={total_updated}"
            )
        )
