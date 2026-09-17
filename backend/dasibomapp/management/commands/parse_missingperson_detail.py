# dasibomapp/management/commands/parse_missingperson_detail.py

from django.core.management.base import BaseCommand
from dasibomapp.models import MissingPerson
from dasibomapp.services.rule_parser import parse_detail_text


class Command(BaseCommand):
    help = "MissingPerson.detail 규칙기반 파싱 → parsed_* 필드 업데이트"

    def handle(self, *args, **options):
        qs = MissingPerson.objects.all()
        total = qs.count()
        updated = 0

        self.stdout.write(f"Parsing {total} MissingPerson records...")

        for person in qs:
            parsed = parse_detail_text(person.detail)

            changed_fields = []
            for field, value in parsed.items():
                if value is not None and getattr(person, field) != value:
                    setattr(person, field, value)
                    changed_fields.append(field)

            if changed_fields:
                person.save(update_fields=changed_fields)
                updated += 1

        self.stdout.write(
            self.style.SUCCESS(f"Done! Updated {updated}/{total} records.")
        )
