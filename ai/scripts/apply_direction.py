import sys
import os
import torch
import cv2
import dlib
import numpy as np
from PIL import Image, ImageDraw
import torchvision.transforms as transforms
from insightface.app import FaceAnalysis
from argparse import Namespace

sys.path.insert(0, r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM')

from models.psp import pSp
from datasets.augmentations import AgeTransformer
from utils.common import tensor2im

MODEL_PATH = r'C:\Users\ekzmd\sam_korean_best_model.pt'
LANDMARK_PATH = r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM\shape_predictor_68_face_landmarks.dat'
DIRECTION_PATH = r'C:\Users\ekzmd\interfacegan\asian_direction.npy'
INPUT_IMAGE = r'C:\Users\ekzmd\Desktop\dasibom-project\dasibom-fullft\data\raw\aihub\Training\01.원천데이터\0893_1972_15_00000024_F.png'
OUTPUT_DIR = r'C:\Users\ekzmd\interfacegan\results'
TARGET_AGE = 40

# 보정 강도 테스트 범위 (-: 서양인 방향 제거, +: 더 동양인 방향)
ALPHAS = [-10.0, -5.0, -2.0, 0.0, 2.0, 5.0, 10.0]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("전처리 모델 로딩 중...")
face_app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640))
face_detector = dlib.get_frontal_face_detector()
landmark_predictor = dlib.shape_predictor(LANDMARK_PATH)

print("SAM 모델 로딩 중...")
ckpt = torch.load(MODEL_PATH, map_location='cpu')
opts = ckpt['opts']
opts['checkpoint_path'] = MODEL_PATH
opts['device'] = 'cuda'
opts = Namespace(**opts)
model = pSp(opts)
model.eval()
model.cuda()

direction = np.load(DIRECTION_PATH)  # (18, 512)
direction_tensor = torch.tensor(direction, dtype=torch.float32).cuda()  # (18, 512)
print("방향 벡터 로딩 완료!")

def to_pil(tensor):
    result = tensor2im(tensor)
    if isinstance(result, Image.Image):
        return result
    return Image.fromarray(result)

def crop_and_align_face(image_np):
    faces = face_app.get(image_np)
    if not faces:
        raise ValueError("얼굴을 찾을 수 없습니다.")
    face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    x1, y1, x2, y2 = [int(v) for v in face.bbox]
    w, h = x2-x1, y2-y1
    pad = int(max(w, h) * 0.4)
    x1 = max(0, x1-pad)
    y1 = max(0, y1-pad)
    x2 = min(image_np.shape[1], x2+pad)
    y2 = min(image_np.shape[0], y2+pad)
    cropped = image_np[y1:y2, x1:x2]
    cropped = cv2.resize(cropped, (256, 256))
    rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
    dets = face_detector(rgb, 1)
    if not dets:
        return Image.fromarray(rgb)
    shape = landmark_predictor(rgb, dets[0])
    landmarks = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)])
    left_eye = landmarks[36:42].mean(axis=0)
    right_eye = landmarks[42:48].mean(axis=0)
    angle = np.degrees(np.arctan2(right_eye[1]-left_eye[1], right_eye[0]-left_eye[0]))
    center = tuple(map(int, ((left_eye+right_eye)/2)))
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    aligned = cv2.warpAffine(rgb, M, (256, 256))
    return Image.fromarray(aligned)

transform = transforms.Compose([
    transforms.Resize((256, 256)),
    transforms.ToTensor(),
    transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
])

img_np = cv2.imdecode(np.fromfile(INPUT_IMAGE, dtype=np.uint8), cv2.IMREAD_COLOR)
aligned_face = crop_and_align_face(img_np)
input_tensor = transform(aligned_face).unsqueeze(0).cuda()
age_transformer = AgeTransformer(target_age=TARGET_AGE)

with torch.no_grad():
    input_with_age = age_transformer(input_tensor.squeeze().cpu()).unsqueeze(0).cuda()
    result_base, codes = model(input_with_age, return_latents=True, randomize_noise=False)
    base_pil = to_pil(result_base[0])
    base_pil.save(os.path.join(OUTPUT_DIR, 'alpha_0.0_base.jpg'))
    print("기본 노화 결과 저장 완료")

print(f"\n방향 벡터 보정 테스트 시작...")

for alpha in ALPHAS:
    with torch.no_grad():
        codes_mod = codes.clone()
        codes_mod = codes_mod + alpha * direction_tensor.unsqueeze(0)
        result_mod, _ = model.decoder([codes_mod], input_is_latent=True, randomize_noise=False)
        result_mod = model.face_pool(result_mod)
        mod_pil = to_pil(result_mod[0])

    # base와 나란히 비교
    combined = Image.new('RGB', (512, 280), (30, 30, 30))
    combined.paste(base_pil.resize((256, 256)), (0, 0))
    combined.paste(mod_pil.resize((256, 256)), (256, 0))
    draw = ImageDraw.Draw(combined)
    draw.text((10, 258), "노화(보정없음)", fill=(200, 200, 200))
    draw.text((266, 258), f"alpha={alpha}", fill=(255, 220, 100))

    fname = f'alpha_{alpha}.jpg'.replace('-', 'neg')
    combined.save(os.path.join(OUTPUT_DIR, fname))
    print(f"  → alpha={alpha} 저장 완료")

print(f"\n완료! {OUTPUT_DIR} 폴더 확인해줘.")