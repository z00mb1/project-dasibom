from django.core.management.base import BaseCommand
import csv

class Command(BaseCommand):
    help = "etc_spfeatr CSV export"

    def handle(self, *args, **kwargs):
        from dasibomapp.models import MissingPerson

        data = MissingPerson.objects.exclude(
            etc_spfeatr=""
        ).values_list("etc_spfeatr", flat=True)[:500]

        with open("etc_data.csv", "w", newline="", encoding="utf-8-sig") as f:
            writer = csv.writer(f)
            writer.writerow(["etc_spfeatr"])

            for row in data:
                writer.writerow([row])

        self.stdout.write(self.style.SUCCESS("CSV 생성 완료"))