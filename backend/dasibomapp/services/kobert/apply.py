# dasibomapp/services/kobert/apply.py

from dasibomapp.models import MissingPerson
from dasibomapp.services.kobert.infer import classify_detail

THRESHOLD = 0.4  # 현실적인 임계값

def apply_kobert_to_all():
    qs = MissingPerson.objects.exclude(detail__isnull=True).exclude(detail="")

    print(f"🔍 대상 실종자 수: {qs.count()}")

    for person in qs:
        result = classify_detail(person.detail)

        # confidence 기준으로 label 결정
        labels = {
            k: (v >= THRESHOLD)
            for k, v in result["confidence"].items()
        }

        person.kobert_labels = labels
        person.kobert_confidence = result["confidence"]
        person.save(update_fields=["kobert_labels", "kobert_confidence"])

        print(f"✅ 적용 완료: {person.seq}")
