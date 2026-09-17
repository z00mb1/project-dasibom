# dasibomapp/management/commands/update_missingperson_risk.py

from django.core.management.base import BaseCommand
from dasibomapp.models import MissingPerson
from dasibomapp.services.risk_engine import (
    extract_ai_features_from_detail,
    calculate_risk_level,
)


class Command(BaseCommand):
    help = "Update MissingPerson risk level using rule-based logic"

    def handle(self, *args, **options):
        qs = MissingPerson.objects.all()
        updated = 0

        for person in qs:
            # 1️⃣ detail 기반 특징 추출
            diseases, behaviors, score = extract_ai_features_from_detail(
                person.detail or ""
            )

            # 2️⃣ 위험도 계산
            risk_level = calculate_risk_level(score)

            # 3️⃣ DB 반영
            person.ai_diseases = diseases
            person.ai_behaviors = behaviors
            person.ai_risk_level = risk_level
            person.ai_confidence = min(score / 10, 1.0)

            person.save(update_fields=[
                "ai_diseases",
                "ai_behaviors",
                "ai_risk_level",
                "ai_confidence",
            ])
            updated += 1

        self.stdout.write(self.style.SUCCESS(
            f"Done! Updated risk for {updated} records."
        ))
