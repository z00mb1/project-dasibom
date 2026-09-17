import json
from channels.generic.websocket import AsyncWebsocketConsumer


class EmergencyConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.group_name = "emergency_alerts"

        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )

        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def emergency_message(self, event):
        await self.send(text_data=json.dumps({
            "type": "emergencyReceived",
            "message": event["message"],
            "data": event["data"],
        }, ensure_ascii=False))


class GPSLocationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.device_code = self.scope["url_route"]["kwargs"]["device_code"]
        self.group_name = f"gps_location_{self.device_code}"

        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )

        await self.accept()

        print(f"[GPS WebSocket 연결] device_code={self.device_code}, group={self.group_name}")

        await self.send(text_data=json.dumps({
            "type": "connected",
            "message": "GPS WebSocket 연결 성공",
            "data": {
                "device_code": self.device_code
            }
        }, ensure_ascii=False))

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

        print(f"[GPS WebSocket 종료] device_code={self.device_code}")

    async def gps_location(self, event):
        await self.send(text_data=json.dumps({
            "type": "gpsLocation",
            "message": event.get("message"),
            "data": event.get("data"),
        }, ensure_ascii=False))