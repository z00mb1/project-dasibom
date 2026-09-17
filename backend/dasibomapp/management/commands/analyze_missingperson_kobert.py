# dasibomapp/management/commands/analyze_missingperson_kobert.py

from django.core.management.base import BaseCommand
from dasibomapp.models import MissingPerson
from dasibomapp.services.kobert.infer import classify_detail

THRESHOLD = 0.6


class Command(BaseCommand):
    help = "KoBERT 기반 MissingPerson detail 의미 분류 적용"

    def handle(self, *args, **options):
        qs = (
            MissingPerson.objects
            .exclude(detail__isnull=True)
            .exclude(detail="")
            .filter(kobert_labels__isnull=True)  # 🔑 이미 분석된 건 제외
        )

        total = qs.count()
        updated = 0

        self.stdout.write(f"🔍 KoBERT 분석 대상: {total}명")

        for person in qs:
            result = classify_detail(person.detail)

            # confidence 기반 boolean label 결정
            labels = {
                key: (value >= THRESHOLD)
                for key, value in result["confidence"].items()
            }

            person.kobert_labels = labels
            person.kobert_confidence = result["confidence"]

            person.save(update_fields=["kobert_labels", "kobert_confidence"])
            updated += 1

            self.stdout.write(f"✅ 적용 완료: {person.seq}")

        self.stdout.write(
            self.style.SUCCESS(f"🎉 KoBERT 분석 완료: {updated}/{total}")
        )
