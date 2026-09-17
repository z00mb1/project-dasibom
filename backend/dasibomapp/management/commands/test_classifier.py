"""
AI 분류기 동작 테스트
사용법:
    python manage.py test_classifier
    python manage.py test_classifier --text "파란색 점퍼 착용"
    python manage.py test_classifier --live   # DB 실제 데이터로 테스트
"""

from django.core.management.base import BaseCommand


# 테스트용 샘플 데이터
SAMPLES = [
    # (텍스트, 예상카테고리)
    ("파란색 점퍼에 흰색 운동화 착용",              "착의외형"),
    ("오른쪽 팔에 흉터 있음, 키 약 165cm",          "신체특징"),
    ("치매 증상 있으며 귀가 능력 없음",              "건강장애"),
    ("지적장애 3급, 혼자 대중교통 이용 불가",        "건강장애"),
    ("마지막 목격 장소는 서울역 근처",               "기타참고"),
    ("검정 바지, 흰 티셔츠, 안경 착용",             "착의외형"),
    ("보행 시 왼쪽 다리 절뚝임",                    "신체특징"),
    ("휴대폰 미소지, 차량 없음",                    "기타참고"),
]


class Command(BaseCommand):
    help = "AI 분류기 동작 테스트"

    def add_arguments(self, parser):
        parser.add_argument(
            "--text",
            type=str,
            default=None,
            help="직접 텍스트 입력해서 분류 테스트"
        )
        parser.add_argument(
            "--live",
            action="store_true",
            help="DB의 실제 MissingPerson 데이터 10건으로 테스트"
        )
        parser.add_argument(
            "--count",
            type=int,
            default=10,
            help="--live 시 테스트할 건수 (기본 10)"
        )

    def handle(self, *args, **options):
        # 모델 로드 확인
        self.stdout.write("모델 로딩 중...")
        try:
            from dasibomapp.ml_classifier import classify_etc, classify_batch
            # 더미 호출로 로드 확인
            classify_etc("테스트")
            self.stdout.write(self.style.SUCCESS("✅ 모델 로드 성공\n"))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f"❌ 모델 로드 실패: {e}"))
            return

        # ── 단일 텍스트 테스트 ──────────────────────────────────────
        if options["text"]:
            self._test_single(options["text"], classify_etc)
            return

        # ── DB 실제 데이터 테스트 ───────────────────────────────────
        if options["live"]:
            self._test_live(options["count"], classify_batch)
            return

        # ── 기본: 샘플 데이터 테스트 ────────────────────────────────
        self._test_samples(classify_etc)

    # ────────────────────────────────────────────────────────────────
    def _test_single(self, text, classify_etc):
        self.stdout.write(f"입력: {text}")
        category, confidence = classify_etc(text)
        color = self.style.SUCCESS if confidence >= 0.6 else self.style.WARNING
        self.stdout.write(color(
            f"결과: {category} (신뢰도: {confidence:.1%})"
        ))

    # ────────────────────────────────────────────────────────────────
    def _test_samples(self, classify_etc):
        self.stdout.write("=" * 55)
        self.stdout.write("샘플 데이터 분류 테스트")
        self.stdout.write("=" * 55)

        correct = 0
        for text, expected in SAMPLES:
            category, confidence = classify_etc(text)
            is_correct = category == expected
            if is_correct:
                correct += 1

            status = "✅" if is_correct else "❌"
            conf_style = self.style.SUCCESS if confidence >= 0.6 else self.style.WARNING

            self.stdout.write(
                f"{status} [{conf_style(f'{confidence:.1%}')}] "
                f"{category:<8} (예상: {expected:<8}) | {text}"
            )

        self.stdout.write("=" * 55)
        self.stdout.write(self.style.SUCCESS(
            f"정확도: {correct}/{len(SAMPLES)} ({correct/len(SAMPLES):.1%})"
        ))

    # ────────────────────────────────────────────────────────────────
    def _test_live(self, count, classify_batch):
        from dasibomapp.models import MissingPerson

        qs = (
            MissingPerson.objects
            .exclude(etc_spfeatr="")
            .only("id", "name", "etc_spfeatr", "etc_ai_category", "etc_ai_confidence")  # 🔥 payload → 새 필드
            [:count]
        )

        rows = list(qs)
        if not rows:
            self.stdout.write(self.style.WARNING("etc_spfeatr가 있는 데이터가 없습니다."))
            return

        texts = [r.etc_spfeatr.strip() for r in rows]
        results = classify_batch(texts)

        self.stdout.write("=" * 65)
        self.stdout.write(f"DB 실제 데이터 {len(rows)}건 테스트")
        self.stdout.write("=" * 65)

        low_conf_count = 0
        for mp, (category, confidence) in zip(rows, results):
            cached = mp.etc_ai_category or "-"  # 🔥 payload → 필드 직접 참조
            is_low = confidence < 0.6

            if is_low:
                low_conf_count += 1

            conf_style = self.style.WARNING if is_low else self.style.SUCCESS
            cache_mark = "💾" if cached != "-" else "  "

            self.stdout.write(
                f"{cache_mark} [{conf_style(f'{confidence:.1%}')}] "
                f"{category:<8} | 캐시: {cached:<8} | "
                f"{mp.name} → {mp.etc_spfeatr[:40]}..."
            )

        self.stdout.write("=" * 65)
        self.stdout.write(
            f"저신뢰(60% 미만): {low_conf_count}건 / 전체 {len(rows)}건"
        )