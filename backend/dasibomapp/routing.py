from django.urls import re_path
from .consumers import EmergencyConsumer, GPSLocationConsumer

websocket_urlpatterns = [
    re_path(r"ws/emergency/$", EmergencyConsumer.as_asgi()),
    re_path(r"ws/gps/(?P<device_code>[^/]+)/$", GPSLocationConsumer.as_asgi()),

]