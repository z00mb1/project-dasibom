"""
Django Management Command: crawl_safe182

사용법:
    python manage.py crawl_safe182
    python manage.py crawl_safe182 --delay 1.5
    python manage.py crawl_safe182 --no-images
    python manage.py crawl_safe182 --update
"""

import logging

from django.core.management.base import BaseCommand

from dasibomapp.crawler import Safe182Crawler


logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = (
        "안전Dream '보호하고 있어요' 데이터 크롤링 → "
        "DB 저장 / 사라진 항목은 status='인계완료' 처리"
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--delay",
            type=float,
            default=1.0,
        )

        parser.add_argument(
            "--no-images",
            action="store_true",
            help="이미지 다운로드 생략",
        )

        parser.add_argument(
            "--update",
            action="store_true",
            help="이미 존재하는 레코드도 업데이트 (기본: 신규만 저장)",
        )

    def handle(self, *args, **options):
        from dasibomapp.models import ProtectedPerson

        delay = options["delay"]
        no_images = options["no_images"]
        do_update = options["update"]

        self.stdout.write(
            self.style.SUCCESS(
                "🚀 보호중인 사람 크롤링 시작"
            )
        )

        self.stdout.write(
            self.style.NOTICE(
                f"설정 | "
                f"delay={delay}s | "
                f"이미지={'생략' if no_images else '저장'} | "
                f"업데이트={'ON' if do_update else 'OFF(신규만)'}"
            )
        )

        # ==================================================
        # 중요
        # ==================================================
        #
        # 예전:
        #   Safe182Crawler(media_root=settings.MEDIA_ROOT)
        #
        # 현재:
        #   저장 위치는 UniversalMediaStorage가 결정
        #
        # MEDIA_WRITE_MODE=local
        #   → 로컬 media/
        #
        # MEDIA_WRITE_MODE=cloudinary
        #   → Cloudinary
        #
        # MEDIA_WRITE_MODE=both
        #   → 둘 다
        #
        # ==================================================

        crawler = Safe182Crawler(
            download_images=not no_images
        )

        # ==================================================
        # 크롤링 전 현재 보호중 ID 스냅샷
        # ==================================================

        db_ids = set(
            ProtectedPerson.objects
            .filter(
                source=ProtectedPerson.Source.SAFE182
            )
            .exclude(
                status=ProtectedPerson.Status.RETURNED
            )
            .values_list(
                "msspsn_idntfccd",
                flat=True,
            )
        )

        self.stdout.write(
            self.style.NOTICE(
                f"📦 현재 DB 보호중/미인계완료 데이터 수: "
                f"{len(db_ids)}"
            )
        )

        seen_ids = set()
        crawl_ok = True

        created_count = 0
        updated_count = 0
        skipped_count = 0
        error_count = 0

        try:
            self.stdout.write(
                self.style.WARNING(
                    "📡 crawl_all 진입"
                )
            )

            for idx, data in enumerate(
                crawler.crawl_all(
                    delay=delay
                ),
                1,
            ):
                self.stdout.write(
                    self.style.NOTICE(
                        "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    )
                )

                self.stdout.write(
                    self.style.NOTICE(
                        f"🔄 [{idx}] 데이터 처리 시작"
                    )
                )

                msspsn_id = data.get(
                    "msspsn_idntfccd",
                    "",
                )

                if not msspsn_id:
                    self.stderr.write(
                        self.style.ERROR(
                            f"❌ [{idx}] 식별코드 없음 → 스킵"
                        )
                    )

                    error_count += 1
                    continue

                self.stdout.write(
                    f"👉 처리 중 ID: {msspsn_id}"
                )

                self.stdout.write(
                    f"📝 이름: "
                    f"{data.get('name', '(이름없음)')} | "
                    f"상태: "
                    f"{data.get('status', '(status 없음)')}"
                )

                seen_ids.add(
                    msspsn_id
                )

                try:
                    existing = (
                        ProtectedPerson.objects
                        .filter(
                            msspsn_idntfccd=msspsn_id
                        )
                        .first()
                    )

                    if existing:
                        self.stdout.write(
                            f"🔎 기존 데이터 존재: "
                            f"{existing.name} "
                            f"({msspsn_id})"
                        )
                    else:
                        self.stdout.write(
                            f"🆕 신규 데이터 감지: "
                            f"{msspsn_id}"
                        )

                    # update 옵션이 없으면 기존 데이터 스킵
                    if existing and not do_update:
                        skipped_count += 1

                        self.stdout.write(
                            self.style.WARNING(
                                f"⏭️ SKIP: 이미 존재하고 "
                                f"update 옵션 꺼짐 "
                                f"({msspsn_id})"
                            )
                        )

                        continue

                    # 모델에 실제 존재하는 필드만 저장
                    model_fields = {
                        f.name
                        for f
                        in ProtectedPerson._meta.get_fields()
                    }

                    safe_data = {
                        k: v
                        for k, v
                        in data.items()
                        if k in model_fields
                    }

                    self.stdout.write(
                        f"🧹 저장 대상 필드 수: "
                        f"{len(safe_data)} | "
                        f"필드: {list(safe_data.keys())}"
                    )

                    # 크롤러 status는 직접 반영하지 않음
                    if "status" in safe_data:
                        self.stdout.write(
                            f"⚠️ safe_data에 status 포함됨 "
                            f"→ 제거: "
                            f"{safe_data.get('status')}"
                        )

                    safe_data.pop(
                        "status",
                        None,
                    )

                    # ==================================================
                    # 기존 데이터 UPDATE
                    # ==================================================

                    if existing:
                        self.stdout.write(
                            "💾 기존 데이터 업데이트 시작"
                        )

                        changed_fields = []

                        for field, value in safe_data.items():
                            if field in (
                                "msspsn_idntfccd",
                                "crawled_at",
                            ):
                                continue

                            old_value = getattr(
                                existing,
                                field,
                                None,
                            )

                            if old_value != value:
                                changed_fields.append(
                                    field
                                )

                            setattr(
                                existing,
                                field,
                                value,
                            )

                        existing.save()

                        updated_count += 1

                        self.stdout.write(
                            self.style.SUCCESS(
                                f"🔁 UPDATE 완료: "
                                f"{existing.name} "
                                f"({msspsn_id})"
                            )
                        )

                        self.stdout.write(
                            f"   변경 필드: "
                            f"{changed_fields if changed_fields else '변경 없음'}"
                        )

                    # ==================================================
                    # 신규 데이터 CREATE
                    # ==================================================

                    else:
                        self.stdout.write(
                            "💾 신규 데이터 저장 시작"
                        )

                        ProtectedPerson.objects.create(
                            **safe_data,
                            status=(
                                ProtectedPerson
                                .Status
                                .PROTECTING
                            ),
                            source=(
                                ProtectedPerson
                                .Source
                                .SAFE182
                            ),
                        )

                        created_count += 1

                        self.stdout.write(
                            self.style.SUCCESS(
                                f"🆕 NEW 저장 완료: "
                                f"{safe_data.get('name', '?')} "
                                f"({msspsn_id})"
                            )
                        )

                except Exception as e:
                    logger.exception(
                        f"DB 저장 실패 ({msspsn_id})"
                    )

                    self.stderr.write(
                        self.style.ERROR(
                            f"❌ ERROR: "
                            f"{msspsn_id} "
                            f"→ {str(e)}"
                        )
                    )

                    error_count += 1

        except RuntimeError as e:
            crawl_ok = False

            self.stderr.write(
                self.style.ERROR(
                    f"\n[크롤링 중단] {e}"
                )
            )

            self.stderr.write(
                self.style.WARNING(
                    "→ 일부 페이지를 가져오지 못했으므로 "
                    "'인계완료' 처리를 건너뜁니다."
                )
            )

        # ==================================================
        # 크롤링 후:
        # 사이트에서 사라진 ID → 인계완료 처리
        # ==================================================

        returned_count = 0

        if crawl_ok:
            vanished_ids = (
                db_ids
                - seen_ids
            )

            self.stdout.write(
                self.style.NOTICE(
                    f"\n📊 크롤링 결과 | "
                    f"DB 기존 ID: {len(db_ids)} | "
                    f"이번에 본 ID: {len(seen_ids)} | "
                    f"사라진 ID 후보: {len(vanished_ids)}"
                )
            )

            if vanished_ids:
                self.stdout.write(
                    self.style.WARNING(
                        f"\n사이트에서 사라진 보호자 "
                        f"{len(vanished_ids)}건 "
                        f"→ '인계완료' 처리 중..."
                    )
                )

                returned_count = (
                    ProtectedPerson.objects
                    .filter(
                        msspsn_idntfccd__in=
                        vanished_ids,
                        source=(
                            ProtectedPerson
                            .Source
                            .SAFE182
                        ),
                    )
                    .update(
                        status=(
                            ProtectedPerson
                            .Status
                            .RETURNED
                        )
                    )
                )

                for pp in (
                    ProtectedPerson.objects
                    .filter(
                        msspsn_idntfccd__in=
                        vanished_ids,
                        source=(
                            ProtectedPerson
                            .Source
                            .SAFE182
                        ),
                    )
                    .only(
                        "msspsn_idntfccd",
                        "name",
                    )
                ):
                    self.stdout.write(
                        f"  [RETURNED] "
                        f"{pp.name} "
                        f"({pp.msspsn_idntfccd})"
                    )

            else:
                self.stdout.write(
                    "\n사라진 보호자 없음 "
                    "(목록 변동 없음)"
                )

        else:
            self.stdout.write(
                self.style.WARNING(
                    "\n크롤링이 완전히 완료되지 않아 "
                    "'인계완료' 처리를 건너뜁니다."
                )
            )

        # ==================================================
        # 최종 결과
        # ==================================================

        self.stdout.write(
            self.style.SUCCESS(
                f"\n✅ 완료! "
                f"신규: {created_count} | "
                f"업데이트: {updated_count} | "
                f"스킵: {skipped_count} | "
                f"인계완료: {returned_count} | "
                f"오류: {error_count}"
            )
        )