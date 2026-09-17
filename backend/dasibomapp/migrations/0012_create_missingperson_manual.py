from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('dasibomapp', '0006_phonerequest_dasibomapp__phone_b8adba_idx'),
    ]

    operations = [
        migrations.CreateModel(
            name='MissingPerson',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('seq', models.CharField(max_length=50, unique=True)),
                ('category', models.CharField(max_length=100, blank=True, default="")),
                ('name', models.CharField(max_length=100)),
                ('gender', models.CharField(max_length=10, blank=True, default="")),
                ('age', models.IntegerField(null=True, blank=True)),
                ('current_age', models.IntegerField(null=True, blank=True)),
                ('missing_date', models.DateField(null=True, blank=True)),
                ('address', models.CharField(max_length=255, blank=True, default="")),
                ('clothes', models.CharField(max_length=255, blank=True, default="")),
                ('description', models.TextField(blank=True, default="")),
                ('detail', models.TextField(blank=True, default="")),
                ('photo_url', models.TextField(blank=True, default="")),
                ('last_updated', models.DateTimeField(auto_now=True)),
            ],
        ),
    ]
